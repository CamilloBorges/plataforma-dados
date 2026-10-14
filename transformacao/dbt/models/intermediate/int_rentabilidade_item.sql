-- Rentabilidade por Setor, por mês, filial e produto, até a margem depois das quebras (as despesas
-- do F360 entram no vw_rentabilidade_item). Porta do executar_etl_mes do notebook "Fato Item" do
-- Fabric, só para os meses do Logus (a partir de var inicio_logus). Diferenças já decididas:
--   * estoque inicial pela regra do Camillo (int_estoque_inicial_mes) e final pela posição do fim do
--     mês (int_estoque_final_mes);
--   * custo zerado trocado pelo último custo positivo do produto ATÉ a data, na própria filial e,
--     se não houver, na filial 1 (o Fabric pegava o último da filial 1 de todo o histórico);
--   * compras pelo mês da EMISSÃO da nota (Camillo, 14/10/2026: a data de entrada no Logus é a do
--     lançamento, não a da chegada física). O Fabric exigia emissão e entrada no mesmo mês;
--   * quantidade comprada = embalagens × quantidade por embalagem. Hoje dá o mesmo que o Fabric: em
--     todas as notas desde 02/2026 a quantidade por embalagem é 1 (o lançamento no Logus já converte).
-- Regras do Camillo mantidas (14/10/2026):
--   * CMV = quantidade vendida × custo FINAL do mês ("custo da última nota"); quebra atualizada =
--     quantidade × custo final. No açougue, o custo médio do mês (Fabric);
--   * estoque final = posição do fim do mês (a regra do inventário até o dia 5 é só do inicial).
with meses as (
    select generate_series(
        date '{{ var("inicio_logus") }}',
        date_trunc('month', current_date)::date,
        interval '1 month'
    )::date as mes
),

-- Departamento do produto na Rentabilidade: o do Logus, ou o do de/para (config.depara_departamento,
-- ex.: CAFETERIA redistribuída); a regra com seção vale antes da regra sem seção. O produto levado
-- fica com a seção = departamento de origem (como no Fabric).
produtos as (
    select
        p.codigo_produto,
        coalesce(d.departamento_destino, p.departamento) as departamento,
        case when d.departamento_destino is not null then p.departamento else p.secao end as secao,
        p.departamento                                  as departamento_logus,
        p.grupo, p.subgrupo, p.descricao, p.descricao_completa, p.unidade_medida, p.ativo
    from {{ source('api', 'vw_produto') }} p
    left join lateral (
        select dd.departamento_destino
        from {{ source('config', 'depara_departamento') }} dd
        where dd.departamento_origem = p.departamento
          and (dd.secao_origem = p.secao or dd.secao_origem is null)
        order by dd.secao_origem nulls last
        limit 1
    ) d on true
    where p.origem = 'Logus'
),

custo_acougue as (
    select make_date(c.ano, c.mes, 1) as mes, c.codigo_produto, c.custo_unitario
    from {{ ref('stg_fabric__custo_medio_acougue') }} c
    where c.custo_unitario > 0
),

vendas as (
    select
        date_trunc('month', v.data_emissao)::date       as mes,
        v.filial_id,
        v.codigo_produto,
        sum(v.quantidade) filter (where bk)             as qtd_vendida_bk,
        sum(v.valor_total) filter (where bk)            as vlr_venda_bruto_bk,
        sum(v.valor_liquido) filter (where bk)          as vlr_vendido_bk,
        sum(v.quantidade) filter (where not bk)         as qtd_vendida,
        sum(v.valor_total) filter (where not bk)        as vlr_venda_bruto,
        sum(v.valor_liquido) filter (where not bk)      as vlr_vendido,
        sum(v.desconto)                                 as vlr_desconto,
        sum(v.impostos)                                 as vlr_impostos_vendas
    from (
        select
            s.*,
            coalesce(s.cpf_cnpj_cliente::text, '') = '57903451000156' as bk,  -- venda para o Bom Kafe
            s.valor_total - coalesce(s.desconto_item, 0) - coalesce(s.desconto_proporcional, 0) as valor_liquido,
            coalesce(s.desconto_item, 0) + coalesce(s.desconto_proporcional, 0) as desconto,
            round(coalesce(s.valor_icms, 0) + coalesce(s.valor_pis, 0) + coalesce(s.valor_cofins, 0)
                  + coalesce(s.valor_fcp, 0), 2) as impostos
        from {{ ref('stg_logus__vendas_item') }} s
        where not s.venda_cancelada and not s.item_cancelado and s.status_nota = 1
          and s.data_emissao >= date '{{ var("inicio_logus") }}'
    ) v
    group by 1, 2, 3
),

compras as (
    select
        date_trunc('month', c.data_emissao)::date       as mes,
        c.filial_id,
        c.codigo_produto,
        sum(c.quantidade * c.quantidade_embalagem)      as qtd_comprada,
        sum(c.valor_total)                              as vlr_comprado,
        sum(round(coalesce(c.valor_icms, 0) + coalesce(c.valor_pis, 0) + coalesce(c.valor_cofins, 0)
                  + coalesce(c.valor_fcp, 0), 2))       as vlr_impostos_compras
    from {{ ref('stg_logus__compras_item') }} c
    where c.situacao_nota = 3
      and c.data_emissao >= date '{{ var("inicio_logus") }}'
    group by 1, 2, 3
),

transformacoes as (
    select
        date_trunc('month', t.data_transformacao)::date as mes,
        t.filial_id,
        t.codigo_produto_destino                        as codigo_produto,
        sum(t.quantidade_destino)                       as qtd_requisicoes
    from {{ ref('stg_logus__transformacoes') }} t
    where t.data_transformacao >= date '{{ var("inicio_logus") }}'
    group by 1, 2, 3
),

quebras as (
    select
        date_trunc('month', e.data)::date               as mes,
        e.filial_id,
        e.codigo_produto,
        sum(e.quantidade_quebras)                       as qtd_quebra,
        sum(e.valor_quebras)                            as vlr_quebra
    from {{ ref('stg_logus__estoque_diario') }} e
    where e.data >= date '{{ var("inicio_logus") }}'
    group by 1, 2, 3
),

inicial as (
    select i.mes, i.filial_id, i.codigo_produto, i.data_estoque, i.origem, i.quantidade,
           coalesce(nullif(i.custo_logus, 0), c.custo_positivo) as custo_logus
    from {{ ref('int_estoque_inicial_mes') }} i
    left join {{ ref('int_estoque_custo') }} c
      on c.filial_id = i.filial_id and c.codigo_produto = i.codigo_produto
     and c.data <= i.data_estoque and (c.proxima_data is null or c.proxima_data > i.data_estoque)
),

final as (
    select mes, filial_id, codigo_produto, data_posicao, quantidade,
           coalesce(nullif(custo_logus, 0), custo_positivo) as custo_logus
    from {{ ref('int_estoque_final_mes') }}
),

-- Custo da filial 1 (Armazém) no início e no fim do mês, para o produto sem custo na própria filial
-- (o Bom Kafe quase não tem estoque no Logus; o Fabric também caía no custo da filial 1).
custo_filial_1 as (
    select
        m.mes,
        c.codigo_produto,
        max(c.custo_positivo) filter (where c.data <= m.mes - 1
            and (c.proxima_data is null or c.proxima_data > m.mes - 1)) as custo_inicio,
        max(c.custo_positivo) filter (where c.data <= least((m.mes + interval '1 month - 1 day')::date, current_date)
            and (c.proxima_data is null or c.proxima_data > least((m.mes + interval '1 month - 1 day')::date, current_date))) as custo_fim
    from meses m
    join {{ ref('int_estoque_custo') }} c
      on c.filial_id = 1
     and c.data <= least((m.mes + interval '1 month - 1 day')::date, current_date)
    group by 1, 2
),

chaves as (
    select mes, filial_id, codigo_produto from vendas
    union select mes, filial_id, codigo_produto from compras
    union select mes, filial_id, codigo_produto from transformacoes
    union select mes, filial_id, codigo_produto from quebras
    union select mes, filial_id, codigo_produto from inicial where quantidade <> 0
    union select mes, filial_id, codigo_produto from final where quantidade <> 0
),

base as (
    select
        k.mes,
        k.filial_id,
        k.codigo_produto,
        p.departamento,
        p.secao,
        p.departamento_logus,
        p.grupo,
        p.subgrupo,
        p.descricao,
        p.descricao_completa,
        p.unidade_medida,
        p.ativo,
        pr.impostos_entrada,
        pr.impostos_saida,
        pr.preco_venda,
        coalesce(i.quantidade, 0)                       as qtd_estoque_inicial,
        coalesce(case when p.departamento = 'ACOUGUE' then ca.custo_unitario end,
                 nullif(i.custo_logus, 0), c1.custo_inicio, 0) as custo_inicial,
        coalesce(i.data_estoque, k.mes)                 as data_estoque_inicial,
        i.origem                                        as origem_estoque_inicial,
        coalesce(f.quantidade, 0)                       as qtd_estoque_final,
        coalesce(case when p.departamento = 'ACOUGUE' then ca.custo_unitario end,
                 nullif(f.custo_logus, 0), c1.custo_fim, 0) as custo_final,
        f.data_posicao                                  as data_estoque_final,
        coalesce(c.qtd_comprada, 0)                     as qtd_comprada,
        coalesce(c.vlr_comprado, 0)                     as vlr_comprado,
        coalesce(c.vlr_impostos_compras, 0)             as vlr_impostos_compras,
        coalesce(v.qtd_vendida_bk, 0)                   as qtd_vendida_bk,
        coalesce(v.vlr_venda_bruto_bk, 0)               as vlr_venda_bruto_bk,
        coalesce(v.vlr_vendido_bk, 0)                   as vlr_vendido_bk,
        coalesce(v.qtd_vendida, 0)                      as qtd_vendida,
        coalesce(v.vlr_venda_bruto, 0)                  as vlr_venda_bruto,
        coalesce(v.vlr_vendido, 0)                      as vlr_vendido,
        coalesce(v.vlr_desconto, 0)                     as vlr_desconto,
        coalesce(v.vlr_impostos_vendas, 0)              as vlr_impostos_vendas,
        coalesce(t.qtd_requisicoes, 0)                  as qtd_requisicoes,
        coalesce(q.qtd_quebra, 0)                       as qtd_quebra,
        coalesce(q.vlr_quebra, 0)                       as vlr_quebra
    from chaves k
    left join produtos p        on p.codigo_produto = k.codigo_produto
    left join {{ ref('stg_logus__precos') }} pr on pr.filial_id = k.filial_id and pr.codigo_produto = k.codigo_produto
    left join custo_acougue ca  on ca.mes = k.mes and ca.codigo_produto = k.codigo_produto
    left join custo_filial_1 c1 on c1.mes = k.mes and c1.codigo_produto = k.codigo_produto
    left join inicial i         on i.mes = k.mes and i.filial_id = k.filial_id and i.codigo_produto = k.codigo_produto
    left join final f           on f.mes = k.mes and f.filial_id = k.filial_id and f.codigo_produto = k.codigo_produto
    left join compras c         on c.mes = k.mes and c.filial_id = k.filial_id and c.codigo_produto = k.codigo_produto
    left join vendas v          on v.mes = k.mes and v.filial_id = k.filial_id and v.codigo_produto = k.codigo_produto
    left join transformacoes t  on t.mes = k.mes and t.filial_id = k.filial_id and t.codigo_produto = k.codigo_produto
    left join quebras q         on q.mes = k.mes and q.filial_id = k.filial_id and q.codigo_produto = k.codigo_produto
),

-- Simples Nacional do Bom Kafe (filial 2): % = Simples da competência no F360 ÷ vendas da filial no
-- mês; sem lançamento no F360, 4% (como no Fabric).
simples as (
    select
        m.mes,
        coalesce(
            (select sum(r.valor) from {{ ref('stg_f360__rateio_titulos') }} r
              where r.empresa_cnpj = '57.903.451/0001-56' and upper(r.plano_de_contas) = 'SIMPLES NACIONAL'
                and r.competencia = to_char(m.mes, 'YYYY-MM'))
            / nullif((select sum(b.vlr_vendido) from base b where b.mes = m.mes and b.filial_id = 2), 0),
            0.04)                                       as taxa
    from meses m
)

select
    b.*,
    b.qtd_estoque_inicial + b.qtd_comprada              as qtd_estoque_compras,
    b.qtd_estoque_inicial * b.custo_inicial + b.vlr_comprado as vlr_estoque_compras,
    b.qtd_vendida_bk + b.qtd_vendida                    as qtd_total_vendas,
    b.vlr_vendido_bk + b.vlr_vendido                    as vlr_total_vendas,
    (b.qtd_vendida_bk + b.qtd_vendida) * b.custo_final  as vlr_cmv,
    case b.filial_id when 1 then b.vlr_impostos_vendas
                     when 2 then b.vlr_vendido * s.taxa else 0 end as vlr_impostos_venda,
    case b.filial_id when 1 then b.vlr_impostos_compras else 0 end as vlr_impostos_compra,
    b.qtd_quebra * b.custo_final                        as vlr_quebra_atualizado
from base b
join simples s on s.mes = b.mes

-- Rentabilidade por Setor por mês, filial e produto (porta do Gold_FatoItem do Fabric): estoque,
-- compras, vendas, CMV, impostos, quebras e as despesas do F360 alocadas ao item pelo peso do item
-- nas vendas do seu setor. Base em int_rentabilidade_item; despesas em vw_rentabilidade_despesas.
with despesas_depto as (
    select
        mes, filial_id, departamento,
        sum(valor_rateado) filter (where despesa = 'PESSOAS')        as pessoas,
        sum(valor_rateado) filter (where despesa = 'ADMINISTRATIVAS') as administrativas,
        sum(valor_rateado) filter (where despesa = 'EMBALAGEM')      as embalagem,
        sum(valor_rateado) filter (where despesa = 'FINANCEIRA')     as financeira,
        sum(valor_rateado) filter (where despesa = 'INTERVENIENCIA') as interveniencia,
        sum(valor_rateado) filter (where despesa = 'MANUTENCAO')     as manutencao,
        sum(valor_rateado) filter (where despesa = 'MARKETING')      as marketing,
        sum(valor_rateado) filter (where despesa = 'OCUPACAO')       as ocupacao
    from {{ ref('vw_rentabilidade_despesas') }}
    group by 1, 2, 3
),

itens as (
    select
        i.*,
        i.vlr_total_vendas - i.vlr_cmv                  as vlr_margem_bruta,
        i.vlr_impostos_venda - i.vlr_impostos_compra    as vlr_impostos_devidos,
        case when sum(i.vlr_total_vendas) over (partition by i.mes, i.filial_id, i.departamento) > 0
             then i.vlr_total_vendas / sum(i.vlr_total_vendas) over (partition by i.mes, i.filial_id, i.departamento)
             else 0 end                                 as peso_item_departamento
    from {{ ref('int_rentabilidade_item') }} i
),

com_despesas as (
    select
        t.*,
        t.vlr_margem_bruta - t.vlr_impostos_devidos     as vlr_margem_impostos,
        coalesce(d.pessoas, 0) * t.peso_item_departamento         as vlr_custo_pessoas,
        coalesce(d.administrativas, 0) * t.peso_item_departamento as vlr_custo_administrativas,
        coalesce(d.embalagem, 0) * t.peso_item_departamento       as vlr_custo_embalagem,
        coalesce(d.financeira, 0) * t.peso_item_departamento      as vlr_custo_financeira,
        coalesce(d.interveniencia, 0) * t.peso_item_departamento  as vlr_custo_interveniencia,
        coalesce(d.manutencao, 0) * t.peso_item_departamento      as vlr_custo_manutencao,
        coalesce(d.marketing, 0) * t.peso_item_departamento       as vlr_custo_marketing,
        coalesce(d.ocupacao, 0) * t.peso_item_departamento        as vlr_custo_ocupacao
    from itens t
    left join despesas_depto d
      on d.mes = t.mes and d.filial_id = t.filial_id and d.departamento is not distinct from t.departamento
),

final as (
    select
        c.*,
        c.vlr_margem_impostos - c.vlr_quebra_atualizado as vlr_margem_quebras,
        c.vlr_custo_pessoas + c.vlr_custo_administrativas + c.vlr_custo_embalagem + c.vlr_custo_financeira
            + c.vlr_custo_interveniencia + c.vlr_custo_manutencao + c.vlr_custo_marketing
            + c.vlr_custo_ocupacao                      as vlr_custo_total
    from com_despesas c
)

select
    concat_ws('-', to_char(f.mes, 'YYYY-MM'), f.filial_id, f.codigo_produto) as id,
    f.mes,
    extract(year from f.mes)::int                       as ano,
    extract(month from f.mes)::int                      as mes_numero,
    f.filial_id,
    fi.filial,
    f.codigo_produto,
    f.departamento, f.secao, f.departamento_logus, f.grupo, f.subgrupo, f.descricao, f.descricao_completa, f.unidade_medida, f.ativo,
    f.impostos_entrada, f.impostos_saida, f.preco_venda,
    f.qtd_estoque_inicial, f.custo_inicial, f.data_estoque_inicial, f.origem_estoque_inicial,
    f.qtd_estoque_final, f.custo_final, f.data_estoque_final,
    f.qtd_comprada, f.vlr_comprado, f.vlr_impostos_compras,
    f.qtd_vendida_bk, f.vlr_venda_bruto_bk, f.vlr_vendido_bk,
    f.qtd_vendida, f.vlr_venda_bruto, f.vlr_vendido, f.vlr_desconto, f.vlr_impostos_vendas,
    f.qtd_requisicoes, f.qtd_quebra, f.vlr_quebra,
    f.qtd_estoque_compras, f.vlr_estoque_compras, f.qtd_total_vendas, f.vlr_total_vendas,
    f.vlr_cmv, f.vlr_margem_bruta,
    case when f.vlr_total_vendas <> 0 then f.vlr_margem_bruta / f.vlr_total_vendas else 0 end as perc_margem_bruta,
    f.vlr_impostos_venda, f.vlr_impostos_compra, f.vlr_impostos_devidos, f.vlr_margem_impostos,
    case when f.vlr_total_vendas <> 0 then f.vlr_margem_impostos / f.vlr_total_vendas else 0 end as perc_margem_impostos,
    f.vlr_quebra_atualizado, f.vlr_margem_quebras,
    case when f.vlr_total_vendas <> 0 then f.vlr_margem_quebras / f.vlr_total_vendas else 0 end as perc_margem_quebras,
    f.vlr_custo_pessoas, f.vlr_custo_administrativas, f.vlr_custo_embalagem, f.vlr_custo_financeira,
    f.vlr_custo_interveniencia, f.vlr_custo_manutencao, f.vlr_custo_marketing, f.vlr_custo_ocupacao,
    f.vlr_custo_total,
    -- Margens em cascata, na ordem do Fabric (14/10/2026): cada uma desconta mais um grupo de despesas.
    f.vlr_margem_quebras - f.vlr_custo_ocupacao         as vlr_margem_ocupacao,
    f.vlr_margem_quebras - f.vlr_custo_ocupacao - f.vlr_custo_pessoas as vlr_margem_pessoas,
    f.vlr_margem_quebras - f.vlr_custo_ocupacao - f.vlr_custo_pessoas - f.vlr_custo_administrativas
                                                        as vlr_margem_administrativo,
    f.vlr_margem_quebras - f.vlr_custo_ocupacao - f.vlr_custo_pessoas - f.vlr_custo_administrativas
        - f.vlr_custo_embalagem                         as vlr_margem_embalagem,
    f.vlr_margem_quebras - f.vlr_custo_ocupacao - f.vlr_custo_pessoas - f.vlr_custo_administrativas
        - f.vlr_custo_embalagem - f.vlr_custo_manutencao as vlr_margem_manutencao,
    f.vlr_margem_quebras - f.vlr_custo_ocupacao - f.vlr_custo_pessoas - f.vlr_custo_administrativas
        - f.vlr_custo_embalagem - f.vlr_custo_manutencao - f.vlr_custo_marketing as vlr_margem_marketing,
    f.vlr_margem_quebras - f.vlr_custo_ocupacao - f.vlr_custo_pessoas - f.vlr_custo_administrativas
        - f.vlr_custo_embalagem - f.vlr_custo_manutencao - f.vlr_custo_marketing
        - f.vlr_custo_interveniencia                    as vlr_margem_interveniencia,
    f.vlr_margem_quebras - f.vlr_custo_total            as vlr_margem_final,  -- = depois da financeira
    now()                                               as atualizado_em
from final f
left join {{ ref('stg_logus__filiais') }} fi on fi.filial_id = f.filial_id

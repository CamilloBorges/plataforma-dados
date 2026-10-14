-- Despesas do F360 para a Rentabilidade por Setor, antes do rateio entre os setores. Reproduz o
-- busca_calcula_despesas do notebook "Fato Item" do Fabric:
--   * títulos: parcelas a pagar, pelo mês da EMISSÃO do título, sem as baixadas e renegociadas; a
--     linha de rateio do tipo Receita entra negativa; só planos com agrupador (join interno, como no
--     Fabric);
--   * cartões: as linhas de rateio do tipo Despesa (taxas das adquirentes), pelo mês da VENDA, sem as
--     baixadas; pessoa = "adquirente [bandeira]".
-- departamento preenchido = despesa direta do setor; nulo = indireta, rateada depois pela
-- participação nas vendas (no Fato Despesas). filial_id pelo CNPJ da empresa.
with titulos as (
    select
        'titulo'                                        as origem,
        t.parcela_id,
        t.empresa_cnpj,
        t.emissao                                       as data,
        t.centro_de_custo,
        t.plano_de_contas,
        t.pessoa,
        case when t.tipo_rateio = 'Receita' then -t.valor else t.valor end as valor
    from {{ ref('stg_f360__rateio_titulos') }} t
    where t.tipo_parcela = 'Despesa'
      and t.status not in ('Baixado', 'Renegociados')
),

cartoes as (
    select
        'cartao'                                        as origem,
        c.parcela_id,
        c.empresa_cnpj,
        c.data_venda                                    as data,
        c.centro_de_custo,
        c.plano_de_contas,
        c.adquirente || ' [' || c.bandeira || ']'       as pessoa,
        c.valor
    from {{ ref('stg_f360__rateio_cartoes') }} c
    where c.tipo_rateio = 'Despesa'
      and c.status <> 'Baixados'
),

despesas as (
    select t.*, p.agrupador1
    from titulos t
    join {{ source('config', 'f360_plano_contas') }} p on p.nome = t.plano_de_contas
    union all
    select c.*, p.agrupador1
    from cartoes c
    left join {{ source('config', 'f360_plano_contas') }} p on p.nome = c.plano_de_contas
)

select
    d.origem,
    d.parcela_id,
    f.filial_id,
    d.empresa_cnpj,
    d.data,
    extract(year from d.data)::int                      as ano,
    extract(month from d.data)::int                     as mes,
    d.agrupador1                                        as despesa,
    d.plano_de_contas,
    d.pessoa,
    d.centro_de_custo,
    cc.departamento,
    cc.departamento is not null                         as direta,
    coalesce(d.valor, 0)                                as valor
from despesas d
left join {{ ref('stg_logus__filiais') }} f on f.cnpj_formatado = d.empresa_cnpj
left join {{ source('config', 'f360_centro_custo') }} cc on cc.centro_de_custo = d.centro_de_custo

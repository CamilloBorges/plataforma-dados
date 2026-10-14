-- Despesas do F360 por mês, filial e setor, já rateadas (porta do Gold_FatoDespesas do Fabric).
-- Direta: centro de custo com departamento (config.f360_centro_custo). Indireta: rateada entre os
-- setores pela participação de cada um nas vendas da filial no mês (vlr_total_vendas).
with vendas_depto as (
    select mes, filial_id, departamento, sum(vlr_total_vendas) as vendas
    from {{ ref('int_rentabilidade_item') }}
    group by 1, 2, 3
),

pesos as (
    select
        mes, filial_id, departamento,
        case when sum(vendas) over (partition by mes, filial_id) > 0
             then round(vendas / sum(vendas) over (partition by mes, filial_id), 8) else 0 end as perc_departamento
    from vendas_depto
),

despesas as (
    select make_date(ano, mes, 1) as mes, filial_id, despesa, plano_de_contas, pessoa, departamento, direta, valor
    from {{ ref('int_despesas_f360') }}
    where make_date(ano, mes, 1) between date '{{ var("inicio_logus") }}' and date_trunc('month', current_date)
),

rateadas as (
    select d.mes, d.filial_id, d.despesa, d.plano_de_contas, d.pessoa, d.departamento, d.valor as valor_rateado
    from despesas d
    where d.direta
    union all
    select d.mes, d.filial_id, d.despesa, d.plano_de_contas, d.pessoa, p.departamento,
           round(d.valor * p.perc_departamento, 4)
    from despesas d
    join pesos p on p.mes = d.mes and p.filial_id = d.filial_id
    where not d.direta
)

select
    md5(concat_ws('|', mes, filial_id, despesa, plano_de_contas, departamento, pessoa)) as id,
    mes,
    extract(year from mes)::int                         as ano,
    extract(month from mes)::int                        as mes_numero,
    filial_id,
    despesa,
    plano_de_contas,
    departamento,
    pessoa,
    sum(valor_rateado)                                  as valor_rateado,
    now()                                               as atualizado_em
from rateadas
group by mes, filial_id, despesa, plano_de_contas, departamento, pessoa

-- Estoque inicial do mês por filial e produto (Rentabilidade por Setor). Regra do Camillo (13 e
-- 14/10/2026):
--   1. Se o produto foi inventariado até o dia 5 do mês, o estoque inicial é a quantidade contada,
--      como está (sem "voltar" ao dia 1). Com mais de um inventário nesse período, vale o primeiro.
--      Num inventário que zera os não contados, o produto do escopo que não foi contado entra com 0.
--   2. Senão, vale a posição do início do dia 1º, que é o estoque do fim do último dia com
--      movimento antes do mês (o estoque diário do Logus só tem linha nos dias com movimento).
-- Só inventários já aplicados ao estoque (processados). O Fabric não fazia assim: pegava a posição
-- mais próxima do dia 1, entre 60 dias antes e 5 dias depois.
-- custo_logus: custo comercial do Logus no último dia com movimento até a data do estoque; o
-- custo médio do açougue (Fabric) é aplicado depois, no Fato Item.
with meses as (
    select generate_series(
        date '{{ var("inicio_logus") }}',
        date_trunc('month', current_date)::date,
        interval '1 month'
    )::date as mes
),

-- Cada linha do estoque diário vale do seu dia até o dia anterior à próxima linha do produto.
estoque as (
    select
        e.filial_id,
        e.codigo_produto,
        e.data,
        lead(e.data) over (partition by e.filial_id, e.codigo_produto order by e.data) as proxima_data,
        e.quantidade_estoque,
        e.custo
    from {{ ref('stg_logus__estoque_diario') }} e
),

posicao_dia_1 as (
    select
        m.mes,
        e.filial_id,
        e.codigo_produto,
        e.data                                          as data_posicao,
        e.quantidade_estoque,
        e.custo
    from meses m
    join estoque e
      on e.data < m.mes
     and (e.proxima_data is null or e.proxima_data >= m.mes)
),

inventario_ate_dia_5 as (
    select distinct on (date_trunc('month', i.data_referencia), i.filial_id, i.codigo_produto)
        date_trunc('month', i.data_referencia)::date    as mes,
        i.filial_id,
        i.codigo_produto,
        i.inventario_id,
        i.data_referencia,
        coalesce(i.quantidade_contada, 0)               as quantidade_contada
    from {{ ref('stg_logus__inventarios_item') }} i
    where i.processado
      and extract(day from i.data_referencia) <= 5
      and (i.contado or i.zera_nao_contados)
      and i.data_referencia >= date '{{ var("inicio_logus") }}'
    order by date_trunc('month', i.data_referencia), i.filial_id, i.codigo_produto,
             i.data_referencia, i.inventario_id
),

inventario_com_custo as (
    select
        i.*,
        e.custo
    from inventario_ate_dia_5 i
    left join estoque e
      on e.filial_id = i.filial_id
     and e.codigo_produto = i.codigo_produto
     and e.data <= i.data_referencia
     and (e.proxima_data is null or e.proxima_data > i.data_referencia)
)

select
    coalesce(i.mes, p.mes)                              as mes,
    extract(year from coalesce(i.mes, p.mes))::int      as ano,
    extract(month from coalesce(i.mes, p.mes))::int     as mes_numero,
    coalesce(i.filial_id, p.filial_id)                  as filial_id,
    coalesce(i.codigo_produto, p.codigo_produto)        as codigo_produto,
    case when i.codigo_produto is not null then 'inventario' else 'posicao_dia_1' end as origem,
    case when i.codigo_produto is not null then i.data_referencia
         else coalesce(i.mes, p.mes) - 1 end            as data_estoque,
    coalesce(i.quantidade_contada, p.quantidade_estoque) as quantidade,
    case when i.codigo_produto is not null then i.custo else p.custo end as custo_logus,
    i.inventario_id,
    p.quantidade_estoque                                as quantidade_posicao_dia_1,
    p.data_posicao
from inventario_com_custo i
full join posicao_dia_1 p
  on p.mes = i.mes
 and p.filial_id = i.filial_id
 and p.codigo_produto = i.codigo_produto

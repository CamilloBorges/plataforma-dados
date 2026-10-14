-- Estoque diário do Logus com o intervalo de validade de cada linha e o último custo positivo.
-- O estoque diário só tem linha nos dias com movimento: a linha vale do seu dia até o dia anterior
-- à próxima linha do produto (proxima_data). custo_positivo: o custo da linha, ou o último custo
-- maior que zero até ela (o Fabric troca o custo zerado pelo último custo positivo).
with base as (
    select
        e.filial_id,
        e.codigo_produto,
        e.data,
        lead(e.data) over w                             as proxima_data,
        e.quantidade_estoque,
        e.custo,
        count(case when e.custo > 0 then 1 end) over (w rows unbounded preceding) as grupo_custo
    from {{ ref('stg_logus__estoque_diario') }} e
    window w as (partition by e.filial_id, e.codigo_produto order by e.data)
)

select
    filial_id,
    codigo_produto,
    data,
    proxima_data,
    quantidade_estoque,
    custo,
    max(case when custo > 0 then custo end)
        over (partition by filial_id, codigo_produto, grupo_custo) as custo_positivo
from base

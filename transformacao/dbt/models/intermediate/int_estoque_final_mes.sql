-- Estoque final do mês por filial e produto: a posição do fim do último dia do mês (no mês
-- corrente, a de hoje), com o custo do Logus nessa data. O Fabric pegava a posição mais próxima do
-- último dia, entre 60 dias antes e 5 dias depois (podia pegar uma posição do mês seguinte).
with meses as (
    select
        m::date                                         as mes,
        least((m + interval '1 month - 1 day')::date, current_date) as data_fim
    from generate_series(
        date '{{ var("inicio_logus") }}',
        date_trunc('month', current_date)::date,
        interval '1 month'
    ) m
)

select
    m.mes,
    e.filial_id,
    e.codigo_produto,
    e.data                                              as data_posicao,
    e.quantidade_estoque                                as quantidade,
    e.custo                                             as custo_logus,
    e.custo_positivo
from meses m
join {{ ref('int_estoque_custo') }} e
  on e.data <= m.data_fim
 and (e.proxima_data is null or e.proxima_data > m.data_fim)

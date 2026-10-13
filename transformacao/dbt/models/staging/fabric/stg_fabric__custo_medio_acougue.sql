-- Custo médio do açougue por produto e mês, calculado no Fabric (carcaças, desossa, compras,
-- transformações e retalhos). Entra no estoque e no CMV dos produtos do açougue no Fato Item.
-- codigo_produto: o mesmo cdg_produto do Logus (eanBalanca no Fabric).
-- data_ultimo_custo: início do mês de onde veio o custo (o Fabric repete o último custo conhecido
-- quando o produto não teve movimento no mês).
select
    ano::int                                            as ano,
    mes::int                                            as mes,
    eanbalanca                                          as codigo_produto,
    vlrunitario                                         as custo_unitario,
    ultimocusto                                         as data_ultimo_custo
from {{ source('fabric', 'custo_medio_acougue') }}

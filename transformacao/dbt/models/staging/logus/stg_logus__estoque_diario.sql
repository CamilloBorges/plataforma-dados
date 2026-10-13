-- Posição de estoque por dia, filial e produto, com o custo comercial do dia (função
-- estmovccusto_coml do Logus) e as quebras. Porta do dataflow "EstoqueDiario Logus" do Fabric
-- (só a parte do Logus; o histórico do PlenoKW entra num modelo próprio).
select
    a.dat_movimento::date                               as data,
    a.cdg_filial::int                                   as filial_id,
    a.cdg_produto::bigint                               as codigo_produto,
    a.qtd_estoque                                       as quantidade_estoque,
    a.val_custo_coml                                    as custo,
    a.qtd_perdas_quebras                                as quantidade_quebras,
    a.val_perdas_quebras                                as valor_quebras
from {{ source('logus', 'estdiapr') }} a

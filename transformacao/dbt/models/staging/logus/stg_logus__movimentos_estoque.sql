-- Movimentos de estoque do Logus (estmovpr), um por operação, com o saldo depois dela.
-- As vendas do dia entram somadas às 23:00 (operação 210). Os ajustes de inventário são as
-- operações 101 (entrada) e 201 (saída), com quantidade_inventario = quantidade contada.
-- O estoque inicial do mês não usa esta tabela (usa o estoque diário e os inventários); ela fica
-- para auditoria dos ajustes.
select
    e.cdg_filial::int                                   as filial_id,
    e.cdg_produto::bigint                               as codigo_produto,
    e.dat_operacao                                      as data_hora,
    e.cdg_operacao::int                                 as operacao_id,
    e.cdg_operacao in (101, 201)                        as ajuste_inventario,
    e.qtd_operacao                                      as quantidade,
    e.qtd_saldo                                         as quantidade_saldo,
    e.qtd_inventario                                    as quantidade_inventario,
    e.val_preco                                         as preco,
    e.val_custo_atm                                     as custo,
    e.dat_cancel                                        as data_cancelamento,
    e.nmr_docto                                         as documento
from {{ source('logus', 'estmovpr') }} e

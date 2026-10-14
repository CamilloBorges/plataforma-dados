-- Itens dos inventários do Logus (bdodinv), com o cabeçalho (bdominv). Uma linha por inventário
-- e produto.
-- Inventários parciais: o escopo vem de tipo_selecao/codigo_selecao (10 = departamento, 3 = seção,
-- 4 = grupo) e o bdodinv traz todos os produtos do escopo, contados ou não (quantidades nulas).
-- Conferido em 14/10/2026 contra os ajustes 101/201 do estmovpr:
--   * a quantidade aplicada ao estoque é loja + depósito (qtd_loja + qtd_deposito); não há
--     recontagem (qtd_loja2/3 sempre nulos);
--   * produto repetido no inventário (linha incluída à mão): vale a última linha (maior
--     nmr_sequencia), sem somar;
--   * com zera_nao_contados, o produto não contado vira 0; sem a marca, ele não é ajustado.
-- data_referencia: dat_atualizacao (data do inventário); data_processamento: quando foi aplicado
-- ao estoque (nula = ainda não aplicado).
with itens as (
    select distinct on (d.cdg_filial, d.nmr_inventario, d.cdg_produto)
        d.*
    from {{ source('logus', 'bdodinv') }} d
    order by d.cdg_filial, d.nmr_inventario, d.cdg_produto, d.nmr_sequencia desc
)

select
    m.cdg_filial::int                                   as filial_id,
    m.nmr_inventario::int                               as inventario_id,
    m.dat_atualizacao::date                             as data_referencia,
    m.dat_processamento                                 as data_processamento,
    m.dat_processamento is not null                     as processado,
    m.flg_selecao::int                                  as tipo_selecao,
    nullif(trim(m.cdg_selecao), '')                     as codigo_selecao,
    coalesce(m.flb_zera_produto_nao_informado, '0') = '1' as zera_nao_contados,
    d.cdg_produto::bigint                               as codigo_produto,
    d.qtd_loja                                          as quantidade_loja,
    d.qtd_deposito                                      as quantidade_deposito,
    case when d.qtd_loja is not null or d.qtd_deposito is not null
         then coalesce(d.qtd_loja, 0) + coalesce(d.qtd_deposito, 0) end as quantidade_contada,
    d.qtd_loja is not null or d.qtd_deposito is not null as contado,
    d.val_custo                                         as custo
from {{ source('logus', 'bdominv') }} m
join itens d
  on d.cdg_filial = m.cdg_filial
 and d.nmr_inventario = m.nmr_inventario

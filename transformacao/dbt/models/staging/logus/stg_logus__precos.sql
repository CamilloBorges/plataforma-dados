-- Preço, custo e estoque atuais por filial e produto. Porta do dataflow qPrecos do Fabric.
-- impostos_*: % de ICMS+FCP sobre a base do PIS/COFINS na entrada e na saída.
select
    a.cdg_filial::int                                   as filial_id,
    f.dcr_fantasia                                      as filial,
    a.cdg_produto::bigint                               as codigo_produto,
    p.dcr_reduzida                                      as descricao,
    a.qtd_estoque                                       as quantidade_estoque,
    a.val_custo                                         as custo,
    a.val_preco                                         as preco_venda,
    a.pct_icms_fcp_ent_base_piscof                      as impostos_entrada,
    a.pct_icms_fcp_sai_base_piscof                      as impostos_saida
from {{ source('logus', 'estprfil') }} a
join {{ source('logus', 'cadprod') }} p on p.cdg_produto = a.cdg_produto
join {{ source('logus', 'cadfil') }} f  on f.cdg_filial = a.cdg_filial

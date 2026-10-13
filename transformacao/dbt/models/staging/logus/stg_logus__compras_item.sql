-- Itens das notas de entrada (compras). Porta do dataflow qCompras do Fabric (12/10/2026).
-- valor_total = quantidade × qtd. por embalagem × preço da embalagem − descontos.
-- ICMS só quando o item não é de substituição tributária (cadicms.flb_sub_tributaria = 0).
-- situacao_nota: bdomnfe.flg_situacao_nf; o Fato Item considera só a situação 3.
select
    i.idbdodnfe                                         as id,
    n.cdg_filial::int                                   as filial_id,
    f.dcr_fantasia                                      as filial,
    p.nmr_pedido::int                                   as pedido,
    n.cdg_oper_es::int                                  as operacao_id,
    o.dcr_oper_es                                       as operacao,
    n.cdg_fornecedor                                    as cnpj_fornecedor,
    fo.dcr_fornecedor                                   as fornecedor,
    n.nmr_chave_acesso                                  as chave_acesso,
    n.nmr_docto::int                                    as numero_nota,
    n.dcr_serie                                         as serie_nota,
    n.dat_emissao                                       as data_emissao,
    n.dat_entrada                                       as data_entrada,
    i.nmr_sequencia::int                                as item,
    i.cdg_produto::bigint                               as codigo_produto,
    i.qtd_de_embal::numeric(18, 4)                      as quantidade,
    i.qtd_por_embal::numeric(18, 4)                     as quantidade_embalagem,
    i.val_preco_embal::numeric(18, 4)                   as valor_unitario,
    i.val_desc::numeric(18, 4)                          as desconto,
    i.val_desc_calc::numeric(18, 4)                     as desconto_calculado,
    (i.qtd_de_embal * i.qtd_por_embal * i.val_preco_embal::numeric)
        - (coalesce(i.val_desc, 0) + i.val_desc_calc)   as valor_total,
    case when t.flb_sub_tributaria::int = 0
         then i.val_icms::numeric(18, 4) else 0 end     as valor_icms,
    i.val_fcp::numeric(18, 4)                           as valor_fcp,
    i.val_pis_cred::numeric(18, 4)                      as valor_pis,
    i.val_cofins_cred::numeric(18, 4)                   as valor_cofins,
    i.flg_status                                        as status_item,
    n.flg_situacao_nf::int                              as situacao_nota,
    i.dat_alteracao                                     as data_alteracao
from {{ source('logus', 'bdodnfe') }} i
join {{ source('logus', 'bdomnfe') }} n
  on n.cdg_filial = i.cdg_filial
 and n.cdg_fornecedor = i.cdg_fornecedor
 and n.nmr_docto = i.nmr_docto
 and n.dcr_serie = i.dcr_serie
join {{ source('logus', 'cadfil') }} f   on f.cdg_filial = n.cdg_filial
join {{ source('logus', 'cadforn') }} fo on fo.cdg_fornecedor = n.cdg_fornecedor
join {{ source('logus', 'cadopes') }} o  on o.cdg_oper_es = n.cdg_oper_es
join {{ source('logus', 'cadicms') }} t  on t.cdg_icms = i.cdg_icms
left join {{ source('logus', 'estmped') }} p on p.nmr_pedido = n.nmr_pedido

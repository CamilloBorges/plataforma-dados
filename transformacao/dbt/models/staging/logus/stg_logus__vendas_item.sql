-- Itens de venda do PDV com a nota (NFC-e ou NF-e). Porta da cópia "Vendas" do pipeline
-- NotasFiscais do Fabric (qVendas, parte do Logus). Traz também os cancelados: quem usa filtra.
-- status_nota: flg_cancelada_sefaz da NFC-e, ou 1 quando não há NFC-e (regra do Fabric; o
-- Fato Item usa só status_nota = 1).
select
    i.idvnditempdv                                      as id,
    c.idvndpdv                                          as venda_id,
    c.cdg_filial::int                                   as filial_id,
    f.dcr_fantasia                                      as filial,
    c.nmr_nsu                                           as nsu,
    c.flb_cancelado::int = 1                            as venda_cancelada,
    c.dat_emissao                                       as data_emissao,
    i.dat_registro_item                                 as data_registro_item,
    coalesce(c.nmr_cpf_cliente_identificado,
             c.nmr_cnpj_cliente_identificado)           as cpf_cnpj_cliente,
    coalesce(nfce.nmr_nota, nfe.nmr_nota)               as numero_nota,
    coalesce(nfce.nmr_serie, nfe.nmr_serie)             as serie_nota,
    coalesce(nfce.nmr_chave_acesso, nfe.nmr_chave_acesso) as chave_nota,
    coalesce(nfce.flg_cancelada_sefaz, 1)::int          as status_nota,
    nfce.dcr_motivo_cancelamento                        as motivo_cancelamento,
    case when nfce.nmr_chave_acesso is not null then 'NFCe'
         when nfe.nmr_chave_acesso is not null then 'NFe'
         else 'N/A' end                                 as tipo_nota,
    i.nmr_sequencia::int                                as item,
    i.cdg_produto::bigint                               as codigo_produto,
    i.flb_cancelado::int = 1                            as item_cancelado,
    i.qtd_produto                                       as quantidade,
    i.val_unitario                                      as valor_unitario,
    i.val_desconto_item                                 as desconto_item,
    i.val_desconto_forma_recebimento                    as desconto_proporcional,
    i.val_acrescimo_item                                as acrescimo_item,
    i.val_acrescimo_forma_receb                         as acrescimo_proporcional,
    i.val_total                                         as valor_total,
    i.val_icms                                          as valor_icms,
    i.val_fcp                                           as valor_fcp,
    i.val_pis                                           as valor_pis,
    i.val_cofins                                        as valor_cofins
from {{ source('logus', 'vnditenspdv') }} i
join {{ source('logus', 'vndpdv') }} c on c.idvndpdv = i.idvndpdv
join {{ source('logus', 'cadfil') }} f on f.cdg_filial = c.cdg_filial
left join {{ source('logus', 'vndpdvnfce') }} nfce on nfce.idvndpdv = c.idvndpdv
left join {{ source('logus', 'vndpdvnfe') }} nfe   on nfe.idvndpdv = c.idvndpdv

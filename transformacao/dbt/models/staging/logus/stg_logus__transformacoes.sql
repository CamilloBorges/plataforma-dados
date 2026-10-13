-- Transformações de produtos. Porta da cópia "Transformacoes" do pipeline "Producoes e
-- Transformacoes" do Fabric. No Logus, cdg_produto é a ORIGEM e cdg_produto_insumo o DESTINO
-- (é como o Fabric nomeia: eanBalancaOrigem/eanBalancaDestino); o Fato Item soma o destino.
select
    m.cdg_filial::int                                   as filial_id,
    m.nmr_transformacao::int                            as transformacao_id,
    m.dat_processamento                                 as data_processamento,
    m.dat_transformacao                                 as data_transformacao,
    d.cdg_produto::bigint                               as codigo_produto_origem,
    d.qtd_produto                                       as quantidade_origem,
    d.cdg_produto_insumo::bigint                        as codigo_produto_destino,
    d.qtd_insumo                                        as quantidade_destino
from {{ source('logus', 'estmtransfprodint') }} m
join {{ source('logus', 'estdtransfprodint') }} d
  on d.cdg_filial = m.cdg_filial
 and d.nmr_transformacao = m.nmr_transformacao

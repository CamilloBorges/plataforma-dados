-- atualizar: após raw_logus_15min
-- Posição de estoque por filial e produto (ERP atual, Logus). id = filial * 10^9 + código do produto.
SELECT
  e.cdg_filial::bigint * 1000000000 + e.cdg_produto AS id,
  f.dcr_fantasia       AS filial,
  e.cdg_produto        AS codigo_produto,
  a.dcr_produto        AS produto,
  p.dcr_embalagem      AS embalagem,
  g.dcr_grupo          AS grupo,
  s.dcr_secao          AS secao,
  e.qtd_estoque        AS quantidade_estoque,
  e.val_custo_med      AS custo_medio,
  e.val_preco          AS preco_venda,
  e.flb_curva_abc      AS curva_abc,
  e.dat_ult_venda      AS data_ultima_venda,
  e.dat_ult_compra     AS data_ultima_compra
FROM raw_logus.estprfil e
LEFT JOIN raw_logus.cadfil f   ON f.cdg_filial = e.cdg_filial
LEFT JOIN raw_logus.cadprod p  ON p.cdg_produto = e.cdg_produto
LEFT JOIN raw_logus.cadassoc a ON a.cdg_interno = p.cdg_interno
LEFT JOIN raw_logus.cadgrupo g ON g.cdg_grupo = a.cdg_grupo
LEFT JOIN raw_logus.cadsecao s ON s.cdg_secao = g.cdg_secao

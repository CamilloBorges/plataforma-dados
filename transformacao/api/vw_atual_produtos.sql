-- atualizar: após raw_logus_diario_03_00
-- Cadastro de produtos do ERP atual (Logus): item vendido (cadprod) com descrição, grupo e seção.
SELECT
  p.cdg_produto            AS id,
  p.cdg_interno            AS codigo_interno,
  p.cdg_barra              AS codigo_barras,
  a.dcr_produto            AS produto,
  p.dcr_reduzida           AS descricao_reduzida,
  p.dcr_embalagem          AS embalagem,
  g.dcr_grupo              AS grupo,
  s.dcr_secao              AS secao,
  p.dat_cadastro::date     AS data_cadastro,
  p.dat_desativacao::date  AS data_desativacao
FROM raw_logus.cadprod p
LEFT JOIN raw_logus.cadassoc a ON a.cdg_interno = p.cdg_interno
LEFT JOIN raw_logus.cadgrupo g ON g.cdg_grupo = a.cdg_grupo
LEFT JOIN raw_logus.cadsecao s ON s.cdg_secao = g.cdg_secao

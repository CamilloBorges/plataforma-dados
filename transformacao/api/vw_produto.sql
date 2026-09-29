-- atualizar: após raw_logus_diario_03_00
-- Cadastro de produtos UNIFICADO: ERP atual (Logus) + legado (PlenoKW), com o Logus prevalecendo.
--   origem = 'Logus':   todo código vendido do Logus (cdg_produto: EAN ou código de balança sem
--                       dígito verificador), com o código do PlenoKW ao lado quando há de/para.
--   origem = 'PlenoKW': produto do legado SEM par válido no Logus (sem de/para, ou de/para para um
--                       código que não existe no cadastro do Logus). Dados do legado; ativo = falso.
-- id: o código do Logus; para produto só do PlenoKW, o código interno do PlenoKW NEGATIVO (nunca
-- colide com código do Logus). De/para em config.depara_produto (Directus, config.bomgado.net).
-- Hierarquia: departamento > seção > grupo > subgrupo. No PlenoKW: cfg05 > cfg04 > cfg03 > cfg02.
-- Um produto mestre do Logus (codigo_interno) pode ter vários códigos vendidos (KG, caixa 9 kg...).
-- Joins todos LEFT: produto sem subgrupo/unidade/centro de custo aparece com o campo vazio.
WITH depara AS (
  SELECT d.codigo_pleno, d.codigo_logus
  FROM config.depara_produto d
  JOIN raw_logus.cadprod p ON p.cdg_produto = d.codigo_logus  -- só pares que existem no Logus
),
carga_logus AS (
  SELECT max(fim) AS fim FROM raw_logus.carga WHERE tabela = 'cadprod' AND erro IS NULL
)
SELECT
  p.cdg_produto::bigint                        AS id,
  'Logus'                                      AS origem,
  p.cdg_produto::bigint                        AS codigo_produto,        -- o que o PDV registra
  dp.codigo_pleno::bigint                      AS codigo_pleno,          -- código interno no PlenoKW
  p.cdg_interno::integer                       AS codigo_interno,        -- produto mestre no Logus
  a.cdg_emb_padrao::bigint                     AS codigo_produto_padrao, -- embalagem padrão do produto mestre
  (p.cdg_produto = a.cdg_emb_padrao)           AS embalagem_padrao,
  p.dcr_reduzida                               AS descricao,
  a.dcr_produto                                AS descricao_completa,
  p.dcr_embalagem                              AS embalagem,
  p.qtd_por_emb                                AS quantidade_por_embalagem,
  un.sgl_unidade_medida                        AS unidade_medida,
  coalesce(cc.dcr_ccusto, d.dcr_depto)         AS centro_custo,          -- sem centro de custo próprio, vale o departamento
  cc.dcr_ccusto                                AS centro_custo_cadastrado,
  d.dcr_depto                                  AS departamento,
  s.dcr_secao                                  AS secao,
  g.dcr_grupo                                  AS grupo,
  sg.dcr_subgrupo                              AS subgrupo,
  coalesce(sg.pct_margem, 0)::numeric(18,4)    AS margem_subgrupo_pct,
  (a.flb_balanca = '1')                        AS vendido_na_balanca,
  (a.flb_tipo_peso = 'V')                      AS peso_variavel,
  coalesce(p.flb_supvirtual = '1', false)      AS disponivel_ecommerce,
  (p.dat_desativacao IS NULL AND p.dat_exclusao IS NULL) AS ativo,
  p.dat_cadastro::date                         AS data_cadastro,
  p.dat_desativacao::date                      AS data_desativacao,
  a.dat_ultima_alteracao                       AS data_ultima_alteracao_cadastro,
  cl.fim                                       AS atualizado_em          -- hora da última cópia do cadastro
FROM raw_logus.cadprod p
CROSS JOIN carga_logus cl
LEFT JOIN depara dp                      ON dp.codigo_logus = p.cdg_produto
LEFT JOIN raw_logus.cadassoc a           ON a.cdg_interno = p.cdg_interno
LEFT JOIN raw_logus.cadgrupo g           ON g.cdg_grupo = a.cdg_grupo
LEFT JOIN raw_logus.cadsecao s           ON s.cdg_secao = g.cdg_secao
LEFT JOIN raw_logus.caddepto d           ON d.cdg_depto = s.cdg_depto
LEFT JOIN raw_logus.cadsubgr sg          ON sg.cdg_subgrupo = a.cdg_subgrupo
LEFT JOIN raw_logus.cadccust cc          ON cc.cdg_ccusto = a.cdg_ccusto
LEFT JOIN raw_logus.cadunidadesmedida un ON un.idcadunidademedida = a.idcadunidademedida

UNION ALL

SELECT
  -m.mcd01_codint                              AS id,
  'PlenoKW'                                    AS origem,
  NULL::bigint                                 AS codigo_produto,
  m.mcd01_codint                               AS codigo_pleno,
  NULL::integer                                AS codigo_interno,
  NULL::bigint                                 AS codigo_produto_padrao,
  NULL::boolean                                AS embalagem_padrao,
  trim(m.mcd01_descricao_curta)                AS descricao,
  trim(m.mcd01_descricao)                      AS descricao_completa,
  NULL                                         AS embalagem,
  NULL::numeric                                AS quantidade_por_embalagem,
  trim(u.adm01_unidade)                        AS unidade_medida,
  coalesce(trim(cc.ctb02_descricao), trim(c5.cfg05_descricao)) AS centro_custo,
  trim(cc.ctb02_descricao)                     AS centro_custo_cadastrado,
  trim(c5.cfg05_descricao)                     AS departamento,
  trim(c4.cfg04_descricao)                     AS secao,
  trim(c3.cfg03_descricao)                     AS grupo,
  trim(c2.cfg02_descricao)                     AS subgrupo,
  coalesce(c2.cfg02_perc_margem_sugerida, 0)::numeric(18,4) AS margem_subgrupo_pct,
  m.mcd01_flgbalanca                           AS vendido_na_balanca,
  NULL::boolean                                AS peso_variavel,         -- o PlenoKW não tem o equivalente
  coalesce(m.mcd01_flgenvia_ecommerce = 1, false) AS disponivel_ecommerce,
  false                                        AS ativo,                 -- não existe no ERP atual
  nullif(m.mcd01_data_inclusao, '1900-01-01') AS data_cadastro,         -- 1900-01-01 = sem data no PlenoKW
  NULL::date                                   AS data_desativacao,
  m.mcd01_dthr_ultima_alteracao::timestamp     AS data_ultima_alteracao_cadastro,
  NULL::timestamptz                            AS atualizado_em          -- legado estático (cópia única de 28/09/2026)
FROM legado.mcd01_mercadoria m
LEFT JOIN legado.adm01_unidade_mercadoria u ON u.adm01_id = m.adm01_unidade_mercadoria_id
LEFT JOIN legado.ctb02_centro_custo cc      ON cc.ctb02_id = m.ctb02_centro_custo_id
LEFT JOIN legado.cfg02_clasmerc_nivel1 c2   ON c2.cfg02_id = m.cfg02_clasmerc_nivel1_id
LEFT JOIN legado.cfg03_clasmerc_nivel2 c3   ON c3.cfg03_id = c2.cfg03_clasmerc_nivel2_id
LEFT JOIN legado.cfg04_clasmerc_nivel3 c4   ON c4.cfg04_id = c3.cfg04_clasmerc_nivel3_id
LEFT JOIN legado.cfg05_clasmerc_nivel4 c5   ON c5.cfg05_id = c4.cfg05_clasmerc_nivel4_id
WHERE NOT EXISTS (SELECT 1 FROM depara dp WHERE dp.codigo_pleno = m.mcd01_codint)

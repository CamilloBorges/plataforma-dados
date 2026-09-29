-- atualizar: após raw_logus_diario_03_00
-- Cadastro de produtos do ERP atual (Logus), um registro por CÓDIGO VENDIDO (cdg_produto: EAN ou
-- código de balança sem dígito verificador). Um produto mestre (codigo_interno) pode ter vários
-- códigos: embalagens (KG, caixa 9 kg, caixa 18 kg) ou EANs alternativos.
-- Hierarquia: departamento > seção > grupo > (subgrupo) > produto mestre > código vendido.
-- Joins todos LEFT: produto sem subgrupo/unidade/centro de custo aparece com o campo vazio.
-- Baseada na consulta de extração usada no Fabric (Camillo, 29/09/2026), revisada.
SELECT
  p.cdg_produto::bigint                        AS id,
  p.cdg_produto::bigint                        AS codigo_produto,        -- o que o PDV registra
  p.cdg_interno::integer                       AS codigo_interno,        -- produto mestre (chave do de/para do PlenoKW é outra: config.depara_produto)
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
  (SELECT max(fim) FROM raw_logus.carga
    WHERE tabela = 'cadprod' AND erro IS NULL) AS atualizado_em          -- hora da última cópia do cadastro
FROM raw_logus.cadprod p
LEFT JOIN raw_logus.cadassoc a           ON a.cdg_interno = p.cdg_interno
LEFT JOIN raw_logus.cadgrupo g           ON g.cdg_grupo = a.cdg_grupo
LEFT JOIN raw_logus.cadsecao s           ON s.cdg_secao = g.cdg_secao
LEFT JOIN raw_logus.caddepto d           ON d.cdg_depto = s.cdg_depto
LEFT JOIN raw_logus.cadsubgr sg          ON sg.cdg_subgrupo = a.cdg_subgrupo
LEFT JOIN raw_logus.cadccust cc          ON cc.cdg_ccusto = a.cdg_ccusto
LEFT JOIN raw_logus.cadunidadesmedida un ON un.idcadunidademedida = a.idcadunidademedida

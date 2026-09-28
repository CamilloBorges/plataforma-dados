-- atualizar: uma vez
-- Vendas por item de cupom do PlenoKW (ERP antigo, 23/08/2021–26/07/2026), sem estornos.
-- Legado estático (cópia única em legado.*): basta materializar uma vez por deploy.
-- "id" vira a chave primária (tem que ser única). CPF/CNPJ do cliente fica de fora (dado pessoal).
-- Conferência no MySQL (25/09/2026): 1.305.178 itens; soma R$ 34.739.035,13 × cupons não
-- estornados R$ 34.741.486,26 (0,007%). No Postgres os flags de estorno viraram boolean (pgloader).
SELECT
  i.fcx02_id                 AS id,
  c.fcx01_data               AS data,
  i.fcx02_hora               AS hora,
  f.cfg06_nome               AS filial,
  c.fcx01_pdv                AS pdv,
  c.fcx01_numero             AS cupom,
  i.fcx02_item               AS item,
  m.mcd01_codint             AS codigo_mercadoria,
  m.mcd01_descricao          AS mercadoria,
  u.adm01_unidade            AS unidade,
  cl.cfg02_codigo            AS classificacao_codigo,
  cl.cfg02_descricao         AS classificacao,
  i.fcx02_qtd                AS quantidade,
  i.fcx02_vlrunit            AS valor_unitario,
  i.fcx02_vlrdesconto_total  AS desconto,
  i.fcx02_vlracrescimo_total AS acrescimo,
  i.fcx02_vlrtot             AS valor_total,
  c.fcx01_id                 AS cupom_id,
  m.mcd01_id                 AS mercadoria_id
FROM legado.fcx02_cupom_item i
JOIN legado.fcx01_cupom c                   ON c.fcx01_id = i.fcx01_cupom_id
JOIN legado.cfg06_filial f                  ON f.cfg06_id = c.cfg06_filial_id
JOIN legado.mcd01_mercadoria m              ON m.mcd01_id = i.mcd01_mercadoria_id
LEFT JOIN legado.adm01_unidade_mercadoria u ON u.adm01_id = m.adm01_unidade_mercadoria_id
LEFT JOIN legado.cfg02_clasmerc_nivel1 cl   ON cl.cfg02_id = i.cfg02_clasmerc_id
WHERE c.fcx01_flgestornado = false
  AND i.fcx02_flgestornado = false

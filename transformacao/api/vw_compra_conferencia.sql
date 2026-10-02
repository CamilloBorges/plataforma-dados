-- atualizar: após raw_f360
-- Conferência das compras: notas de entrada do Logus (raw_logus.bdomnfe) × títulos a pagar do F360
-- (raw_f360.parcela_titulo), casando por CNPJ do fornecedor + número da nota. Uma linha por nota.
-- As notas do Logus casam com qualquer título do F360; "só no F360" lista só os títulos com rateio em
-- "Compra de Mercadorias" (o que deveria ter nota de entrada no Logus). Bonificações ficam de fora. Notas e títulos dos últimos 3 dias ficam como "recente" (prazo de lançamento).
-- Exemplo que motivou a view (02/10/2026): AgroBrasil NF 38336, R$ 59.418,60, só no F360.
WITH empresas AS (
  -- Só as empresas que lançam notas de entrada no Logus (o Bom Kafe, por ora, não lança).
  SELECT DISTINCT regexp_replace(f.nmr_cgc::text, '\D', '', 'g') AS cnpj
  FROM raw_logus.bdomnfe m JOIN raw_logus.cadfil f ON f.cdg_filial = m.cdg_filial
  WHERE m.dat_entrada >= current_date - 30
),
logus AS (
  SELECT regexp_replace(m.cdg_fornecedor, '\D', '', 'g')          AS cnpj,
         ltrim(m.nmr_docto::text, '0')                             AS nf,
         min(m.dat_emissao)::date                                  AS emissao,
         min(m.dat_entrada)::date                                  AS entrada,
         sum(m.val_docto)                                          AS valor,
         count(*)                                                  AS notas
  FROM raw_logus.bdomnfe m
  WHERE m.dat_cancel IS NULL AND m.dat_entrada >= current_date - 120
    AND coalesce(m.flb_bonific::text, '0') <> '1'
  GROUP BY 1, 2
),
titulo AS (
  SELECT p.dados->'DadosDoTitulo'->>'TituloId'                                        AS titulo_id,
         regexp_replace(max(p.cliente_fornecedor_doc), '\D', '', 'g')                 AS cnpj,
         ltrim(regexp_replace(max(coalesce(p.dados->'DadosDoTitulo'->>'NumeroDoTitulo', p.numero)), '\D', '', 'g'), '0') AS nf,
         max(p.cliente_fornecedor)                                                    AS fornecedor,
         max(p.empresa)                                                               AS empresa,
         regexp_replace(max(p.empresa_cnpj), '\D', '', 'g')                          AS empresa_cnpj,
         max((p.dados->'DadosDoTitulo'->>'Emissao'))::date                            AS emissao,
         max((p.dados->'DadosDoTitulo'->>'Valor')::numeric)                           AS valor,
         count(*)                                                                     AS parcelas,
         bool_and(p.liquidacao IS NOT NULL)                                           AS pago,
         min(p.vencimento) FILTER (WHERE p.liquidacao IS NULL)                        AS proximo_vencimento,
         bool_or(EXISTS (SELECT 1 FROM jsonb_array_elements(p.dados->'Rateio') r
                         WHERE r->>'PlanoDeContas' ILIKE '%Compra de Mercadorias%'))  AS mercadoria
  FROM raw_f360.parcela_titulo p
  WHERE p.tipo = 'Despesa' AND NOT coalesce(p.cancelada, false)
  GROUP BY 1
),
f360 AS (
  SELECT cnpj, nf, max(fornecedor) AS fornecedor, max(empresa) AS empresa, min(emissao) AS emissao,
         sum(valor) AS valor, count(*) AS titulos, bool_and(pago) AS pago, min(proximo_vencimento) AS proximo_vencimento,
         bool_or(mercadoria) AS mercadoria
  FROM titulo
  WHERE nf <> '' AND empresa_cnpj IN (SELECT cnpj FROM empresas)
  GROUP BY 1, 2
),
nomes AS (
  SELECT DISTINCT ON (regexp_replace(cliente_fornecedor_doc, '\D', '', 'g'))
         regexp_replace(cliente_fornecedor_doc, '\D', '', 'g') AS cnpj, cliente_fornecedor AS nome
  FROM raw_f360.parcela_titulo
  WHERE tipo = 'Despesa' AND cliente_fornecedor_doc IS NOT NULL
  ORDER BY 1, visto_em DESC
)
SELECT
  coalesce(l.cnpj, f.cnpj) || '-' || coalesce(l.nf, f.nf)  AS id,
  coalesce(f.fornecedor, n.nome)                            AS fornecedor,
  coalesce(l.cnpj, f.cnpj)                                  AS cnpj_fornecedor,
  coalesce(l.nf, f.nf)                                      AS nota,
  coalesce(l.emissao, f.emissao)                            AS emissao,
  l.entrada                                                 AS entrada_logus,
  l.valor                                                   AS valor_logus,
  f.valor                                                   AS valor_f360,
  f.empresa                                                 AS empresa_f360,
  f.titulos                                                 AS titulos_f360,
  f.pago                                                    AS pago_no_f360,
  f.proximo_vencimento                                      AS proximo_vencimento_f360,
  CASE
    WHEN l.cnpj IS NULL AND f.emissao > current_date - 3      THEN 'recente (aguardando o Logus)'
    WHEN l.cnpj IS NULL                                        THEN 'só no F360 (sem nota de entrada no Logus)'
    WHEN f.cnpj IS NULL AND l.entrada > current_date - 3       THEN 'recente (aguardando o F360)'
    WHEN f.cnpj IS NULL                                        THEN 'só no Logus (sem título no F360)'
    WHEN f.titulos > 1 AND abs(l.valor * f.titulos - f.valor) <= 1.00
                                                               THEN 'título em duplicidade no F360'
    WHEN abs(l.valor - f.valor) > 1.00                         THEN 'valor diferente'
    ELSE 'ok'
  END                                                       AS pendencia
FROM logus l
FULL JOIN f360 f ON f.cnpj = l.cnpj AND f.nf = l.nf
LEFT JOIN nomes n ON n.cnpj = coalesce(l.cnpj, f.cnpj)
WHERE l.cnpj IS NOT NULL OR (f.mercadoria AND f.emissao >= current_date - 120)

-- atualizar: após raw_logus_15min
-- Vendas por item de cupom do ERP atual (Logus), sem cupons/itens cancelados (flb_cancelado = 1).
-- Operação real a partir de 17/06/2026 (Bom Kafe 25/06); antes só há cupons de teste cancelados.
-- Sobrepõe o PlenoKW (api.vw_vendas_item) de 17/06 a 26/07/2026: não somar as duas sem cortar.
-- valor_total é BRUTO; o valor vendido é valor_liquido = valor_total - desconto + acrescimo
-- (conferido no MySQL em 25/09/2026: soma de valor_liquido = soma de vndpdv.val_venda).
-- "id" vira a chave primária (única). Sem CPF/CNPJ.
-- flb_cancelado::int: funciona se a coluna vier como smallint, char('0'/'1') ou boolean.
SELECT
  i.idvnditempdv                                      AS id,
  c.dat_emissao::date                                 AS data,
  c.dat_emissao::time                                 AS hora,
  f.dcr_fantasia                                      AS filial,
  c.nmr_ecf                                           AS pdv,
  c.idvndpdv                                          AS cupom_id,
  i.nmr_sequencia                                     AS item,
  i.cdg_produto                                       AS codigo_produto,
  a.dcr_produto                                       AS produto,
  p.dcr_embalagem                                     AS embalagem,
  g.dcr_grupo                                         AS grupo,
  s.dcr_secao                                         AS secao,
  i.qtd_produto                                       AS quantidade,
  i.val_unitario                                      AS valor_unitario,
  i.val_desconto_item + i.val_desconto_forma_recebimento AS desconto,
  i.val_acrescimo_item + i.val_acrescimo_forma_receb  AS acrescimo,
  i.val_total                                         AS valor_total,
  i.val_total - (i.val_desconto_item + i.val_desconto_forma_recebimento)
              + (i.val_acrescimo_item + i.val_acrescimo_forma_receb) AS valor_liquido
FROM raw_logus.vnditenspdv i
JOIN raw_logus.vndpdv c        ON c.idvndpdv = i.idvndpdv
LEFT JOIN raw_logus.cadfil f   ON f.cdg_filial = c.cdg_filial
LEFT JOIN raw_logus.cadprod p  ON p.cdg_produto = i.cdg_produto
LEFT JOIN raw_logus.cadassoc a ON a.cdg_interno = p.cdg_interno
LEFT JOIN raw_logus.cadgrupo g ON g.cdg_grupo = a.cdg_grupo
LEFT JOIN raw_logus.cadsecao s ON s.cdg_secao = g.cdg_secao
WHERE c.flb_cancelado::int = 0
  AND i.flb_cancelado::int = 0

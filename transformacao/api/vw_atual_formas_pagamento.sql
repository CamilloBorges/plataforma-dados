-- atualizar: após raw_logus_15min
-- Formas de recebimento por cupom do ERP atual (Logus), sem cupons cancelados.
-- Sem dados de cliente, cartão ou cheque. Conferência: soma(valor - troco) = vendas do período.
SELECT
  r.idvndformarecebimentopdv AS id,
  c.dat_emissao::date        AS data,
  f.dcr_fantasia             AS filial,
  c.nmr_ecf                  AS pdv,
  c.idvndpdv                 AS cupom_id,
  r.cdg_frec                 AS codigo_forma,
  fr.dcr_frec                AS forma,
  r.val_forma_recebimento    AS valor,
  r.val_troco                AS troco,
  r.nmr_parcelas             AS parcelas
FROM raw_logus.vndformasrecebimentopdv r
JOIN raw_logus.vndpdv c         ON c.idvndpdv = r.idvndpdv
LEFT JOIN raw_logus.cadfil f    ON f.cdg_filial = c.cdg_filial
LEFT JOIN raw_logus.cadfrec fr  ON fr.cdg_frec = r.cdg_frec
WHERE c.flb_cancelado::int = 0

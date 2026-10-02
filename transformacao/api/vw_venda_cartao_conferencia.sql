-- atualizar: após raw_f360
-- Conferência das vendas em cartão (e vale/voucher) por dia e loja: formas de recebimento do PDV do
-- Logus × parcelas de cartão que as adquirentes mandaram ao F360 (raw_f360.parcela_cartao, pela data
-- da venda). PIX pela SiTef fica em colunas à parte. Dinheiro, PIX no CNPJ, boleto, convênio e iFood
-- não entram (não passam por adquirente). As adquirentes mandam o arquivo em D+1: os dois últimos
-- dias ficam como "aguardando adquirente".
WITH logus AS (
  SELECT c.dat_emissao::date                                  AS data,
         regexp_replace(f.nmr_cgc::text, '\D', '', 'g')       AS cnpj,
         max(f.dcr_fantasia)                                  AS loja,
         sum(r.val_forma_recebimento - coalesce(r.val_troco, 0))
           FILTER (WHERE r.cdg_frec IN (4, 5, 6, 900, 901, 903, 905, 906, 907, 908, 909, 910, 911, 912, 913, 914, 915,
                                        918, 920, 921, 922, 923, 925, 926, 928, 929, 930, 931, 932)) AS cartao,
         sum(r.val_forma_recebimento - coalesce(r.val_troco, 0)) FILTER (WHERE r.cdg_frec = 904) AS pix_sitef
  FROM raw_logus.vndformasrecebimentopdv r
  JOIN raw_logus.vndpdv c      ON c.idvndpdv = r.idvndpdv
  LEFT JOIN raw_logus.cadfil f ON f.cdg_filial = c.cdg_filial
  WHERE c.flb_cancelado::int = 0 AND c.dat_emissao >= current_date - 45
  GROUP BY 1, 2
),
f360 AS (
  SELECT data_venda                                                    AS data,
         regexp_replace(empresa_cnpj, '\D', '', 'g')                   AS cnpj,
         sum(valor_bruto) FILTER (WHERE modalidade NOT ILIKE '%pix%')  AS cartao,
         sum(valor_bruto) FILTER (WHERE modalidade ILIKE '%pix%')      AS pix,
         sum(taxa)                                                     AS taxas,
         count(DISTINCT cartao_id)                                     AS vendas,
         count(*) FILTER (WHERE NOT coalesce(conciliado_pdv, false))   AS pendentes_conciliacao_pdv
  FROM raw_f360.parcela_cartao
  WHERE NOT coalesce(cancelada, false)
  GROUP BY 1, 2
)
SELECT
  coalesce(l.data, f.data)::text || '-' || coalesce(l.cnpj, f.cnpj)  AS id,
  coalesce(l.data, f.data)                                            AS data,
  coalesce(l.loja, coalesce(l.cnpj, f.cnpj))                          AS loja,
  coalesce(l.cartao, 0)                                               AS cartao_logus,
  coalesce(f.cartao, 0)                                               AS cartao_f360,
  coalesce(f.cartao, 0) - coalesce(l.cartao, 0)                       AS diferenca_cartao,
  coalesce(l.pix_sitef, 0)                                            AS pix_sitef_logus,
  coalesce(f.pix, 0)                                                  AS pix_f360,
  f.taxas                                                             AS taxas_f360,
  f.vendas                                                            AS vendas_f360,
  f.pendentes_conciliacao_pdv                                         AS parcelas_pendentes_conciliacao_pdv,
  CASE
    WHEN coalesce(l.data, f.data) >= current_date - 1                 THEN 'aguardando adquirente'
    WHEN f.data IS NULL AND coalesce(l.cartao, 0) > 0                 THEN 'sem arquivo da adquirente no F360'
    WHEN abs(coalesce(f.cartao, 0) - coalesce(l.cartao, 0)) <= 1.00   THEN 'ok'
    WHEN coalesce(f.cartao, 0) < coalesce(l.cartao, 0)                THEN 'F360 menor que o Logus'
    ELSE 'F360 maior que o Logus'
  END                                                                 AS situacao
FROM logus l
FULL JOIN f360 f ON f.data = l.data AND f.cnpj = l.cnpj
WHERE coalesce(l.data, f.data) >= current_date - 45

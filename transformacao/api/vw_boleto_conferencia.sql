-- atualizar: após raw_f360
-- Conferência dos boletos emitidos no Logus (raw_logus.recdocob) com o contas a receber do F360
-- (raw_f360.parcela_titulo, casando pelo número do boleto) e com os retornos do banco importados no
-- Logus (raw_logus.movdretornobanco). Uma linha por boleto; "pendencia" = 'ok' quando os dois batem.
-- Fase 1 (só leitura) da integração Logus → F360.
WITH f AS (
  SELECT DISTINCT ON (numero) numero, status, liquidacao, valor, cliente_fornecedor
  FROM raw_f360.parcela_titulo
  WHERE tipo = 'Receita'
  ORDER BY numero, cancelada, visto_em DESC
),
ret AS (
  SELECT trim(nmr_documento) AS documento, max(dat_ocorrencia)::date AS pago_em, sum(val_pago) AS valor_pago
  FROM raw_logus.movdretornobanco
  WHERE flb_pagamento::int = 1
  GROUP BY 1
)
SELECT
  trim(b.nmr_docto_cob)          AS id,
  b.nmr_nossonumero              AS nosso_numero,
  b.dat_emissao::date            AS emissao,
  b.dat_vecto::date              AS vencimento,
  b.val_docto                    AS valor,
  b.dat_cancel IS NOT NULL       AS cancelado_no_logus,
  f.cliente_fornecedor           AS cliente,
  f.status                       AS situacao_f360,
  f.liquidacao                   AS liquidado_no_f360_em,
  f.valor                        AS valor_f360,
  ret.pago_em                    AS pago_no_retorno_logus_em,
  CASE
    WHEN b.dat_cancel IS NOT NULL AND f.numero IS NOT NULL AND f.liquidacao IS NULL
                                                         THEN 'cancelado no Logus e aberto no F360'
    WHEN b.dat_cancel IS NOT NULL                        THEN 'ok'
    WHEN f.numero IS NULL AND b.dat_vecto::date >= current_date - 180
                                                         THEN 'sem título no F360'
    WHEN f.numero IS NULL                                THEN 'fora da janela lida do F360'
    WHEN abs(f.valor - b.val_docto) > 0.01               THEN 'valor diferente'
    WHEN ret.pago_em IS NOT NULL AND f.liquidacao IS NULL THEN 'pago no retorno e aberto no F360'
    WHEN f.liquidacao IS NULL AND b.dat_vecto::date < current_date
                                                         THEN 'vencido em aberto no F360'
    ELSE 'ok'
  END                            AS pendencia
FROM raw_logus.recdocob b
LEFT JOIN f   ON f.numero = trim(b.nmr_docto_cob)
LEFT JOIN ret ON ret.documento = trim(b.nmr_docto_cob)

-- NFC-e das vendas do PDV, sem o XML (dcr_xml_offline): só a identificação da nota e a situação
-- na SEFAZ, que a Rentabilidade por Setor usa para descartar notas canceladas.
SELECT idvndpdvnfce, idvndpdv, nmr_nota, nmr_serie, nmr_chave_acesso, flg_situacao_nota,
       flg_cancelada_sefaz, dcr_motivo_cancelamento, dat_protocolo_autorizacao
  FROM vndpdvnfce

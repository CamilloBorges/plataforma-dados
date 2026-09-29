-- Tabelas de configuração (de/para) editadas pelo Directus (config.bomgado.net).
-- Rodado a cada deploy pelo db-setup como o papel config_app (dono, para o Directus poder gravar).
-- Só "CREATE ... IF NOT EXISTS": mudança de estrutura em tabela existente vai num arquivo novo.

-- Produto do PlenoKW (ERP antigo, até 26/07/2026) -> produto do Logus (ERP atual).
-- Origem: planilha qProdutosDP.xlsx (Fabric, 20/07/2026). O "eanBalanca" da planilha é o próprio
-- cdg_produto do Logus (conferido em 29/09/2026: 9.205 de 9.346 batem; balança sem dígito verificador).
CREATE TABLE IF NOT EXISTS config.depara_produto (
    codigo_pleno  integer PRIMARY KEY,   -- legado.mcd01_mercadoria.mcd01_codint ("codInterno")
    codigo_logus  numeric NOT NULL,      -- raw_logus.cadprod.cdg_produto
    observacao    text,
    origem        text,
    alterado_em   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE config.depara_produto IS 'De/para de produto: código interno do PlenoKW -> cdg_produto do Logus';

-- alterado_em se atualiza sozinho em qualquer edição (pelo Directus ou por SQL).
CREATE OR REPLACE FUNCTION config.tocar_alterado_em() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.alterado_em := now();
    RETURN NEW;
END $$;
CREATE OR REPLACE TRIGGER depara_produto_alterado_em
    BEFORE UPDATE ON config.depara_produto
    FOR EACH ROW EXECUTE FUNCTION config.tocar_alterado_em();

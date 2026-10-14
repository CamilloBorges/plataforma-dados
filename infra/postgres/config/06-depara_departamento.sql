-- De/para de departamento do produto na Rentabilidade por Setor: leva os produtos de um
-- departamento do Logus para outro, opcionalmente só os de uma seção. Criado em 14/10/2026 para
-- descontinuar a CAFETERIA (notebook "Fato Item" do Fabric, versão de 14/10 18:18):
--   CAFETERIA, seção BEBIDAS -> BEBIDAS; seção DOCES -> CONFEITARIA; demais seções -> ROTISSERIA.
-- O produto levado fica com a seção = departamento de origem (ex.: seção "CAFETERIA"), como no
-- Fabric. Regra mais específica primeiro: a linha com seção vale antes da linha sem seção.
-- Rodado a cada deploy pelo db-setup como o papel config_app. Só "CREATE ... IF NOT EXISTS".
CREATE TABLE IF NOT EXISTS config.depara_departamento (
    id                    serial PRIMARY KEY,
    departamento_origem   text NOT NULL REFERENCES config.logus_departamento (departamento) ON UPDATE CASCADE,
    secao_origem          text,                -- nula = todas as seções do departamento
    departamento_destino  text NOT NULL REFERENCES config.logus_departamento (departamento) ON UPDATE CASCADE,
    observacao            text,
    alterado_em           timestamptz NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (departamento_origem, secao_origem)
);
COMMENT ON TABLE config.depara_departamento IS 'De/para de departamento do produto (Rentabilidade por Setor)';

CREATE OR REPLACE TRIGGER depara_departamento_alterado_em
    BEFORE UPDATE ON config.depara_departamento
    FOR EACH ROW EXECUTE FUNCTION config.tocar_alterado_em();

INSERT INTO config.depara_departamento (departamento_origem, secao_origem, departamento_destino, observacao) VALUES
    ('CAFETERIA', 'BEBIDAS', 'BEBIDAS',     'Cafeteria descontinuada (14/10/2026)'),
    ('CAFETERIA', 'DOCES',   'CONFEITARIA', 'Cafeteria descontinuada (14/10/2026)'),
    ('CAFETERIA', NULL,      'ROTISSERIA',  'Cafeteria descontinuada (14/10/2026): demais seções')
ON CONFLICT DO NOTHING;

-- Metadados do Directus: a coleção e as duas listas de departamento (reiniciar o Directus depois).
DO $$
BEGIN
    IF to_regclass('config.directus_relations') IS NULL THEN
        RETURN;
    END IF;
    INSERT INTO config.directus_collections (collection, icon, note)
    SELECT 'depara_departamento', 'swap_horiz', 'De/para de departamento do produto (Rentabilidade por Setor)'
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_collections WHERE collection = 'depara_departamento');

    INSERT INTO config.directus_relations (many_collection, many_field, one_collection)
    SELECT 'depara_departamento', f, 'logus_departamento'
    FROM unnest(ARRAY['departamento_origem', 'departamento_destino']) f
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_relations
                      WHERE many_collection = 'depara_departamento' AND many_field = f);

    INSERT INTO config.directus_fields (collection, field, special, interface, options, display, display_options, note)
    SELECT 'depara_departamento', f, 'm2o', 'select-dropdown-m2o', '{"template":"{{departamento}}"}',
           'related-values', '{"template":"{{departamento}}"}', n
    FROM (VALUES ('departamento_origem', 'Departamento do produto no Logus'),
                 ('departamento_destino', 'Departamento em que o produto entra na Rentabilidade')) v(f, n)
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_fields WHERE collection = 'depara_departamento' AND field = v.f);

    INSERT INTO config.directus_fields (collection, field, note)
    SELECT 'depara_departamento', 'secao_origem', 'Seção do produto no Logus; vazio = todas as seções'
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_fields WHERE collection = 'depara_departamento' AND field = 'secao_origem');
END $$;

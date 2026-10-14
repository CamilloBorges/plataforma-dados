-- De/para de departamento do produto na Rentabilidade por Setor: leva os produtos de um
-- departamento do Logus para outro, opcionalmente só os de uma seção. Criado em 14/10/2026 para
-- descontinuar a CAFETERIA (notebook "Fato Item" do Fabric, versão de 14/10 18:18):
--   CAFETERIA, seção BEBIDAS -> BEBIDAS; seção DOCES -> CONFEITARIA; demais seções -> ROTISSERIA.
-- O produto levado fica com a seção = departamento de origem (ex.: seção "CAFETERIA"), como no
-- Fabric. Regra mais específica primeiro: a linha com seção vale antes da linha sem seção.
-- A seção é o código da lista config.logus_secao (06-logus_secao.sql); a 1ª versão (14/10) guardava o
-- nome em secao_origem, migrado abaixo.
-- Rodado a cada deploy pelo db-setup como o papel config_app. Só "CREATE ... IF NOT EXISTS".
CREATE TABLE IF NOT EXISTS config.depara_departamento (
    id                    serial PRIMARY KEY,
    departamento_origem   text NOT NULL REFERENCES config.logus_departamento (departamento) ON UPDATE CASCADE,
    secao_origem_id       integer REFERENCES config.logus_secao (codigo),  -- nula = todas as seções
    departamento_destino  text NOT NULL REFERENCES config.logus_departamento (departamento) ON UPDATE CASCADE,
    observacao            text,
    alterado_em           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE config.depara_departamento IS 'De/para de departamento do produto (Rentabilidade por Setor)';

-- Migração da 1ª versão (seção pelo nome): o nome vira o código da seção do mesmo departamento.
ALTER TABLE config.depara_departamento
    ADD COLUMN IF NOT EXISTS secao_origem_id integer REFERENCES config.logus_secao (codigo);
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'config' AND table_name = 'depara_departamento' AND column_name = 'secao_origem') THEN
        UPDATE config.depara_departamento d
           SET secao_origem_id = s.codigo
          FROM config.logus_secao s
         WHERE d.secao_origem IS NOT NULL AND d.secao_origem_id IS NULL
           AND s.secao = d.secao_origem AND s.departamento = d.departamento_origem;
        -- CASCADE: a view do dbt que lia a coluna antiga cai e volta no próximo dbt build.
        ALTER TABLE config.depara_departamento DROP COLUMN secao_origem CASCADE;  -- leva junto o UNIQUE antigo
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'depara_departamento_origem_secao_key') THEN
        ALTER TABLE config.depara_departamento
            ADD CONSTRAINT depara_departamento_origem_secao_key
            UNIQUE NULLS NOT DISTINCT (departamento_origem, secao_origem_id);
    END IF;
END $$;

CREATE OR REPLACE TRIGGER depara_departamento_alterado_em
    BEFORE UPDATE ON config.depara_departamento
    FOR EACH ROW EXECUTE FUNCTION config.tocar_alterado_em();

-- Seções 17 = CAFETERIA › BEBIDAS e 19 = CAFETERIA › DOCES.
INSERT INTO config.depara_departamento (departamento_origem, secao_origem_id, departamento_destino, observacao) VALUES
    ('CAFETERIA', 17,   'BEBIDAS',     'Cafeteria descontinuada (14/10/2026)'),
    ('CAFETERIA', 19,   'CONFEITARIA', 'Cafeteria descontinuada (14/10/2026)'),
    ('CAFETERIA', NULL, 'ROTISSERIA',  'Cafeteria descontinuada (14/10/2026): demais seções')
ON CONFLICT DO NOTHING;

-- Metadados do Directus: a coleção e as listas de departamento e de seção (reiniciar o Directus depois).
DO $$
BEGIN
    IF to_regclass('config.directus_relations') IS NULL THEN
        RETURN;
    END IF;
    INSERT INTO config.directus_collections (collection, icon, note)
    SELECT 'depara_departamento', 'swap_horiz', 'De/para de departamento do produto (Rentabilidade por Setor)'
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_collections WHERE collection = 'depara_departamento');

    INSERT INTO config.directus_relations (many_collection, many_field, one_collection)
    SELECT 'depara_departamento', v.f, v.c
    FROM (VALUES ('departamento_origem', 'logus_departamento'), ('departamento_destino', 'logus_departamento'),
                 ('secao_origem_id', 'logus_secao')) v(f, c)
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_relations
                      WHERE many_collection = 'depara_departamento' AND many_field = v.f);

    DELETE FROM config.directus_fields WHERE collection = 'depara_departamento' AND field = 'secao_origem';
    INSERT INTO config.directus_fields (collection, field, special, interface, options, display, display_options, note)
    SELECT 'depara_departamento', v.f, 'm2o', 'select-dropdown-m2o', v.o::json, 'related-values', v.o::json, v.n
    FROM (VALUES
        ('departamento_origem', '{"template":"{{departamento}}"}', 'Departamento do produto no Logus'),
        ('departamento_destino', '{"template":"{{departamento}}"}', 'Departamento em que o produto entra na Rentabilidade'),
        ('secao_origem_id', '{"template":"{{departamento}} › {{secao}}"}',
         'Seção do produto no Logus (deve ser do departamento de origem); vazio = todas as seções')) v(f, o, n)
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_fields WHERE collection = 'depara_departamento' AND field = v.f);
END $$;

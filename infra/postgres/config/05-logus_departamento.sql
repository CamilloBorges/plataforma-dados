-- Departamentos do Logus (raw_logus.caddepto), para escolher o departamento do centro de custo do
-- F360 numa lista no Directus (config.f360_centro_custo.departamento tem chave estrangeira para cá;
-- o Directus reconhece a chave e mostra o campo como lista).
-- Rodado a cada deploy pelo db-setup como o papel config_app. Só "CREATE ... IF NOT EXISTS".
-- Sincronizado todo dia pelo dbt (on-run-end em transformacao/dbt/dbt_project.yml): departamento
-- novo no Logus entra aqui; renomeado entra com o nome novo e o antigo fica (pode ainda estar em uso).
-- A carga inicial abaixo é a do Logus em 14/10/2026, para a chave estrangeira valer já no deploy.
CREATE TABLE IF NOT EXISTS config.logus_departamento (
    departamento  text PRIMARY KEY,        -- caddepto.dcr_depto, o nome usado na Rentabilidade
    codigo        integer,                 -- caddepto.cdg_depto
    alterado_em   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE config.logus_departamento IS 'Departamentos do Logus (lista do centro de custo do F360); sincronizada pelo dbt';

-- O dbt (papel ingestao) inclui os departamentos novos.
GRANT SELECT, INSERT, UPDATE ON config.logus_departamento TO ingestao;

INSERT INTO config.logus_departamento (departamento, codigo) VALUES
    ('( DESATIVAR )', 1), ('ACOUGUE', 2), ('BEBIDAS', 3), ('CAFETERIA', 4), ('CHURRASCO', 5),
    ('CONFEITARIA', 6), ('FIAMBRERIA', 7), ('FRIOS E CIA', 8), ('HORTIFRUTI', 9), ('IMOBILIZADO', 10),
    ('LIMPEZA', 11), ('MERCEARIA', 12), ('PADARIA E CIA', 13), ('ROTISSERIA', 14), ('SERVICOS', 15),
    ('USO E CONSUMO', 16), ('TESTES', 17)
ON CONFLICT DO NOTHING;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'f360_centro_custo_departamento_fkey') THEN
        ALTER TABLE config.f360_centro_custo
            ADD CONSTRAINT f360_centro_custo_departamento_fkey
            FOREIGN KEY (departamento) REFERENCES config.logus_departamento (departamento)
            ON UPDATE CASCADE;
    END IF;
END $$;

-- Metadados do Directus (só quando as tabelas do Directus já existem): a coleção da lista, a
-- relação muitos-para-um e o campo departamento do centro de custo como lista suspensa.
-- O Directus guarda o esquema em cache: depois de mudar aqui, reiniciar o Directus.
DO $$
BEGIN
    IF to_regclass('config.directus_relations') IS NULL THEN
        RETURN;
    END IF;
    INSERT INTO config.directus_collections (collection, icon, note, display_template)
    SELECT 'logus_departamento', 'category', 'Departamentos do Logus (sincronizado pelo dbt)', '{{departamento}}'
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_collections WHERE collection = 'logus_departamento');

    INSERT INTO config.directus_relations (many_collection, many_field, one_collection)
    SELECT 'f360_centro_custo', 'departamento', 'logus_departamento'
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_relations
                      WHERE many_collection = 'f360_centro_custo' AND many_field = 'departamento');

    UPDATE config.directus_fields
       SET special = 'm2o', interface = 'select-dropdown-m2o',
           options = '{"template":"{{departamento}}"}', display = 'related-values',
           display_options = '{"template":"{{departamento}}"}',
           note = 'Departamento do Logus; vazio = despesa indireta (rateada entre os setores)'
     WHERE collection = 'f360_centro_custo' AND field = 'departamento';
    INSERT INTO config.directus_fields (collection, field, special, interface, options, display, display_options, note)
    SELECT 'f360_centro_custo', 'departamento', 'm2o', 'select-dropdown-m2o', '{"template":"{{departamento}}"}',
           'related-values', '{"template":"{{departamento}}"}',
           'Departamento do Logus; vazio = despesa indireta (rateada entre os setores)'
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_fields WHERE collection = 'f360_centro_custo' AND field = 'departamento');
END $$;

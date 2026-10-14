-- Seções do Logus (raw_logus.cadsecao), para escolher a seção do de/para de departamento numa lista
-- no Directus. O nome da seção se repete entre departamentos (ex.: DOCES na CAFETERIA, na
-- CONFEITARIA e na ROTISSERIA), então a chave é o código, e a lista mostra "DEPARTAMENTO › SEÇÃO".
-- Rodado a cada deploy pelo db-setup como o papel config_app. Só "CREATE ... IF NOT EXISTS".
-- Sincronizado todo dia pelo dbt (on-run-end em transformacao/dbt/dbt_project.yml). A carga inicial
-- abaixo é a do Logus em 14/10/2026 (95 seções).
CREATE TABLE IF NOT EXISTS config.logus_secao (
    codigo        integer PRIMARY KEY,     -- cadsecao.cdg_secao
    secao         text NOT NULL,           -- cadsecao.dcr_secao
    departamento  text NOT NULL REFERENCES config.logus_departamento (departamento) ON UPDATE CASCADE,
    alterado_em   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE config.logus_secao IS 'Seções do Logus (lista do de/para de departamento); sincronizada pelo dbt';
GRANT SELECT, INSERT, UPDATE ON config.logus_secao TO ingestao;

INSERT INTO config.logus_secao (codigo, secao, departamento) VALUES
    (1, '( DESATIVAR )', '( DESATIVAR )'),
    (2, 'AVES', 'ACOUGUE'),
    (3, 'BOVINO', 'ACOUGUE'),
    (4, 'EMBUTIDOS / SALGADOS', 'ACOUGUE'),
    (5, 'OSSO/SEBO', 'ACOUGUE'),
    (6, 'OVINO', 'ACOUGUE'),
    (7, 'SUINO', 'ACOUGUE'),
    (8, 'AGUA', 'BEBIDAS'),
    (9, 'CERVEJAS / CHOP', 'BEBIDAS'),
    (10, 'CHAS', 'BEBIDAS'),
    (11, 'DESTILADOS', 'BEBIDAS'),
    (12, 'DRINKS PRONTOS', 'BEBIDAS'),
    (13, 'ESPUMANTES', 'BEBIDAS'),
    (14, 'REFRIGERANTES', 'BEBIDAS'),
    (15, 'SUCOS', 'BEBIDAS'),
    (16, 'VINHOS', 'BEBIDAS'),
    (17, 'BEBIDAS', 'CAFETERIA'),
    (18, 'COPOS, XICARAS, TALH', 'CAFETERIA'),
    (19, 'DOCES', 'CAFETERIA'),
    (20, 'EMBALAGENS', 'CAFETERIA'),
    (21, 'EQUIPAMENTOS', 'CAFETERIA'),
    (22, 'INSUMO', 'CAFETERIA'),
    (23, 'MOLHOS TEMPEROS E CO', 'CAFETERIA'),
    (24, 'SALGADOS', 'CAFETERIA'),
    (25, 'ASSADO CORDEIRO', 'CHURRASCO'),
    (26, 'ASSADO FRANGO', 'CHURRASCO'),
    (27, 'ASSADO GADO BOVINO', 'CHURRASCO'),
    (28, 'ASSADO SALSICHAO', 'CHURRASCO'),
    (29, 'ASSADO SUINO', 'CHURRASCO'),
    (30, 'TRANSFORMACAO', 'CHURRASCO'),
    (31, 'BOLOS', 'CONFEITARIA'),
    (32, 'DOCES', 'CONFEITARIA'),
    (33, 'DOCES TERCEIRIZADOS', 'CONFEITARIA'),
    (34, 'SOBREMESAS', 'CONFEITARIA'),
    (35, 'TORTAS', 'CONFEITARIA'),
    (36, 'ANTEPASTOS', 'FIAMBRERIA'),
    (37, 'CARNES', 'FIAMBRERIA'),
    (38, 'FRIOS', 'FIAMBRERIA'),
    (39, 'OUTROS', 'FIAMBRERIA'),
    (40, 'QUEIJOS', 'FIAMBRERIA'),
    (41, 'SALAMES', 'FIAMBRERIA'),
    (42, 'SALGADOS', 'FIAMBRERIA'),
    (43, 'CONGELADOS', 'FRIOS E CIA'),
    (44, 'RESFRIADOS', 'FRIOS E CIA'),
    (45, 'SORVETES / SORBET', 'FRIOS E CIA'),
    (46, 'TRANSFORMACAO', 'FRIOS E CIA'),
    (47, 'COGUMELOS', 'HORTIFRUTI'),
    (48, 'ESPECIARIAS', 'HORTIFRUTI'),
    (49, 'FRUTAS', 'HORTIFRUTI'),
    (50, 'LEGUMES', 'HORTIFRUTI'),
    (51, 'OVOS', 'HORTIFRUTI'),
    (52, 'TEMPERO VERDE', 'HORTIFRUTI'),
    (53, 'VERDURAS', 'HORTIFRUTI'),
    (54, 'EQUIPAMENTOS', 'IMOBILIZADO'),
    (55, 'INFORMATICA', 'IMOBILIZADO'),
    (56, 'MOVEIS / ACABAMENTOS', 'IMOBILIZADO'),
    (57, 'VEICULOS', 'IMOBILIZADO'),
    (58, 'LIMPEZA', 'LIMPEZA'),
    (59, 'BASICO DA DESPENSA', 'MERCEARIA'),
    (60, 'BAZAR', 'MERCEARIA'),
    (61, 'BEBES E CRIANCAS', 'MERCEARIA'),
    (62, 'BISCOITOS, SALGADINH', 'MERCEARIA'),
    (63, 'CLUBE BOMGADO', 'MERCEARIA'),
    (64, 'CUIDADOS PESSOAIS', 'MERCEARIA'),
    (65, 'DOCES E SOBREMESAS', 'MERCEARIA'),
    (66, 'ENLATADOS E CONSERVA', 'MERCEARIA'),
    (67, 'LACTIOS / QUEIJOS /', 'MERCEARIA'),
    (68, 'LIMPEZA', 'MERCEARIA'),
    (69, 'MOLHOS TEMPEROS E CO', 'MERCEARIA'),
    (70, 'PADARIA E CONFEITARI', 'MERCEARIA'),
    (71, 'PETSHOP', 'MERCEARIA'),
    (72, 'SUPLEMENTOS ALIMENTA', 'MERCEARIA'),
    (73, 'TRANSORMACAO', 'MERCEARIA'),
    (74, 'CONFEITARIA', 'PADARIA E CIA'),
    (75, 'INSUMOS PROD. PROPRI', 'PADARIA E CIA'),
    (76, 'MASSAS CONGELADAS PA', 'PADARIA E CIA'),
    (77, 'PADARIA', 'PADARIA E CIA'),
    (78, 'DOCES', 'ROTISSERIA'),
    (79, 'HORTIFRUTI', 'ROTISSERIA'),
    (80, 'INSUMO', 'ROTISSERIA'),
    (81, 'SALGADOS', 'ROTISSERIA'),
    (82, 'DELIVERY', 'SERVICOS'),
    (83, 'CONTABILIDADE', 'USO E CONSUMO'),
    (84, 'EMBALAGENS E COMPLEM', 'USO E CONSUMO'),
    (85, 'EQUIPAMENTOS', 'USO E CONSUMO'),
    (86, 'ITENS OBSOLETOS', 'USO E CONSUMO'),
    (87, 'MANUTENCOES', 'USO E CONSUMO'),
    (88, 'MATERIAL DE EXPEDIEN', 'USO E CONSUMO'),
    (89, 'MATERIAL DE LIMPEZA', 'USO E CONSUMO'),
    (90, 'PESSOAS', 'USO E CONSUMO'),
    (91, 'PRODUCAO', 'USO E CONSUMO'),
    (92, 'TESTES1', 'TESTES'),
    (93, 'EVENTOS', 'SERVICOS'),
    (94, 'PRODUÇÃO PROPRIA', 'CONFEITARIA'),
    (95, 'BOMKAFE', 'ROTISSERIA')
ON CONFLICT DO NOTHING;

-- Metadados do Directus: a coleção da lista (reiniciar o Directus depois).
DO $$
BEGIN
    IF to_regclass('config.directus_collections') IS NULL THEN
        RETURN;
    END IF;
    INSERT INTO config.directus_collections (collection, icon, note, display_template)
    SELECT 'logus_secao', 'segment', 'Seções do Logus (sincronizado pelo dbt)', '{{departamento}} › {{secao}}'
    WHERE NOT EXISTS (SELECT 1 FROM config.directus_collections WHERE collection = 'logus_secao');
END $$;

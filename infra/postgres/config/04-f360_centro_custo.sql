-- Centro de custo do F360 -> departamento do Logus (caddepto.dcr_depto), para a Rentabilidade por
-- Setor. Despesa de centro com departamento é DIRETA do setor; sem departamento (nulo) é INDIRETA e
-- é rateada entre os setores pela participação nas vendas da filial.
-- Rodado a cada deploy pelo db-setup como o papel config_app. Só "CREATE ... IF NOT EXISTS".
-- Origem: de/para fixo no notebook "Fato Item" do Fabric (14/10/2026), reproduzido como está para a
-- conferência no centavo. Pontos a rever com o Camillo depois da conferência:
--   * "Armazem - Confeitaria" vai para CAFETERIA (há também o departamento CONFEITARIA);
--   * "Armazem - Churrasco" e "Armazem - Serviços" não têm departamento no Fabric (viram rateio),
--     embora existam CHURRASCO e SERVICOS no Logus.
-- O nome é comparado sem espaços nas pontas (o F360 grava "Armazém Bomgado " com espaço no fim).
CREATE TABLE IF NOT EXISTS config.f360_centro_custo (
    centro_de_custo  text PRIMARY KEY,
    departamento     text,                      -- nulo = despesa indireta (rateada)
    observacao       text,
    alterado_em      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE config.f360_centro_custo IS 'Centro de custo do F360 -> departamento do Logus (Rentabilidade por Setor)';

CREATE OR REPLACE TRIGGER f360_centro_custo_alterado_em
    BEFORE UPDATE ON config.f360_centro_custo
    FOR EACH ROW EXECUTE FUNCTION config.tocar_alterado_em();

INSERT INTO config.f360_centro_custo (centro_de_custo, departamento, observacao) VALUES
    ('Armazem - Açougue',     'ACOUGUE',       NULL),
    ('Armazem - Bebidas',     'BEBIDAS',       NULL),
    ('Armazem - Confeitaria', 'CAFETERIA',     'Como no Fabric; rever (há o departamento CONFEITARIA)'),
    ('Armazem - Fiambreria',  'FIAMBRERIA',    NULL),
    ('Armazem - Frios e CIA', 'FRIOS E CIA',   NULL),
    ('Armazem - Hortifruti',  'HORTIFRUTI',    NULL),
    ('Armazem - Mercearia',   'MERCEARIA',     NULL),
    ('Armazem - Padaria',     'PADARIA E CIA', NULL),
    ('Armazem - Rotisseria',  'ROTISSERIA',    NULL),
    ('Armazem - Churrasco',   NULL,            'Sem departamento no Fabric (rateio); rever (há CHURRASCO)'),
    ('Armazem - Serviços',    NULL,            'Sem departamento no Fabric (rateio); rever (há SERVICOS)'),
    ('Armazém Bomgado',       NULL,            'Despesa geral da filial: rateio'),
    ('Bomgado Kafe',          NULL,            'Despesa geral da filial: rateio')
ON CONFLICT DO NOTHING;

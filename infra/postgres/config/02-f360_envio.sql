-- Fila de títulos a lançar no F360 (fase 2 da integração Logus → F360), revisada no Directus.
-- Rodado a cada deploy pelo db-setup como o papel config_app. Só "CREATE ... IF NOT EXISTS".
--
-- Fluxo (ingestao/f360/envio.py, DAG f360_envio):
--   1. a DAG inclui aqui, com status 'pendente', as pendências das conferências: nota de entrada do
--      Logus sem conta a pagar no F360 e boleto do Logus sem conta a receber no F360;
--   2. o Camillo revisa no Directus (pode corrigir plano, centro de custo, conta, parcelas) e muda o
--      status para 'aprovado' (ou 'descartado');
--   3. a DAG envia os aprovados pelo webhook de títulos do F360 (só cria título) -> 'enviado';
--   4. a leitura do F360 (raw_f360) confirma que o título entrou -> 'confirmado'; se não aparecer em
--      2 dias -> 'erro' (ver a tela Upload de Arquivos do F360).
CREATE TABLE IF NOT EXISTS config.f360_envio (
    id               bigserial PRIMARY KEY,
    chave            text NOT NULL UNIQUE,          -- 'pagar:<cnpj>:<nota>' ou 'receber:boleto:<numero>'
    origem           text NOT NULL,                 -- 'compra sem título' | 'boleto sem título'
    motivo           text,                          -- a pendência da conferência que gerou a linha
    tipo_titulo      text NOT NULL CHECK (tipo_titulo IN ('pagar', 'receber')),
    empresa_cnpj     text NOT NULL,                 -- formatado, como o F360 espera (00.000.000/0000-00)
    pessoa_nome      text,
    pessoa_doc       text,                          -- CPF/CNPJ (só dígitos)
    numero_titulo    text NOT NULL,
    tipo_documento   text NOT NULL,                 -- 'nota fiscal' | 'boleto' (lista do webhook)
    emissao          date NOT NULL,
    valor            numeric(14,2) NOT NULL,
    parcelas         jsonb NOT NULL,                -- [{"numeroParcela", "vencimento", "valor", "codigoDeBarras"}]
    conta_bancaria   text,                          -- nome da conta no F360
    meio_pagamento   text,                          -- lista do webhook (boleto, dda, pix não existe: 'transferência bancária')
    plano_de_contas  text,                          -- nome do plano no F360 (sugerido pelo histórico do fornecedor)
    centro_de_custo  text,
    competencia      text,                          -- MM-yyyy
    historico        text,
    status           text NOT NULL DEFAULT 'pendente'
                     CHECK (status IN ('pendente', 'aprovado', 'enviado', 'confirmado', 'erro', 'descartado')),
    rastreio_id      text,
    enviado_em       timestamptz,
    confirmado_em    timestamptz,
    erro             text,
    criado_em        timestamptz NOT NULL DEFAULT now(),
    alterado_em      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE config.f360_envio IS 'Fila de títulos a lançar no F360 pelo webhook; o Camillo aprova cada linha no Directus';
CREATE INDEX IF NOT EXISTS f360_envio_status_idx ON config.f360_envio (status);

CREATE OR REPLACE TRIGGER f360_envio_alterado_em
    BEFORE UPDATE ON config.f360_envio
    FOR EACH ROW EXECUTE FUNCTION config.tocar_alterado_em();

-- A DAG (papel ingestao) monta a fila e atualiza o status; o Directus (config_app, dono) edita.
GRANT SELECT, INSERT, UPDATE ON config.f360_envio TO ingestao;
GRANT USAGE ON SEQUENCE config.f360_envio_id_seq TO ingestao;

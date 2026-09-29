#!/bin/sh
# Roda a cada deploy (serviço db-setup), depois do Postgres subir. Idempotente: cria o que falta
# e reaplica as permissões. (O initdb/ só roda no 1º boot; mudanças de papel/schema vêm para cá.)
#
# Papéis:
#   ingestao     dono dos schemas raw_* e api (extratores e materialização das views)
#   api_leitura  só SELECT no schema api (gateway OData do Excel)
#   mcp_leitura  só SELECT em api, legado e raw_* (MCP de SQL do Claude/Copilot)
#   config_app   dono do schema config (Directus: tabelas de sistema directus_* e as de de/para).
#                O ingestao e o mcp_leitura leem só as tabelas de de/para (nunca as directus_*,
#                que têm usuários e hashes de senha); a permissão é reaplicada a cada deploy.
# O schema legado (cópia única do PlenoKW feita com pgloader em 28/09/2026) pertence ao postgres.
set -eu
export PGPASSWORD="$POSTGRES_PASSWORD"
psql -v ON_ERROR_STOP=1 -h postgres -U postgres -d dados \
  -v api_pw="$API_DB_PASSWORD" -v mcp_pw="$MCP_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', r) FROM unnest(ARRAY['api_leitura','mcp_leitura']) r
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) \gexec
ALTER ROLE api_leitura PASSWORD :'api_pw';
ALTER ROLE mcp_leitura PASSWORD :'mcp_pw';
ALTER ROLE mcp_leitura SET default_transaction_read_only = on;
ALTER ROLE mcp_leitura SET statement_timeout = '60s';
ALTER ROLE api_leitura SET default_transaction_read_only = on;
ALTER ROLE api_leitura SET search_path = api;

CREATE SCHEMA IF NOT EXISTS raw_jetbov AUTHORIZATION ingestao;
CREATE SCHEMA IF NOT EXISTS raw_logus AUTHORIZATION ingestao;
CREATE SCHEMA IF NOT EXISTS api AUTHORIZATION ingestao;

-- Leitura: o que já existe e o que o ingestao criar daqui para frente.
GRANT USAGE ON SCHEMA api TO api_leitura, mcp_leitura;
GRANT USAGE ON SCHEMA raw_jetbov, raw_logus TO mcp_leitura;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_leitura, mcp_leitura;
GRANT SELECT ON ALL TABLES IN SCHEMA raw_jetbov, raw_logus TO mcp_leitura;
ALTER DEFAULT PRIVILEGES FOR ROLE ingestao IN SCHEMA api GRANT SELECT ON TABLES TO api_leitura, mcp_leitura;
ALTER DEFAULT PRIVILEGES FOR ROLE ingestao IN SCHEMA raw_jetbov, raw_logus GRANT SELECT ON TABLES TO mcp_leitura;

-- Legado: só leitura para o MCP e para o ingestao (as views vw_* leem dele).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'legado') THEN
    GRANT USAGE ON SCHEMA legado TO mcp_leitura, ingestao;
    GRANT SELECT ON ALL TABLES IN SCHEMA legado TO mcp_leitura, ingestao;
  END IF;
END $$;
SQL
# Directus / schema config: só quando a senha do config_app estiver no cofre (directus-db-password).
if [ -n "${DIRECTUS_DB_PASSWORD:-}" ]; then
  psql -v ON_ERROR_STOP=1 -h postgres -U postgres -d dados -v cfg_pw="$DIRECTUS_DB_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE config_app LOGIN' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'config_app') \gexec
ALTER ROLE config_app PASSWORD :'cfg_pw';
ALTER ROLE config_app SET search_path = config;
CREATE SCHEMA IF NOT EXISTS config AUTHORIZATION config_app;
SQL
  for f in /config/*.sql; do
    [ -e "$f" ] || continue
    { echo "SET ROLE config_app;"; cat "$f"; } | psql -v ON_ERROR_STOP=1 -q -h postgres -U postgres -d dados
  done
  psql -v ON_ERROR_STOP=1 -q -h postgres -U postgres -d dados <<'SQL'
GRANT USAGE ON SCHEMA config TO ingestao, mcp_leitura;
SELECT format('GRANT SELECT ON config.%I TO ingestao, mcp_leitura', tablename)
  FROM pg_tables WHERE schemaname = 'config' AND tablename NOT LIKE 'directus\_%' \gexec
SQL
  echo "db-setup: schema config ok"
fi
echo "db-setup ok"

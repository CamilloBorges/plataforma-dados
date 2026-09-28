#!/bin/bash
# Roda só no primeiro boot (volume vazio). Cria um banco e um usuário por dono:
#   airflow  -> banco "airflow" (metadados do Airflow)
#   ingestao -> banco "dados", dono dos schemas raw_* (dados brutos das fontes)
# Para refazer do zero: apague o volume postgres-data e reimplante.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username postgres <<SQL
CREATE ROLE airflow LOGIN PASSWORD '${AIRFLOW_DB_PASSWORD}';
CREATE DATABASE airflow OWNER airflow;

CREATE ROLE ingestao LOGIN PASSWORD '${INGESTAO_DB_PASSWORD}';
CREATE DATABASE dados OWNER postgres;
SQL

psql -v ON_ERROR_STOP=1 --username postgres --dbname dados <<SQL
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA raw_jetbov AUTHORIZATION ingestao;
SQL

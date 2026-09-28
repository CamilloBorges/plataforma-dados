#!/bin/sh
# Entrada dos contêineres do Airflow, chamada pelo com_segredos.sh (que já exportou os segredos):
# monta as configurações que embutem senha e segue para o entrypoint oficial da imagem.
set -e
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow:${AIRFLOW_DB_PASSWORD}@postgres:5432/airflow"
export AIRFLOW__CORE__FERNET_KEY="$AIRFLOW_FERNET_KEY"
export AIRFLOW__API_AUTH__JWT_SECRET="$AIRFLOW_JWT_SECRET"
# Conexão usada pelos extratores (schemas raw_*), com usuário próprio.
export DADOS_DB_URL="postgresql://ingestao:${INGESTAO_DB_PASSWORD}@postgres:5432/dados"
exec /usr/bin/dumb-init -- /entrypoint "$@"

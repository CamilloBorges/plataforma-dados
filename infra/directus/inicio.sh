#!/bin/sh
# Entrada do Directus, chamada pelo com_segredos.sh (que já exportou os segredos do cofre):
# traduz os nomes do cofre para os que o Directus espera e segue para o comando original da imagem.
set -e
: "${DIRECTUS_DB_PASSWORD:?grave directus-db-password no cofre}"
: "${DIRECTUS_SECRET:?grave directus-secret no cofre}"
: "${DIRECTUS_ADMIN_PASSWORD:?grave directus-admin-password no cofre}"
export DB_PASSWORD="$DIRECTUS_DB_PASSWORD" SECRET="$DIRECTUS_SECRET" ADMIN_PASSWORD="$DIRECTUS_ADMIN_PASSWORD"
unset DIRECTUS_DB_PASSWORD DIRECTUS_SECRET DIRECTUS_ADMIN_PASSWORD
exec docker-entrypoint.sh node docker-entrypoint.cjs  # comando original da imagem 12.x

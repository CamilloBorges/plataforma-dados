#!/bin/sh
# Entrada do Directus, chamada pelo com_segredos.sh (que já exportou os segredos do cofre):
# traduz os nomes do cofre para os que o Directus espera e segue para o comando original da imagem.
set -e
: "${DIRECTUS_DB_PASSWORD:?grave directus-db-password no cofre}"
: "${DIRECTUS_SECRET:?grave directus-secret no cofre}"
: "${DIRECTUS_ADMIN_PASSWORD:?grave directus-admin-password no cofre}"
export DB_PASSWORD="$DIRECTUS_DB_PASSWORD" SECRET="$DIRECTUS_SECRET" ADMIN_PASSWORD="$DIRECTUS_ADMIN_PASSWORD"

# Licença: desde a 12.0 o SSO não existe no tier "Core" (sem chave). A Bomgado se enquadra no
# "Open Innovation Grant" (receita < US$ 5 mi e < 50 funcionários), que é gratuito e inclui SSO.
# A chave recebida vai no cofre como directus-license-key.
if [ -n "${DIRECTUS_LICENSE_KEY:-}" ]; then
  export LICENSE_KEY="$DIRECTUS_LICENSE_KEY"
fi

# Login pelo Entra ID (OpenID Connect), ligado quando o app "Directus Config" estiver no cofre
# (directus-entra-client-id/-secret; o locatário é o mesmo da dados-api, entra-tenant-id).
# Callback registrado no Entra: https://config.bomgado.net/auth/login/microsoft/callback
if [ -n "${DIRECTUS_ENTRA_CLIENT_ID:-}" ] && [ -n "${DIRECTUS_ENTRA_CLIENT_SECRET:-}" ] && [ -n "${ENTRA_TENANT_ID:-}" ]; then
  export AUTH_PROVIDERS=microsoft \
    AUTH_MICROSOFT_DRIVER=openid \
    AUTH_MICROSOFT_LABEL="Microsoft (Bomgado)" \
    AUTH_MICROSOFT_CLIENT_ID="$DIRECTUS_ENTRA_CLIENT_ID" \
    AUTH_MICROSOFT_CLIENT_SECRET="$DIRECTUS_ENTRA_CLIENT_SECRET" \
    AUTH_MICROSOFT_ISSUER_URL="https://login.microsoftonline.com/$ENTRA_TENANT_ID/v2.0/.well-known/openid-configuration" \
    AUTH_MICROSOFT_SCOPE="openid profile email" \
    AUTH_MICROSOFT_IDENTIFIER_KEY=preferred_username \
    AUTH_MICROSOFT_ALLOW_PUBLIC_REGISTRATION=true
  # Usuário criado no 1º login entra SEM papel (não vê nada) até o admin atribuir um.
else
  echo "inicio.sh: login Entra desligado (faltam directus-entra-client-id/-secret no cofre)" >&2
fi
unset DIRECTUS_DB_PASSWORD DIRECTUS_SECRET DIRECTUS_ADMIN_PASSWORD DIRECTUS_ENTRA_CLIENT_ID DIRECTUS_ENTRA_CLIENT_SECRET DIRECTUS_LICENSE_KEY
exec docker-entrypoint.sh node docker-entrypoint.cjs  # comando original da imagem 12.x

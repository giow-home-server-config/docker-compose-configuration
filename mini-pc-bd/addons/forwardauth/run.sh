#!/usr/bin/env bash
set -e

# Le as opcoes direto do /data/options.json em vez de usar bashio::config: com
# host_network=true o container nao consegue autenticar na API do supervisor
# (403 forbidden), entao bashio::config falha.
OPTS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // ""' "${OPTS}"; }

for k in client_id client_secret secret whitelist; do
    if [ -z "$(opt "$k")" ]; then
        echo "[FATAL] opcao '${k}' vazia." >&2
        exit 1
    fi
done

# Mesmos nomes de env do container 'oauth' do mk1. O SECRET precisa ser
# identico ao de la: e ele que assina o cookie, entao com o mesmo valor a
# sessao vale nas duas maquinas e ninguem precisa logar de novo.
export CLIENT_ID="$(opt client_id)"
export CLIENT_SECRET="$(opt client_secret)"
export SECRET="$(opt secret)"
export COOKIE_DOMAIN="$(opt cookie_domain)"
export AUTH_HOST="$(opt auth_host)"
export URL_PATH="$(opt url_path)"
export WHITELIST="$(opt whitelist)"
export LIFETIME="$(opt lifetime)"
export PORT="$(opt port)"
export LOG_LEVEL="$(opt log_level)"
export LOG_FORMAT=text
export INSECURE_COOKIE=false

echo "[INFO] forward-auth :${PORT} como 'forwardauth' | auth_host=${AUTH_HOST} cookie_domain=${COOKIE_DOMAIN} whitelist=$(echo "${WHITELIST}" | tr ',' '\n' | wc -l) emails"

# So variaveis de ambiente, nenhum arquivo: basta trocar de usuario.
exec su-exec forwardauth traefik-forward-auth

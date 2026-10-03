#!/usr/bin/env bash
set -e

# Le as opcoes direto do /data/options.json em vez de usar bashio::config: com
# host_network=true o container nao consegue autenticar na API do supervisor
# (403 forbidden), entao bashio::config falha.
OPTS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // ""' "${OPTS}"; }

ACME_EMAIL="$(opt acme_email)"
CF_TOKEN="$(opt cf_dns_api_token)"
LOG_LEVEL="$(opt log_level)"
LISTEN_PORT="$(opt listen_port)"
TRUSTED_IPS="$(opt trusted_forward_ips)"
ACCESS_LOG="$(opt access_log)"
ACCESS_LOG_MAX_BYTES="$(opt access_log_max_bytes)"
RULES_DIR="$(opt rules_dir)"
ACME_CA_SERVER="$(opt acme_ca_server)"
[ -n "${LOG_LEVEL}" ] || LOG_LEVEL=INFO
[ -n "${LISTEN_PORT}" ] || LISTEN_PORT=8443
[ -n "${TRUSTED_IPS}" ] || TRUSTED_IPS=127.0.0.1/32
[ -n "${ACCESS_LOG_MAX_BYTES}" ] || ACCESS_LOG_MAX_BYTES=104857600

RUN_AS=traefik

if [ -z "${CF_TOKEN}" ]; then
    echo "[FATAL] cf_dns_api_token esta vazio - sem ele o ACME DNS-01 nao emite o certificado." >&2
    exit 1
fi

# As regras vem do repositorio (git). Sem elas o traefik subiria sem nenhuma
# rota e responderia 404 para tudo - melhor falhar alto.
if ! find "${RULES_DIR}" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.toml' \) 2>/dev/null | grep -q .; then
    echo "[FATAL] nenhuma regra em ${RULES_DIR} (o clone /addons/homelab existe?)." >&2
    exit 1
fi

# Segredos -> variaveis de ambiente. As regras leem com {{ env "NOME" }} (Go
# template do file provider), entao o valor nunca precisa estar no repositorio.
while IFS=$'\t' read -r name value; do
    [ -n "${name}" ] || continue
    if ! [[ "${name}" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        echo "[FATAL] nome de segredo invalido: '${name}'." >&2
        exit 1
    fi
    export "${name}=${value}"
done < <(jq -r '.secrets[]? | [.name, .value] | @tsv' "${OPTS}")

# Avisa (sem derrubar) quando uma regra usa um segredo que nao foi cadastrado.
# Regra de bypass por API key deve se proteger com {{ if env "X" }} - ver
# mini-pc-bd/traefik/README.md.
MISSING=()
for v in $(find "${RULES_DIR}" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.toml' \) \
              -exec grep -hoE 'env "[A-Z][A-Z0-9_]*"' {} + | sed -E 's/env "(.*)"/\1/' | sort -u); do
    [ -n "${!v:-}" ] || MISSING+=("${v}")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "[WARN] regras usam segredos sem valor em 'secrets': ${MISSING[*]}" >&2
fi

export CF_DNS_API_TOKEN="${CF_TOKEN}"

# Arquivos que o traefik escreve passam a ser do usuario dele.
ACME_FILE=/config/acme.json
mkdir -p /config
[ -f "${ACME_FILE}" ] || echo '{}' > "${ACME_FILE}"
chmod 600 "${ACME_FILE}"
chown -R "${RUN_AS}:${RUN_AS}" /config

ACCESS_LOG_ARGS=()
if [ -n "${ACCESS_LOG}" ]; then
    mkdir -p "$(dirname "${ACCESS_LOG}")"
    touch "${ACCESS_LOG}"
    chown "${RUN_AS}:${RUN_AS}" "$(dirname "${ACCESS_LOG}")" "${ACCESS_LOG}"
    ACCESS_LOG_ARGS=(
        --accessLog.filePath="${ACCESS_LOG}"
        --accessLog.format=json
        --accessLog.bufferingSize=0
    )
    # Trunca em vez de rotacionar: o traefik escreve com O_APPEND e o crowdsec
    # detecta truncamento e volta a ler do inicio. Sem isso o arquivo cresce sem
    # limite e um dia enche a particao de dados do HAOS.
    (
        while true; do
            sleep 3600
            sz=$(stat -c %s "${ACCESS_LOG}" 2>/dev/null || echo 0)
            if [ "${sz}" -gt "${ACCESS_LOG_MAX_BYTES}" ]; then
                : > "${ACCESS_LOG}"
                echo "[INFO] access log truncado (estava com ${sz} bytes)"
            fi
        done
    ) &
else
    ACCESS_LOG_ARGS=(--accessLog=false)
fi

ACME_ARGS=()
if [ -n "${ACME_CA_SERVER}" ]; then
    ACME_ARGS=(--certificatesResolvers.cloudflare.acme.caServer="${ACME_CA_SERVER}")
    echo "[WARN] ACME apontando para ${ACME_CA_SERVER} (nao e o Let's Encrypt de producao)." >&2
fi

echo "[INFO] traefik :${LISTEN_PORT} como '${RUN_AS}' | regras: ${RULES_DIR} ($(find "${RULES_DIR}" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.toml' \) | wc -l) arquivos) | segredos: $(jq '.secrets | length' "${OPTS}")"
echo "[INFO] trustedIPs=${TRUSTED_IPS} accessLog=${ACCESS_LOG:-off}"

exec su-exec "${RUN_AS}" traefik \
    --entryPoints.https.address=":${LISTEN_PORT}" \
    --entryPoints.https.forwardedHeaders.trustedIPs="${TRUSTED_IPS}" \
    --providers.file.directory="${RULES_DIR}" \
    --providers.file.watch=true \
    --certificatesResolvers.cloudflare.acme.email="${ACME_EMAIL}" \
    --certificatesResolvers.cloudflare.acme.storage="${ACME_FILE}" \
    --certificatesResolvers.cloudflare.acme.dnsChallenge.provider=cloudflare \
    --certificatesResolvers.cloudflare.acme.dnsChallenge.resolvers=1.1.1.1:53,1.0.0.1:53 \
    "${ACME_ARGS[@]}" \
    --experimental.localPlugins.crowdsec.moduleName=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin \
    --log.level="${LOG_LEVEL}" \
    "${ACCESS_LOG_ARGS[@]}" \
    --api=false --ping=false \
    --global.checkNewVersion=false --global.sendAnonymousUsage=false

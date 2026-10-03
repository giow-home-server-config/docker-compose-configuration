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
FWD_AUTH="$(opt forward_auth_address)"
TRUSTED_IPS="$(opt trusted_forward_ips)"
ACCESS_LOG="$(opt access_log)"
ACCESS_LOG_MAX_BYTES="$(opt access_log_max_bytes)"
RL_AVG="$(opt rate_limit_average)"
RL_BURST="$(opt rate_limit_burst)"
CS_ENABLED="$(jq -r '.crowdsec_enabled // false' "${OPTS}")"
CS_HOST="$(opt crowdsec_lapi_host)"
CS_KEY="$(opt crowdsec_lapi_key)"
[ -n "${LOG_LEVEL}" ] || LOG_LEVEL=INFO
[ -n "${FWD_AUTH}" ] || FWD_AUTH=http://127.0.0.1:4181
[ -n "${TRUSTED_IPS}" ] || TRUSTED_IPS=127.0.0.1/32
[ -n "${RL_AVG}" ] || RL_AVG=100
[ -n "${RL_BURST}" ] || RL_BURST=50
[ -n "${ACCESS_LOG_MAX_BYTES}" ] || ACCESS_LOG_MAX_BYTES=104857600

if [ -z "${CF_TOKEN}" ]; then
    echo "[FATAL] cf_dns_api_token esta vazio - sem ele o ACME DNS-01 nao emite o certificado." >&2
    exit 1
fi

if [ "$(jq '.routes | length' "${OPTS}")" -eq 0 ]; then
    echo "[FATAL] nenhuma rota configurada em 'routes'." >&2
    exit 1
fi

# So liga o bouncer se a chave existir. Sem essa guarda, um erro de config
# deixaria o traefik falando com uma LAPI que recusa tudo.
if [ "${CS_ENABLED}" = "true" ] && [ -z "${CS_KEY}" ]; then
    echo "[FATAL] crowdsec_enabled=true mas crowdsec_lapi_key esta vazia." >&2
    exit 1
fi

PLUGIN_ARGS=()
if [ "${CS_ENABLED}" = "true" ]; then
    PLUGIN_ARGS=(--experimental.localPlugins.crowdsec.moduleName=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin)
fi

export CF_DNS_API_TOKEN="${CF_TOKEN}"

DYNAMIC_DIR=/config/dynamic
ACME_FILE=/config/acme.json

mkdir -p "${DYNAMIC_DIR}"
[ -f "${ACME_FILE}" ] || echo '{}' > "${ACME_FILE}"
chmod 600 "${ACME_FILE}"

ACCESS_LOG_ARGS=()
if [ -n "${ACCESS_LOG}" ]; then
    mkdir -p "$(dirname "${ACCESS_LOG}")"
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

# Um router + um service por rota. O nome vem do dominio com os pontos trocados
# por hifen, para ser um identificador valido no traefik.
#
# ipStrategy.depth=1 pega o IP mais a direita do X-Forwarded-For, que e o que a
# cloudflare poe como cliente real. Sem isso o rateLimit agruparia todo mundo
# como 127.0.0.1 e viraria um limite global, nao por IP.
jq -r --arg fwd "${FWD_AUTH}" --argjson avg "${RL_AVG}" --argjson burst "${RL_BURST}" \
      --arg csh "${CS_HOST}" --arg csk "${CS_KEY}" --argjson cs "${CS_ENABLED}" '
  def id: gsub("[^a-zA-Z0-9]"; "-");
  def chain: "        - ratelimit" + (if $cs then "\n        - crowdsec" else "" end);
  "http:",
  "  middlewares:",
  (if $cs then
    "    crowdsec:\n      plugin:\n        crowdsec:\n          enabled: \"true\"\n          crowdsecMode: live\n          crowdsecLapiScheme: http\n          crowdsecLapiHost: \"\($csh)\"\n          crowdsecLapiKey: \"\($csk)\"\n          forwardedHeadersTrustedIPs:\n            - 127.0.0.1/32\n          clientTrustedIPs:\n            - 192.168.1.0/24"
   else empty end),
  "    ratelimit:",
  "      rateLimit:",
  "        average: \($avg)",
  "        burst: \($burst)",
  "        sourceCriterion:",
  "          ipStrategy:",
  "            depth: 1",
  "    oauth:",
  "      forwardAuth:",
  "        address: \"\($fwd)\"",
  "        trustForwardHeader: true",
  "        authResponseHeaders:",
  "          - X-Forwarded-User",
  "  serversTransports:",
  "    insecure:",
  "      insecureSkipVerify: true",
  "  routers:",
  (.routes[] | "    \(.domain|id):\n      rule: \"Host(`\(.domain)`)\"\n      entryPoints:\n        - https\n      service: \(.domain|id)\n      middlewares:\n\(chain)\(if .auth then "\n        - oauth" else "" end)\n      tls:\n        certResolver: cloudflare"),
  "  services:",
  (.routes[] | "    \(.domain|id):\n      loadBalancer:\n        passHostHeader: true\(if .insecure_skip_verify then "\n        serversTransport: insecure" else "" end)\n        servers:\n          - url: \"\(.backend)\"")
' "${OPTS}" > "${DYNAMIC_DIR}/routes.yml"

jq -r '.routes[] | "[INFO] traefik: \(.domain) -> \(.backend)\(if .auth then " [oauth]" else "" end)"' "${OPTS}"
echo "[INFO] trustedIPs=${TRUSTED_IPS} rateLimit=${RL_AVG}/s burst=${RL_BURST} accessLog=${ACCESS_LOG:-off} crowdsec=${CS_ENABLED}"

exec traefik \
    --entryPoints.https.address=:443 \
    --entryPoints.https.forwardedHeaders.trustedIPs="${TRUSTED_IPS}" \
    --providers.file.directory="${DYNAMIC_DIR}" \
    --providers.file.watch=true \
    --certificatesResolvers.cloudflare.acme.email="${ACME_EMAIL}" \
    --certificatesResolvers.cloudflare.acme.storage="${ACME_FILE}" \
    --certificatesResolvers.cloudflare.acme.dnsChallenge.provider=cloudflare \
    --certificatesResolvers.cloudflare.acme.dnsChallenge.resolvers=1.1.1.1:53,1.0.0.1:53 \
    --log.level="${LOG_LEVEL}" \
    "${ACCESS_LOG_ARGS[@]}" \
    "${PLUGIN_ARGS[@]}" \
    --api=false --ping=false \
    --global.checkNewVersion=false --global.sendAnonymousUsage=false

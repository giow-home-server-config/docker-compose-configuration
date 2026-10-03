#!/usr/bin/env bash
set -e

# Le as opcoes direto do /data/options.json em vez de usar bashio::config: com
# host_network=true o container nao consegue autenticar na API do supervisor
# (403 forbidden), entao bashio::config falha.
OPTS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // ""' "${OPTS}"; }

SERVER_ADDR="$(opt server_addr)"
SERVER_PORT="$(opt server_port)"
TOKEN="$(opt token)"
PROXY_NAME="$(opt proxy_name)"
LOCAL_PORT="$(opt local_port)"
CERT_DIR="$(opt cert_dir)"
LOG_LEVEL="$(opt log_level)"
[ -n "${LOG_LEVEL}" ] || LOG_LEVEL=info

if [ -z "${TOKEN}" ]; then
    echo "[FATAL] token vazio - o frps recusa a conexao sem ele." >&2
    exit 1
fi

if [ "$(jq '.custom_domains | length' "${OPTS}")" -eq 0 ]; then
    echo "[FATAL] nenhum dominio configurado em 'custom_domains'." >&2
    exit 1
fi

for f in ca.crt client.crt client.key; do
    if [ ! -f "${CERT_DIR}/${f}" ]; then
        echo "[FATAL] faltando ${CERT_DIR}/${f} - o frps exige mTLS (transport.tls.force)." >&2
        exit 1
    fi
done

DOMAINS="$(jq -c '.custom_domains' "${OPTS}")"
CONFIG=/data/frpc.toml
RUN_AS=frpc

# O client.key em /share/frp e 600 de outro dono e o /share e montado so para
# leitura: copia os certificados para /data, com dono do usuario do frpc.
CERTS=/data/certs
mkdir -p "${CERTS}"
cp "${CERT_DIR}/ca.crt" "${CERT_DIR}/client.crt" "${CERT_DIR}/client.key" "${CERTS}/"
chmod 700 "${CERTS}"; chmod 600 "${CERTS}"/*

# customDomains com os dominios EXATOS: no frps, match exato vence o curinga
# *.giow.dev registrado pelo mk1. Parar este add-on devolve os dominios ao mk1.
cat > "${CONFIG}" <<EOF
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${TOKEN}"

transport.tls.enable = true
transport.tls.certFile = "${CERTS}/client.crt"
transport.tls.keyFile = "${CERTS}/client.key"
transport.tls.trustedCaFile = "${CERTS}/ca.crt"

log.level = "${LOG_LEVEL}"

[[proxies]]
name = "${PROXY_NAME}"
type = "https"
localIp = "127.0.0.1"
localPort = ${LOCAL_PORT}
customDomains = ${DOMAINS}
EOF

chmod 600 "${CONFIG}"
chown -R "${RUN_AS}:${RUN_AS}" "${CONFIG}" "${CERTS}"

echo "[INFO] frpc ${SERVER_ADDR}:${SERVER_PORT} como '${RUN_AS}' | ${DOMAINS} -> 127.0.0.1:${LOCAL_PORT}"

exec su-exec "${RUN_AS}" frpc -c "${CONFIG}"

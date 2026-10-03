#!/bin/bash
set -e

# Le as opcoes direto do /data/options.json: com host_network=true o container
# nao consegue autenticar na API do supervisor.
OPTS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // ""' "${OPTS}"; }

ACCESS_LOG="$(opt access_log)"
BOUNCER_NAME="$(opt bouncer_name)"
BOUNCER_KEY="$(opt bouncer_key)"
LAPI_PORT="$(opt lapi_port)"
COLLECTIONS="$(opt collections)"
WHITELIST_IPS="$(opt whitelist_ips)"
LOG_LEVEL="$(opt log_level)"
UNBAN_IPS="$(opt unban_ips)"
BAN_IPS="$(opt ban_ips)"
BAN_DURATION="$(opt ban_duration)"
[ -n "${BAN_DURATION}" ] || BAN_DURATION=4h
RUN_AS=crowdsec

if [ -z "${BOUNCER_KEY}" ]; then
    echo "[FATAL] bouncer_key vazia - sem ela o traefik nao consegue consultar a LAPI." >&2
    exit 1
fi

# O /data do add-on e o unico lugar persistente. Sem isso o banco de decisoes e
# as chaves de bouncer somem a cada restart.
mkdir -p /data/crowdsec-data /data/crowdsec-etc
if [ ! -L /var/lib/crowdsec/data ]; then
    [ -d /var/lib/crowdsec/data ] && cp -an /var/lib/crowdsec/data/. /data/crowdsec-data/ 2>/dev/null || true
    rm -rf /var/lib/crowdsec/data
    ln -s /data/crowdsec-data /var/lib/crowdsec/data
fi

# Acquisition: o access log do traefik em JSON.
mkdir -p /etc/crowdsec/acquis.d
cat > /etc/crowdsec/acquis.d/traefik.yaml <<EOF
filenames:
  - ${ACCESS_LOG}
labels:
  type: traefik
EOF

# Whitelist da rede local + rede dos add-ons, para o crowdsec nunca banir a
# propria casa nem o trafego interno.
mkdir -p /etc/crowdsec/parsers/s02-enrich
{
    echo "name: local/whitelist-lan"
    echo "description: nao banir rede local e rede hassio"
    echo "whitelist:"
    echo "  reason: rede local"
    echo "  ip:"
    for ip in ${WHITELIST_IPS}; do
        case "${ip}" in
            */*) : ;;
            *) echo "    - \"${ip}\"" ;;
        esac
    done
    echo "  cidr:"
    for ip in ${WHITELIST_IPS}; do
        case "${ip}" in
            */*) echo "    - \"${ip}\"" ;;
        esac
    done
} > /etc/crowdsec/parsers/s02-enrich/whitelist-lan.yaml

# Com host_network a LAPI ficaria em 0.0.0.0 e exposta na LAN. O config.yaml.local
# sobrescreve so essa chave e o docker_start.sh nao mexe em arquivos ja existentes.
cat > /etc/crowdsec/config.yaml.local <<EOF
api:
  server:
    listen_uri: 127.0.0.1:${LAPI_PORT}
EOF

# A imagem exige um volume montado em /var/lib/crowdsec/data. Aqui ele e um
# symlink para /data/crowdsec-data, que e o volume persistente do add-on - a
# persistencia existe, so nao no formato que o check procura.
export CROWDSEC_BYPASS_DB_VOLUME_CHECK=true

export COLLECTIONS="${COLLECTIONS}"
export BOUNCER_KEY_${BOUNCER_NAME}="${BOUNCER_KEY}"
export LEVEL_${LOG_LEVEL^^}=true
export LOCAL_API_URL="http://127.0.0.1:${LAPI_PORT}"
export DISABLE_ONLINE_API=false
export USE_WAL=true

# A env COLLECTIONS do entrypoint oficial nao instalou nada aqui, entao fazemos
# explicitamente. Precisa ser DEPOIS do sync do /staging (que popula /etc/crowdsec)
# e ANTES do crowdsec subir, senao os parsers nao entram no runtime.
if [ -d /staging/etc/crowdsec ]; then
    mkdir -p /etc/crowdsec
    cp -an /staging/etc/crowdsec/. /etc/crowdsec/ 2>/dev/null || true
fi
if cscli hub update >/dev/null 2>&1; then
    for c in ${COLLECTIONS}; do
        if cscli collections install "${c}" >/dev/null 2>&1; then
            echo "[INFO] collection instalada: ${c}"
        else
            echo "[WARN] falhou instalar collection: ${c}" >&2
        fi
    done
else
    echo "[WARN] 'cscli hub update' falhou - sem internet? collections nao instaladas." >&2
fi

echo "[INFO] crowdsec: lendo ${ACCESS_LOG} | LAPI 127.0.0.1:${LAPI_PORT} | bouncer=${BOUNCER_NAME}"

# Entrypoint oficial da imagem: instala collections, registra bouncers via
# BOUNCER_KEY_*, e sobe o crowdsec.
# Aplica ban/unban depois que a LAPI subir. Roda em background porque o exec
# abaixo substitui este processo pelo crowdsec.
if [ -n "${UNBAN_IPS}${BAN_IPS}" ]; then
    (
        for _ in $(seq 1 90); do
            su-exec "${RUN_AS}" cscli lapi status >/dev/null 2>&1 && break
            sleep 2
        done
        for ip in ${UNBAN_IPS}; do
            su-exec "${RUN_AS}" cscli decisions delete --ip "${ip}" >/dev/null 2>&1 \
                && echo "[INFO] unban aplicado: ${ip}" || echo "[WARN] unban falhou: ${ip}" >&2
        done
        for ip in ${BAN_IPS}; do
            su-exec "${RUN_AS}" cscli decisions add --ip "${ip}" --duration "${BAN_DURATION}" --reason "manual via add-on" >/dev/null 2>&1 \
                && echo "[INFO] ban aplicado: ${ip} (${BAN_DURATION})" || echo "[WARN] ban falhou: ${ip}" >&2
        done
    ) &
fi

# O entrypoint oficial faz o setup como root (hub, registro do bouncer, banco) e
# termina com `exec crowdsec $ARGS`. Roda uma copia em que so esse ultimo passo
# muda: os arquivos passam a ser do usuario crowdsec e o processo sobe com ele.
# Os cscli de ban/unban acima tambem rodam como esse usuario, para nunca criar
# arquivo do banco (sqlite WAL) com dono root.
START=/tmp/docker_start.sh
awk -v u="${RUN_AS}" '
    $0 == "exec crowdsec $ARGS" {
        print "chown -R " u ":" u " /data/crowdsec-data /etc/crowdsec"
        print "exec su-exec " u " crowdsec $ARGS"
        found = 1; next
    }
    { print }
    END { if (!found) exit 1 }
' /docker_start.sh > "${START}" || {
    echo "[FATAL] nao achei 'exec crowdsec \$ARGS' no /docker_start.sh da imagem - revisar o run.sh." >&2
    exit 1
}

echo "[INFO] crowdsec vai rodar como '${RUN_AS}'"
exec /bin/bash "${START}"

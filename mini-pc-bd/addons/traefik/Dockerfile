ARG BUILD_FROM

# O binario do traefik e estatico (Go), entao copiar da imagem oficial para a
# base do HA funciona e evita ter que manter um download/checksum aqui.
FROM traefik:v3.7 AS upstream

# Plugin do bouncer embutido na imagem (localPlugins) em vez de baixado no boot:
# assim o traefik nunca depende do github para subir. Se o download falhasse num
# religamento pos-queda de energia, o proxy inteiro nao subiria.
FROM ${BUILD_FROM} AS plugin
ARG PLUGIN_VERSION=v1.7.1
ARG PLUGIN_PATH=/plugins-local/src/github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
RUN apk add --no-cache curl tar \
    && mkdir -p "${PLUGIN_PATH}" \
    && curl -fsSL "https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin/archive/refs/tags/${PLUGIN_VERSION}.tar.gz" -o /tmp/p.tgz \
    && tar -xzf /tmp/p.tgz -C /tmp \
    && cp -a /tmp/crowdsec-bouncer-traefik-plugin-*/. "${PLUGIN_PATH}/" \
    && rm -rf /tmp/p.tgz /tmp/crowdsec-bouncer-traefik-plugin-*

FROM ${BUILD_FROM}
# O run.sh prepara arquivos como root e entrega o processo ao usuario traefik.
RUN apk add --no-cache su-exec \
    && addgroup -S -g 10010 traefik \
    && adduser -S -D -H -u 10010 -G traefik -s /sbin/nologin traefik
COPY --from=upstream /usr/local/bin/traefik /usr/local/bin/traefik
COPY --from=plugin /plugins-local /plugins-local
COPY run.sh /run.sh
RUN chmod a+x /run.sh
# O traefik procura ./plugins-local relativo ao working dir.
WORKDIR /
CMD [ "/run.sh" ]

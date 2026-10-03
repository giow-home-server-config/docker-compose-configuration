# traefik-forward-auth v2.3.0
#
# Nao existe imagem publicada desta versao: o Docker Hub do projeto parou em
# 2021 (build com Go 1.13.15, EOL desde 2020) e de v2.3.0 em diante o upstream
# publica apenas o binario estatico no GitHub Releases. Por isso montamos a
# imagem aqui em vez de usar thomseddon/traefik-forward-auth:latest.
#
# O add-on local_forwardauth do mini-pc-bd (que serve oauth.giow.dev) roda
# EXATAMENTE este mesmo binario/checksum. Os dois lados precisam bater: o mk1
# emite o cookie CSRF e o mini-pc-bd valida no callback, entao versoes
# diferentes quebram o login em todos os servicos.
FROM alpine:3.22

ARG TFA_VERSION=v2.3.0
ARG TFA_SHA256=539d733f1037b3ef5930880a5a1abca4081fcf72d6fabb810dc5b4a7adb81751

RUN apk add --no-cache ca-certificates \
    && apk add --no-cache --virtual .fetch curl \
    && curl -fsSL -o /usr/local/bin/traefik-forward-auth \
       "https://github.com/thomseddon/traefik-forward-auth/releases/download/${TFA_VERSION}/traefik-forward-auth_amd64" \
    && echo "${TFA_SHA256}  /usr/local/bin/traefik-forward-auth" | sha256sum -c - \
    && chmod +x /usr/local/bin/traefik-forward-auth \
    && apk del .fetch

ENTRYPOINT [ "/usr/local/bin/traefik-forward-auth" ]

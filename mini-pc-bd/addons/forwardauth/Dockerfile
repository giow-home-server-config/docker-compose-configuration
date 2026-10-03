ARG BUILD_FROM
FROM ${BUILD_FROM}

# Binario estatico (Go) baixado do GitHub Releases e verificado por sha256.
# NAO voltar a pinar por tag de imagem: o Docker Hub do projeto parou em 2021
# (build com Go 1.13.15) e a tag :2.2.0 e de 2020, sem o CSRF cookie por-nonce
# que o mk1 usa - foi exatamente isso que quebrou o callback antes.
# De v2.3.0 em diante o upstream publica so o binario no release.
# O mk1 roda este mesmo binario/checksum.
ARG TFA_VERSION=v2.3.0
ARG TFA_SHA256=539d733f1037b3ef5930880a5a1abca4081fcf72d6fabb810dc5b4a7adb81751

RUN apk add --no-cache curl \
    && curl -fsSL -o /usr/bin/traefik-forward-auth \
       "https://github.com/thomseddon/traefik-forward-auth/releases/download/${TFA_VERSION}/traefik-forward-auth_amd64" \
    && echo "${TFA_SHA256}  /usr/bin/traefik-forward-auth" | sha256sum -c - \
    && chmod +x /usr/bin/traefik-forward-auth

COPY run.sh /run.sh
RUN chmod a+x /run.sh
CMD [ "/run.sh" ]

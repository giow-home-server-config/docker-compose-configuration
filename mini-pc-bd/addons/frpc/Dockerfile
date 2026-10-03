ARG BUILD_FROM
FROM ${BUILD_FROM}

# Mesma versao do frpc que roda no Dell (mk1), para nao arriscar divergencia de
# protocolo com o frps.
ARG FRP_VERSION=0.62.0

RUN apk add --no-cache curl tar \
    && curl -fsSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz" -o /tmp/frp.tgz \
    && tar -xzf /tmp/frp.tgz -C /tmp \
    && mv "/tmp/frp_${FRP_VERSION}_linux_amd64/frpc" /usr/bin/frpc \
    && chmod +x /usr/bin/frpc \
    && rm -rf /tmp/frp.tgz "/tmp/frp_${FRP_VERSION}_linux_amd64"

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]

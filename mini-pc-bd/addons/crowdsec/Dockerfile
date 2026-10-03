# Usa a imagem oficial direto como base: o entrypoint dela ja cuida de sincronizar
# /etc/crowdsec a partir do /staging e de instalar as collections.
FROM crowdsecurity/crowdsec:v1.7.8
# jq nao vem na imagem e o run.sh precisa dele para ler /data/options.json.
RUN apk add --no-cache jq || (apt-get update && apt-get install -y --no-install-recommends jq && rm -rf /var/lib/apt/lists/*)
COPY run.sh /run.sh
RUN chmod a+x /run.sh
# A imagem base define ENTRYPOINT ["/bin/bash","/docker_start.sh"]; sem sobrescrever
# aqui, um CMD viraria apenas argumento dele e o run.sh nunca executaria.
ENTRYPOINT [ "/bin/bash", "/run.sh" ]
CMD []

# Usa a imagem oficial direto como base: o entrypoint dela ja cuida de sincronizar
# /etc/crowdsec a partir do /staging e de instalar as collections.
FROM crowdsecurity/crowdsec:v1.7.8
# jq nao vem na imagem e o run.sh precisa dele para ler /data/options.json.
# su-exec + usuario crowdsec: o setup roda como root e o processo final nao.
RUN apk add --no-cache jq su-exec \
    && addgroup -S -g 10013 crowdsec \
    && adduser -S -D -H -u 10013 -G crowdsec -s /sbin/nologin crowdsec \
    # O docker_start.sh cria /var/lib/crowdsec/data/* como symlinks para estes
    # arquivos (root, 600). O chown do run.sh so troca o dono do link; aqui, no
    # build, troca o do alvo sem copiar os ~74 MB de GeoIP a cada start.
    && chown -R crowdsec:crowdsec /staging/var/lib/crowdsec/data
COPY run.sh /run.sh
RUN chmod a+x /run.sh
# A imagem base define ENTRYPOINT ["/bin/bash","/docker_start.sh"]; sem sobrescrever
# aqui, um CMD viraria apenas argumento dele e o run.sh nunca executaria.
ENTRYPOINT [ "/bin/bash", "/run.sh" ]
CMD []

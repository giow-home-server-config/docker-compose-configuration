## Home Setup YAML files
This repository contains the docker-compose.yml files used in my home setup.

## To run a single container with reverse proxy:
```bash
docker-compose -p home-server \
--env-file .env \
-f reverse-proxy.yml \
-f container.yml
up -d
```

## To run the compose files inside this folder
To run all the containers use the following:
```bash
docker-compose --compatibility -p home-server \
--env-file .env \
-f reverse-proxy.yml \
-f companions.yml \
-f resume-curriculo.yml \
-f vpn.yml \
-f plex.yml \
-f calibre-web.yml \
-f files.yml \
-f portainer.yml \
-f blog.yml \
-f jmusicbot.yml \
up -d
```

## To run the compose files from any folder
```bash
docker-compose --compatibility -p home-server \
--env-file ~/docker/docker-compose-files/.env \
-f ~/docker/docker-compose-files/reverse-proxy.yml \
-f ~/docker/docker-compose-files/companions.yml \
-f ~/docker/docker-compose-files/resume-curriculo.yml \
-f ~/docker/docker-compose-files/vpn.yml \
-f ~/docker/docker-compose-files/plex.yml \
-f ~/docker/docker-compose-files/calibre-web.yml \
-f ~/docker/docker-compose-files/files.yml \
-f ~/docker/docker-compose-files/portainer.yml \
-f ~/docker/docker-compose-files/blog.yml \
-f ~/docker/docker-compose-files/jmusicbot.yml \
up -d
```

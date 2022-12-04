## Home Setup YAML files
This repository contains the docker-compose.yml files used in my home setup.

## Setup explanation
This setup has been largely influenced by the following guide: https://www.smarthomebeginner.com/traefik-2-docker-tutorial/

### Reverse proxy: Traefik 2
Reverse proxy is done using Traefik 2. Its configuration is quite challenging, but once it you get
it working it is as simple as put flags into containers.

### Traefik 2 middlewares: OAuth2 with Google
To enhance security for some services traefik only routes the connection after a secure authentication
has been made with OAuth. I use Google OAuth container for that

### Cloudflare
Clouflare secures the connection by blocking connection from unwanted agents, hiding my IP with their proxy, while still providing cache for the hosted services.

## Files explained
The `plex.yml` runs the following services:
 - Sonarr, Radarr, Rtorrent, Ombi and Plex

The `blog.yml`:
 - Ghost, Ghost-DB(mysql), Commento(comment service), Commento-DB(Postgres)

The `reverse-proxy.yml`:
 - Traefik 2, Google OAuth

The `files.yml`:
 - Syncthing, Samba server

The `companions.yml`:
 - Duckdns(for DDNS), Cloudflare-CF(Automatic CNAME DNS Creation), ouroboros (updates containers)

The `vpn.yml`:
 - Wireguard (VPN), Pihole (filter ads)

The other files manage single services:
 - Portainer - Docker GUI management
 - Resume - Static website
 - Jmusicbot - Discord bot
 - Calibre-web - To read books

The optional are services that are not usually executed but are good to have:
 - Bazarr
 - Calibre (RDP)
 - CF-DNS
 - Jellyfin
 - Lidarr
 - Tdarr
 - One-Drive

## To run a single container with reverse proxy:
```bash
docker compose -p home-server \
--env-file .env \
-f reverse-proxy.yml \
-f container.yml \
up -d
```

## To run the compose files inside this folder
To run all the containers use the following:
```bash
docker compose --compatibility -p home-server \
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
docker compose --compatibility -p home-server \
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

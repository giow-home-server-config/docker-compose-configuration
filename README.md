# Homelab giow.dev — configurações

Configuração versionada das duas máquinas de casa. A documentação de verdade está em [`docs/`](docs/):

- **[docs/INFRA.md](docs/INFRA.md)** — como as máquinas, o tráfego público (Cloudflare → frp → Traefik) e o login
  Google se encaixam. Também traz o hardware, o princípio de alocação, o plano em andamento e o histórico.
- **[docs/CATALOGO.md](docs/CATALOGO.md)** — inventário de containers, scripts e serviços, com consumo e onde cada um
  deve ficar.

## Estrutura

```
.
├── *.yml, optional/, forwardauth/   mk1 (Dell T320): Docker Compose, projeto "home-server"
├── mini-pc-bd/                      mini-pc-bd (HAOS): add-ons locais e regras do Traefik
├── docs/                            INFRA.md, CATALOGO.md
├── env.example                      variáveis do .env do mk1 (só os nomes)
└── .pre-commit-config.yaml          inclui gitleaks: barra segredos no commit
```

## mk1 — Docker Compose

Os arquivos da raiz formam **um único projeto** (`home-server`). Rode sempre com o mesmo nome de projeto e todos os
arquivos; senão o Compose cria containers duplicados.

| Arquivo | Serviços |
|---|---|
| `reverse-proxy.yml` | traefik, socket-proxy, oauth (traefik-forward-auth v2.3.0, build em `forwardauth/`) |
| `companions.yml` | crowdsec, cf-companion, duckdns, watchtower |
| `plex.yml` | plex, sonarr, radarr, qbittorrent (VPN), seerr, tautulli, unpackerr, maintainerr, arr-mcp |
| `bazarr.yml` | bazarr |
| `files.yml` | samba |
| `vpn.yml` | wireguard |
| `optional/searcharr.yml` | searcharr |
| `portainer.yml`, `jmusicbot.yml`, `kavita.yml` | nenhum ativo (tudo comentado) |
| `optional/*.yml` | serviços desligados, guardados para referência |

```bash
cd ~/docker/docker-compose-files
docker compose -p home-server $(for f in reverse-proxy companions vpn plex files portainer jmusicbot bazarr kavita optional/searcharr; do printf -- '-f %s.yml ' $f; done) up -d --no-deps <serviço>
```

Variáveis: copie `env.example` para `.env` e preencha. O `.env` nunca vai para o Git.

O setup do Traefik com Docker labels começou pelo guia
[smarthomebeginner — Traefik 2 Docker tutorial](https://www.smarthomebeginner.com/traefik-2-docker-tutorial/).

## mini-pc-bd — add-ons do Home Assistant OS

Ver [`mini-pc-bd/README.md`](mini-pc-bd/README.md). Resumo: este repositório fica clonado em `/addons/homelab` no
mini-pc-bd, e o HA encontra os add-ons em `mini-pc-bd/addons/*`. Edite e commite **no mk1**; depois
`mini-pc-bd/deploy.sh <add-on>` publica no GitHub, envia para o mini-pc-bd e reconstrói o add-on.

> ⚠️ O HA trata **qualquer arquivo `config.yaml`/`config.json`** deste repositório como add-on. Não crie arquivos com
> esses nomes fora de `mini-pc-bd/addons/`.

## Segredos

- Nunca no Git. No mk1 ficam no `.env`; no mini-pc-bd, nas opções de cada add-on.
- O pre-commit roda o **gitleaks** (via Docker) em todo commit. Para ativar num clone novo:
  `pip install pre-commit && pre-commit install`. No mk1: `venv/bin/pre-commit install`.

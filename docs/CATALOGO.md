# Catálogo de serviços — o que roda onde, quanto pesa, o que compensa mover

> Levantado em 2026-10-03. Complementa o [INFRA.md](INFRA.md), onde estão o hardware e o princípio de alocação.
> Os números são **médias desde que cada container subiu**, então escondem os picos. Use como ordem de
> grandeza, não como pico.

## Como ler

- **CPU méd.**: uso médio em % de **1 núcleo**. O mk1 tem 4 núcleos, então 100% de 1 núcleo = 25% da máquina.
  Vem do cgroup de cada container (`cpu.stat` ÷ tempo de vida).
- **RAM**: memória do cgroup. No qBittorrent inclui cache de disco; o processo em si usa ~70 MB.
- **IO**: bytes lidos + escritos desde o start. `sdf` é o disco do sistema (configs). `sda` a `sde` são os discos de mídia.
- **Veredito**: 🟢 fica no mk1 · 🔵 vai para o mini-pc-bd · ⚪ indiferente (fica onde está) · 🔴 remover/consertar.

## Panorama

| | mk1 (Xeon E5-2403 v2, 8 GB) | mini-pc-bd (N150, 8 GB) |
|---|---|---|
| CPU ocupada desde o boot | 7,0% (iowait 5,8%) | 21,2% (iowait 0,5%) — quase tudo é o Frigate |
| RAM | 4,7 GB disponíveis, **1,3 GB de swap em uso** | ~4,1 GB disponíveis |
| Gargalo real | **Disco** (iowait de 40–70% nos picos, visto em 30/09) e RAM. A CPU sofre com legenda queimada e decode de anime 10-bit no Plex. | RAM: o Frigate usa 2 GB |

## A regra de decisão

Para cada serviço, três perguntas, nesta ordem:
1. **Precisa dos discos ou da GPU?** → fica no mk1. Disco pela rede está fora de cogitação.
2. **Precisa estar de pé com o mk1 desligado?** → mini-pc-bd. É o caso da borda e do acesso remoto.
3. **Pesa e não depende de disco?** → mini-pc-bd (Jackett, FlareSolverr).

Se nenhuma se aplica, mover não traz ganho, só gasta RAM do mini-pc-bd.

## Containers do mk1

| Serviço | O que faz | Pastas que acessa | Fala com | CPU méd. | RAM | IO | Veredito |
|---|---|---|---|---:|---:|---:|---|
| **plex** | Servidor de mídia, transcode na GTX 1050 Ti | Todos os discos de mídia, `/dev/shm` (transcode) | — | 9,0% | 474 MB | 3,8 TB | 🟢 discos + GPU |
| **qbittorrent** | Torrents, com VPN AirVPN (WireGuard) dentro do container | Todos os discos de mídia + Downloads | trackers | 5,6% | 2,6 GB* | 185 GB em 2,6 dias | 🟢 discos |
| **sonarr** | Séries/anime | Todos os discos (15 root folders) | qBittorrent, Jackett (mini-pc-bd) | 1,8% | 553 MB | 961 GB | 🟢 importa arquivos |
| **radarr** | Filmes | Todos os discos (10 root folders) | qBittorrent, Jackett (mini-pc-bd) | 1,1% | 395 MB | 175 GB | 🟢 importa arquivos |
| **bazarr** | Legendas, com **sincronização por áudio ligada** (ffsubsync, pesado nos picos) | Todos os discos (grava a legenda ao lado do vídeo) | Sonarr, Radarr | 1,2% | 234 MB | 32 GB | 🟢 discos |
| **unpackerr** | Descompacta downloads | Discos + Downloads | Sonarr, Radarr | 0,01% | 18 MB | 2 GB | 🟢 discos |
| **samba** | Compartilhamento de rede | Todos os discos | — | 0,0% | 30 MB | 1 GB | 🟢 discos |
| **tautulli** | Estatísticas/histórico do Plex | Só config | Plex (API) | 0,6% | 90 MB | 1 GB | ⚪/🔵 ver "Decisões em aberto" |
| **seerr** (`pedidos`) | Pedidos de filmes/séries | Só config | Plex, Sonarr, Radarr | 0,35% | 189 MB | 1 GB | ⚪ sem o mk1 não serve para nada |
| **maintainerr** | Limpeza de biblioteca por regras | Monta os discos (provavelmente sem necessidade) | Plex, Seerr, Tautulli, *arr | 0,45% | 339 MB | 1 GB | ⚪ depende de tudo do mk1 |
| **media-cleaner** | Seu script: tira downloads stalled da fila (a cada 1h, 3 strikes) | Nenhuma | Sonarr, Radarr (API) | ~0% | 13 MB | — | ⚪ só faz sentido com o mk1 de pé |
| **traefik** | Proxy reverso (borda) | Rules, acme, log | tudo | 0,18% | 136 MB | 22 GB (log) | 🔵 borda |
| **oauth** | Login Google (forward-auth v2.3.0) | — | Google | 0,0% | 12 MB | — | 🔵 borda (o do mini-pc-bd já existe) |
| **crowdsec** | IPS, lê o log do Traefik | Log do Traefik | Traefik (bouncer) | 0,37% | 104 MB | 38 GB | 🔵 borda (já existe lá) |
| **socket-proxy** | Docker API filtrada para o Traefik | `docker.sock` | só o Traefik | 0,01% | 10 MB | — | 🔴 sai junto com o Traefik |
| **cf-companion** | Cria um CNAME no Cloudflare para cada label do Traefik | `docker.sock` | Cloudflare | 0,06% | 20 MB | — | 🔴 redundante: já existe o `*.giow.dev` |
| **wireguard** | VPN para entrar em casa (:51820/udp). 3 peers, **1 ativo** (handshake recente) | config | — | 0,02% | 21 MB | 2 GB | 🔵? ver "Decisões em aberto" |
| **duckdns** | DNS dinâmico | config | DuckDNS | 0,03% | 17 MB | — | 🔴 **falhando** ("KO" em toda atualização) |
| **searcharr** | Bot do Telegram para pedir no Sonarr/Radarr | config | Sonarr/Radarr em `192.168.0.100`, **rede que não existe** | 0,05% | 31 MB | — | 🔴 **quebrado** (logs vazios desde abril) |
| **watchtower** | Atualiza imagens `:latest` | `docker.sock` | registries | 0,26% | 17 MB | — | 🟢 gerencia o Docker do mk1 |
| jackett, flaresolverr | — | — | — | — | — | — | 🔴 parados, já migrados. Apagar depois de uns dias. |
| media-cleaner-old | Versão antiga do media-cleaner | — | — | — | — | — | 🔴 parado, apagar (`docker rm media-cleaner-old && docker rmi media-cleaner:old`) |

\* inclui cache de disco.

## Scripts e agendamentos (mk1)

| O quê | Como roda | Faz | Acessa | Veredito |
|---|---|---|---|---|
| `scripts/download_debloater` | **cron do root**, 00:00 e 12:00 | Remove torrents/arquivos fora da biblioteca, com tempo de seed por tracker (corrigido em 30/09) | qBittorrent (API) + `/mnt/*` (hardlinks) | 🟢 precisa dos discos |
| `scripts/sonarr_script-master` | **cron do root**, a cada 6h | Busca season packs e empurra para o Sonarr (backoff desde 30/09) | API do Sonarr | ⚪ só API, mas depende do Sonarr |
| `scripts/sonarr-radarr-queue-cleaner` | container `media-cleaner` | ver tabela acima | — | ⚪ |
| `scripts/cookie_updater` | nada (inativo) | Login no Jackett via Selenium | Jackett **antigo** (192.168.1.88:9003) | 🔴 obsoleto |
| `scripts/clue_login.py` | manual | Teste de API (03/10) | — | não é serviço |
| `traefik2/rotate-access-log.sh` | cron do usuário, :17 | Rotaciona o access log do Traefik | log | sai junto com o Traefik |
| logcheck | `/etc/cron.d`, de hora em hora | Varre logs e manda e-mail local | logs | ⚪ verificar se alguém lê |

O crontab do root não pode ser lido sem senha; os horários vêm da análise de 30/09 (log do sistema).
Para conferir: `sudo crontab -l`.

## Serviços do sistema (mk1)

| Serviço | CPU méd. | Veredito |
|---|---:|---|
| `frpc` | 0,03% | 🔵 sai no fim da migração da borda |
| `frps.service` | desativado | 🔴 sobra de quando o mk1 era servidor frp, remover |
| `tailscaled` | 0,11% | 🟢 manter (acesso de emergência) |
| `fail2ban` | 0,04% | 🟢 manter (SSH) |
| `nvidia-persistenced` | ~0% | 🟢 GPU do Plex |
| `cpu-performance` | — | Força o governor `performance` no Xeon. Deixa o transcode mais rápido, mas gasta energia parado. Avaliar. |
| `dsm_sa_*` (Dell OpenManage) | ~0% | Sem o iDRAC e sem `omreport` instalado, provavelmente inútil. Verificar antes de remover. |
| `vmtoolsd`, `iscsi`, `multipath` | — | Sobras (VMware tools num servidor físico). Podem sair. |

## O que já está no mini-pc-bd (e a folga)

| Add-on | CPU | RAM |
|---|---:|---:|
| Frigate | 18,7% | 2.026 MB |
| Home Assistant core | 0,4% | 564 MB |
| Jackett NAS | 0,8% | 172 MB |
| Changedetection.io | 0,2% | 133 MB |
| FlareSolverr | 0% (picos com Chromium ao resolver Cloudflare) | 58 MB |
| Traefik, CrowdSec, frpc, forward-auth | ~0,1% | 95 MB juntos |
| VS Code, Tailscale, SSH, Z2M, File editor | ~0% | ~200 MB juntos |

Sobram **~4 GB de RAM**. A borda inteira do mk1 (Traefik + CrowdSec) cabe com folga; o limite de lá é RAM, não CPU.

## Decisões em aberto

1. **Tautulli → mini-pc-bd?** Não precisa de disco (só a API do Plex), pesa pouco (~90 MB), e lá ficaria de pé
   com o mk1 desligado. Isso daria **aviso quando o Plex/mk1 cair** e o histórico acessível. Contra: perde o
   leitor de logs do Plex (precisa da pasta de logs) e gasta ~100 MB no mini-pc-bd.
   Alternativa sem migrar nada: um sensor *Ping* no HA para o mk1 com notificação.
2. **WireGuard → mini-pc-bd ou substituir pelo Tailscale?** É o acesso remoto à rede de casa e hoje morre junto com
   o mk1. Pelo princípio 2, deveria ficar no mini-pc-bd (existe add-on oficial de WireGuard). Antes, verificar
   quem são os 3 peers e se o endpoint deles usa o hostname do DuckDNS, que está falhando.
3. **DuckDNS:** remover, ou consertar se o WireGuard depender dele.
4. **Searcharr:** consertar (URL `192.168.1.88:9001`/`9002`) ou remover, se ninguém usa o bot.
5. **Seerr** fica no mk1 por enquanto: sem o Sonarr/Radarr, a página de pedidos sozinha não resolve nada.

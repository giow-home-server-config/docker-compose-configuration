# Infraestrutura do homelab (giow.dev)

> Última revisão: 2026-10-03. Documento mantido à mão; antes de mexer em algo, confira o estado real
> (`docker ps`, `ha apps`, logs do Traefik). Nenhum segredo fica aqui — só os nomes das variáveis.
>
> **Repositório:** [giow-home-server-config/docker-compose-configuration](https://github.com/giow-home-server-config/docker-compose-configuration)
> (privado). No mk1 o clone fica em `~/docker/docker-compose-files`, e `~/docker/INFRA.md` é um atalho para
> `docs/INFRA.md`. **Commits e pushes saem do mk1**, que também envia para o clone do mini-pc-bd
> (`/addons/homelab`) com `mini-pc-bd/deploy.sh`. O mini-pc-bd não tem credencial do GitHub.

## Visão geral

São duas máquinas na mesma LAN (`192.168.1.0/24`), mais um VPS que recebe o tráfego público.

| Máquina | Apelido | LAN | Tailscale | O que é |
|---|---|---|---|---|
| `giovanni-server-01` | **mk1** (Giowbox MK-1) | 192.168.1.88 | 100.119.215.67 | Ubuntu + Docker Compose. Mídia, Traefik principal. |
| `mini-pc-bd` | hostname `homeassistant` | 192.168.1.232 | 100.116.35.103 | Home Assistant OS. Tudo roda como add-on. |
| VPS | — | — | — | `164.152.53.41`, roda o **frps** (servidor do túnel frp). |

Os subdomínios `*-bh.giow.dev` (authentik `auth-bh`, tandoor, homarr, chat…) ficam num **terceiro servidor**,
que não é nenhum dos dois acima.

## Hardware e papel de cada máquina

### mk1 — Dell PowerEdge T320
- **CPU:** Xeon E5-2403 v2 (4 núcleos / 4 threads, 1.8 GHz, sem turbo, de 2013). Fraco para transcodificar por software.
- **RAM:** 8 GB. **GPU:** GTX 1050 Ti 4 GB, adaptada no servidor e usada pelo Plex (NVENC/NVDEC).
- **Discos:** 4× 4 TB SATA (`/mnt/hdd-sata-1..4`, cerca de 80% cheios), 1 TB USB (`/mnt/hdd-usb-1`) e 1 TB WD.
  Tem muitas baias e espaço: é a máquina de **armazenamento**.
- ⚠️ **Tomou um raio e perdeu o iDRAC**, o chip que controla ventoinhas, gerenciamento remoto etc.
  **Para ligar, só manualmente, no botão.** Por isso evite reiniciar ou desligar o mk1. Se ele cair, só volta
  com alguém em casa.

### mini-pc-bd — GMKtec NucBox G3 Plus
- **CPU:** Intel N150 (4 núcleos). **RAM:** 8 GB (cerca de 4 GB livres com Frigate + HA). **Disco:** NVMe 458 GB.
- Liga muito rápido, volta sozinho depois de queda de energia, e o HAOS é estável.
- Reinicia cerca de 2 vezes por mês (atualizações do HAOS), mas volta em poucos minutos sem intervenção.

### Princípio de alocação (decidido em 2026-10-03)
1. **O mini-pc-bd nunca pode depender do mk1.** Antes, o HA dependia do mk1 estar ligado, e isso era péssimo.
   A dependência só pode apontar do mk1 para o mini-pc-bd.
2. **No mini-pc-bd fica o que precisa de rapidez e resiliência:** HA, Frigate, Zigbee e a **borda inteira**
   (frp, Traefik, login OAuth, CrowdSec). Também ficam ali os serviços com pico de CPU que não precisam dos
   discos (Jackett, FlareSolverr).
3. **No mk1 fica o que precisa dos discos ou da GPU:** Plex, qBittorrent, Sonarr/Radarr/Bazarr/Unpackerr
   (importam arquivos), Samba. Também ficam os serviços que só servem com esses de pé (Seerr, Tautulli,
   Maintainerr, Searcharr): mudar esses de máquina não traz resiliência nenhuma.

### Onde a CPU do mk1 realmente vai (dados do Tautulli, 90 dias até 2026-10-03)
- 1.082 reproduções: 651 direct play; 424 com transcodificação.
- **Vídeo é quase todo na GPU:** 218 transcodificações com decode e encode na GPU, e só 1 inteiramente em software.
- **28 reproduções com decode em CPU** (encode na GPU). Provavelmente formatos que a 1050 Ti não decodifica:
  H.264 10-bit, comum em anime, e AV1. Isso pesa no Xeon.
- **116 com legenda queimada** (16 em ASS/SSA). A renderização e a sobreposição da legenda rodam na CPU,
  mesmo com o vídeo na GPU.
- 165 transcodificações só de áudio (vídeo copiado). São leves.
- Traefik, oauth e CrowdSec somados ficam abaixo de 0,1% de CPU. Tirar a borda do mk1 é por **resiliência**,
  não por CPU. Os picos de CPU que dava para tirar do mk1 eram o Jackett e o FlareSolverr (o Chromium),
  já migrados.

## Como o tráfego público chega

```
navegador ──► Cloudflare (DNS proxied: todo *.giow.dev é CNAME → giow.dev)
                 │
                 ▼
            VPS 164.152.53.41 (frps, vhost HTTPS por SNI)
                 │
     ┌───────────┴──────────────────────────────┐
     │ domínio exato registrado pelo            │ qualquer outro *.giow.dev
     │ frpc do mini-pc-bd:                      │ (frpc do mk1, customDomains = *.giow.dev)
     │ casa / frigate / oauth .giow.dev         │
     ▼                                          ▼
 Traefik do mini-pc-bd (:443)              Traefik do mk1 (:443)
```

- O frps dá prioridade ao domínio exato sobre o wildcard. Por isso `casa`, `frigate` e `oauth` vão direto para
  o mini-pc-bd e nunca aparecem no access log do mk1. Isso foi confirmado pelos logs em 2026-10-03.
- **Reserva automática:** se o frpc do mini-pc-bd desconectar (reboot, add-on reiniciando), o frps tira os
  domínios exatos dele e o tráfego cai no wildcard do **mk1**. Se o mk1 tiver rota para o domínio, ele atende.
  Confirmado nos logs: `casa.giow.dev` foi atendido pelo `hass.toml` do mk1 em 2026-08-25 (deu 502 porque o HA
  também estava reiniciando) e em 2026-09-10 (200). Essa reserva só existe enquanto o mk1 anunciar `*.giow.dev`.
- Para mover um domínio público para o mini-pc-bd, é preciso **adicioná-lo nos dois lugares de lá**:
  em `custom_domains` do add-on frpc e em `routes` do add-on Traefik.

> Inventário completo de containers, scripts e serviços, com consumo e veredito de onde cada um deve ficar:
> **[CATALOGO.md](CATALOGO.md)**.

## Autenticação (Google OAuth / traefik-forward-auth)

- O `AUTH_HOST` de tudo é **`oauth.giow.dev`**, servido pelo **mini-pc-bd** (add-on `local_forwardauth`).
  Isso é intencional: a ideia é o mini-pc-bd cuidar do auth e do Traefik.
- Existem **duas instâncias**, uma em cada máquina, e as duas precisam ter o mesmo `SECRET`, o mesmo
  `CLIENT_ID/SECRET`, `COOKIE_DOMAIN=giow.dev` e a mesma whitelist de e-mails. Se uma divergir, o login
  quebra com "Not authorized".
- As duas usam o **v2.3.0** (Go 1.22), baixado do GitHub Releases e conferido por sha256:
  - mk1: `docker-compose-files/forwardauth/Dockerfile` (o serviço `oauth` em `reverse-proxy.yml` usa `build:`
    e tem `com.centurylinklabs.watchtower.enable=false`)
  - mini-pc-bd: `/addons/forwardauth/Dockerfile`
- Não use a imagem `thomseddon/traefik-forward-auth` do Docker Hub: ela parou em 2021, e foi isso que quebrou o
  login em 2026-09-11. Ideia para o futuro: migrar para oauth2-proxy.
- Middlewares do mk1 (`traefik2/rules/middlewares-chain.toml`): `chain-oauth` (com login) e `chain-no-auth`.

---

## mk1 — giovanni-server-01

**Compose:** um único projeto `home-server`, que junta vários arquivos em `~/docker/docker-compose-files/`:
`reverse-proxy.yml companions.yml vpn.yml plex.yml files.yml portainer.yml jmusicbot.yml bazarr.yml kavita.yml optional/searcharr.yml`.
Variáveis ficam em `docker-compose-files/.env`.

Para aplicar mudanças sempre com o mesmo nome de projeto e todos os arquivos (senão o compose cria duplicatas):

```bash
cd ~/docker/docker-compose-files
docker compose -p home-server $(for f in reverse-proxy companions vpn plex files portainer jmusicbot bazarr kavita optional/searcharr; do printf -- '-f %s.yml ' $f; done) up -d --no-deps <serviço>
```

| Grupo | Containers | Observações |
|---|---|---|
| Borda | `traefik` (v3.7, :80/:443, dashboard :9007), `oauth`, `crowdsec`, `cf-companion`, `socket-proxy`, `duckdns` | Config do Traefik em `~/docker/traefik2/` (`rules/` = file provider, `acme/`, `traefik.log` = access log JSON, rotacionado pelo cron das :17). |
| Túnel | `frpc` (systemd, `/etc/frp/frpc.toml`) | `customDomains = ["*.giow.dev"]` → 127.0.0.1:443 |
| Mídia | `plex`, `sonarr` (:9001), `radarr` (:9002), `bazarr`, `qbittorrent` (com VPN, :9012), `seerr` (`pedidos.giow.dev`), `tautulli`, `maintainerr`, `unpackerr`, `searcharr`, `media-cleaner` | Rede docker `t2_proxy` = 192.168.90.0/24 |
| Outros | `wireguard` (:51820/udp), `samba` (:445), `watchtower` | Watchtower atualiza tudo, exceto o que tiver o label de desativação. |
| Sistema | tailscale, fail2ban, ssh | |

**Rotas em arquivo** (`~/docker/traefik2/rules/`):
- `jackett.toml` → Jackett no mini-pc-bd (ver abaixo)
- `hass.toml` → **reserva**: só recebe tráfego quando o frpc do mini-pc-bd está fora (ver "Reserva automática").
- `frigate.toml` → quebrado: aponta para `192.168.1.89`, que não existe mais. Como reserva, deveria apontar para
  uma porta exposta do Frigate no mini-pc-bd. Hoje o Frigate só é acessível de dentro da rede do HA.

## mini-pc-bd — Home Assistant OS

**Acesso:** `ssh root@192.168.1.232` (add-on Advanced SSH; a chave do mk1 está em `authorized_keys`).
O add-on está em *protection mode*, então `docker` não funciona por SSH; use o CLI `ha apps …`.
Web UI: <https://casa.giow.dev>.

| Add-on | Slug | O que faz |
|---|---|---|
| Traefik | `local_traefik` | Proxy de `casa`/`frigate`/`oauth`. As rotas ficam nas **opções do add-on** (`routes`: domain, backend, auth). Só suporta "com login" ou "sem login". |
| frpc | `local_frpc` | `custom_domains`: casa, frigate, oauth `.giow.dev` → localhost:443 |
| Traefik Forward Auth | `local_forwardauth` | `oauth.giow.dev`, porta 4181 |
| CrowdSec | `local_crowdsec` | Bouncer do Traefik de lá |
| Frigate | `ccab4aaf_frigate` | NVR. Rota `frigate.giow.dev` → `172.30.33.1:5000` |
| Jackett NAS | `db21ed7f_jackett_nas` | **:9117**. Config em `/config/addons_config/Jackett/` |
| FlareSolverr | `db21ed7f_flaresolverr` | **:8191**. Dentro da rede do HA: `http://db21ed7f-flaresolverr:8191` |
| Zigbee2MQTT, Changedetection.io (:5000), Studio Code Server, File editor, Tailscale, Advanced SSH | | |
| Vaultwarden | `a0d7b954_bitwarden` | ⚠️ em estado `error` |

O código dos add-ons locais (`local_*`) fica em `/addons/<nome>/` (`Dockerfile`, `config.yaml`, `run.sh`).
Depois de editar: `ha apps rebuild local_<nome>`.

Hardware: 8 GB de RAM (o Frigate usa cerca de 2,6 GB) e 458 GB de disco.

---

## Jackett + FlareSolverr (migrados para o mini-pc-bd em 2026-10-03)

- **Sonarr** (7 indexadores) e **Radarr** (5) apontam para `http://192.168.1.232:9117/api/v2.0/indexers/<id>/results/torznab/`.
- O Jackett usa o FlareSolverr do próprio mini-pc-bd (`http://db21ed7f-flaresolverr:8191`).
- A config veio inteira do mk1 (`ServerConfig.json`, `Indexers/`, `DataProtection/`), então a API key e a senha
  admin são as mesmas de antes (`JACKETT_API_KEY` no `.env` do mk1).
- `jackett.giow.dev` continua entrando pelo **Traefik do mk1** (`rules/jackett.toml`), que repassa para
  192.168.1.232:9117 com login Google.
- ⚠️ **Pendente:** a rota que libera a API por chave (`jackett-rtr-bypass`, usada pelo app do celular) ainda
  não foi recriada. Antes ela era um label do container e lia `$JACKETT_API_KEY` do `.env`.
- Teste rápido de cada indexador:
  ```bash
  curl -s "http://192.168.1.232:9117/api/v2.0/indexers/<id>/results/torznab/api?apikey=$JACKETT_API_KEY&t=search&q=" | grep -c '<item>'
  ```

**Rollback** (se precisar voltar para o mk1):
1. Descomentar `jackett` e `flaresolverr` em `docker-compose-files/plex.yml`
   (backup: `plex.yml.bak-claude-20261003-*`).
2. `docker update --restart=unless-stopped jackett flaresolverr && docker start flaresolverr jackett`
3. Apagar `traefik2/rules/jackett.toml`.
4. Voltar as URLs dos indexadores no Sonarr/Radarr para `http://192.168.90.89:9117`.
5. Backup da config antiga do Jackett do mini-pc-bd: `/config/addons_config/Jackett.bak-claude-20261003-161958.tgz`.

Os containers `jackett` e `flaresolverr` do mk1 estão **parados, sem restart, mas não removidos**.
Podem ser apagados (`docker rm jackett flaresolverr`) depois de alguns dias sem problemas, junto com
`~/docker/jackett/`.

## Por que existem dois Traefiks — e o plano

Não é failover. A borda começou a migrar do mk1 para o mini-pc-bd em 2026-08-10/11 (princípio 2 acima),
mas só `casa`, `frigate` e `oauth` foram. Enquanto a migração não terminar:
- **Não há paridade.** O add-on só aceita domínio, backend e "com/sem login". Faltam o bypass por API key
  (usado em sonarr, radarr, bazarr, torrent, tautulli e jackett), os middlewares de headers e de rate limit etc.
  Há dois CrowdSec independentes e dois forward-auth que precisam ficar sincronizados.
- **Se o mini-pc-bd reiniciar, ninguém consegue *entrar* nos serviços do mk1**, porque o login vai para
  `oauth.giow.dev`. Sessões já abertas continuam valendo.

Failover ativo-ativo (os dois frpc num `loadBalancer.group` do frp) foi avaliado e descartado. Os serviços
moram numa máquina só cada um, então o segundo Traefik não teria para onde mandar o tráfego. Os pontos únicos
de falha reais (VPS, internet, energia) são compartilhados, e seria preciso manter paridade total o tempo todo.

**Plano: borda única no mini-pc-bd** (status: proposto)
1. Ampliar o add-on `local_traefik` para ler um diretório de regras (file provider em `/share/traefik/rules`)
   e receber segredos (API keys) pelas opções do add-on. Assim ele fica com os mesmos recursos do Traefik do mk1.
2. Recriar lá os middlewares do mk1 e as rotas dos serviços do mk1, apontando para `192.168.1.88:<porta>`
   (todos já publicam porta no host: 9001, 9002, 9011, 9012, 9015, 9019, 9020, 32400).
3. Virar **um domínio por vez**, colocando o domínio em `custom_domains` do frpc do mini-pc-bd. O domínio
   exato vence o wildcard do mk1. Para desfazer, basta tirar o domínio da lista.
4. Estado final, **em aberto**:
   - (a) o frpc do mini-pc-bd assume `*.giow.dev`, e no mk1 saem frpc, traefik, oauth, crowdsec, cf-companion e
     socket-proxy; ou
   - (b) **primário + reserva**: o mini-pc-bd anuncia a lista explícita de domínios e o mk1 continua anunciando
     `*.giow.dev` com o Traefik dele só para os próprios serviços. Se a borda do mini-pc-bd cair, os serviços do
     mk1 continuam acessíveis pela "Reserva automática". Em operação normal, o Traefik do mk1 não recebe tráfego.

## Problemas conhecidos

- **Indexadores que já estavam quebrados antes da migração:** AmigosShare (login falha; está no Sonarr e no Radarr),
  MyAnonamouse (sessão expirada), animez, therarbg, thegeeks. **AnimeTorrents** está no Sonarr, mas não existe
  no Jackett. O Nyaa do Sonarr tem aviso de seed ratio = 0.
- O Jackett NAS roda como root (`PUID/PGID = 0` nas opções do add-on).
- `~/scripts/cookie_updater/main.py` ainda aponta para o Jackett antigo (`192.168.1.88:9003`). O script não está no cron.
- Os `*-bh.giow.dev` batem no Traefik do mk1 e recebem 404 (cerca de 4.800 requisições desde 14/09).
  Provavelmente falta registrar esses domínios no frpc do servidor deles.
- **A chave de API atual do Radarr está no histórico do Git** (`optional/others.yml`, commit `f2bb08b` de 2022).
  O repositório é privado, mas vale trocar a chave. Ao trocar, atualize: `.env` (`RADARR_API_KEY`), Seerr, Bazarr,
  Maintainerr, Searcharr, media-cleaner (`scripts/sonarr-radarr-queue-cleaner/.env`), os scripts e o app do celular.
- `arr-mcp` está definido no `plex.yml`, mas não existe container dele.

## Histórico

| Data | Mudança |
|---|---|
| 2026-09-11 | Login "Not authorized" em todo o OAuth: o forward-auth do mini-pc-bd era de 2020 e incompatível com o do mk1. As duas instâncias foram para o v2.3.0. Watchtower desativado para o `oauth`. |
| 2026-10-03 | Jackett e FlareSolverr migrados do mk1 para os add-ons do mini-pc-bd (atualizados para 0.24.2756 / 3.5.2). Rota `jackett.giow.dev` refeita como file rule. Chave SSH do mk1 autorizada no mini-pc-bd. Este documento criado. |

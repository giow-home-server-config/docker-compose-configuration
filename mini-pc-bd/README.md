# mini-pc-bd — add-ons locais do Home Assistant OS

GMKtec NucBox G3 Plus (Intel N150), `192.168.1.232`. Contexto e papel desta máquina: [../docs/INFRA.md](../docs/INFRA.md).

## Como este diretório chega ao HA

- O repositório inteiro fica clonado em **`/addons/homelab`**. O Supervisor procura add-ons em qualquer
  profundidade de `/addons` e encontra `mini-pc-bd/addons/<nome>/config.yaml`.
- O slug é o campo `slug` do `config.yaml`, com prefixo `local_` (ex.: `local_traefik`). Mudar a pasta de lugar não
  muda o slug; as opções e os dados do add-on são mantidos.
- Para publicar no GitHub, use a **deploy key** `/config/.ssh/homelab_deploy`, que tem escrita só neste repositório.
  O clone já vem configurado (`core.sshCommand`).

## Fluxo de mudança

```bash
ssh root@192.168.1.232
cd /addons/homelab
git pull                                  # pegar mudanças feitas em outro lugar
# ...editar mini-pc-bd/addons/<nome>/...
ha store reload                           # só se mudou config.yaml (versão, opções, schema)
ha apps rebuild local_<nome>              # reconstrói a imagem e reinicia
git add -A && git commit -m "..." && git push
```

O SSH roda no add-on Advanced SSH em *protection mode*, então `docker` não funciona; use o `ha apps …`.

## Add-ons

| Pasta | Slug | Função |
|---|---|---|
| `addons/traefik` | `local_traefik` | Proxy reverso da borda (Let's Encrypt via DNS-01 Cloudflare) |
| `addons/frpc` | `local_frpc` | Cliente frp: anuncia os domínios no VPS e entrega no Traefik local |
| `addons/forwardauth` | `local_forwardauth` | Login Google (`oauth.giow.dev`), v2.3.0 conferido por checksum |
| `addons/crowdsec` | `local_crowdsec` | IPS que lê o access log do Traefik e alimenta o bouncer |

Segredos (token do Cloudflare, chave da LAPI do CrowdSec, credenciais OAuth, token do frp, API keys) ficam **nas
opções do add-on**, nunca nos arquivos deste diretório.

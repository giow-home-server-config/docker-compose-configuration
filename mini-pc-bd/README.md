# mini-pc-bd — add-ons locais do Home Assistant OS

GMKtec NucBox G3 Plus (Intel N150), `192.168.1.232`. Contexto e papel desta máquina: [../docs/INFRA.md](../docs/INFRA.md).

## Como este diretório chega ao HA

- O repositório inteiro fica clonado em **`/addons/homelab`**. O Supervisor procura add-ons em qualquer
  profundidade de `/addons` e encontra `mini-pc-bd/addons/<nome>/config.yaml`.
- O slug é o campo `slug` do `config.yaml`, com prefixo `local_` (ex.: `local_traefik`). Mudar a pasta de lugar não
  muda o slug; as opções e os dados do add-on são mantidos.
- **O mini-pc-bd não tem acesso ao GitHub.** Quem commita e publica é o **mk1** (`~/docker/docker-compose-files`),
  onde roda o pre-commit com gitleaks. O mk1 envia o commit para o clone do mini-pc-bd por SSH (remote
  `mini-pc-bd`). Lá está configurado `receive.denyCurrentBranch=updateInstead`, então o push atualiza os arquivos.

## Fluxo de mudança (no mk1)

```bash
cd ~/docker/docker-compose-files
# ...editar mini-pc-bd/addons/<nome>/...
git add -A && git commit -m "..."         # pre-commit + gitleaks rodam aqui
mini-pc-bd/deploy.sh <nome> [<nome>...]   # push GitHub + push mini-pc-bd + store reload + rebuild/update
```

**Emergência com o mk1 desligado:** edite direto em `/addons/homelab` no mini-pc-bd, faça
`ha apps rebuild local_<nome>` e **commit lá**. Quando o mk1 voltar, puxe para ele e publique:
`git pull mini-pc-bd main && git push origin main`. Enquanto houver mudança não commitada no mini-pc-bd, o push do mk1
é recusado, o que evita sobrescrever o conserto.

O SSH roda no add-on Advanced SSH em *protection mode*, então `docker` não funciona; use o `ha apps …`.

## Add-ons

| Pasta | Slug | Função |
|---|---|---|
| `addons/traefik` | `local_traefik` | Proxy reverso da borda, `:8443` (Let's Encrypt via DNS-01 Cloudflare). Regras em [`traefik/rules/`](traefik/README.md) |
| `addons/frpc` | `local_frpc` | Cliente frp: anuncia os domínios no VPS e entrega em `127.0.0.1:8443` |
| `addons/forwardauth` | `local_forwardauth` | Login Google (`oauth.giow.dev`), v2.3.0 conferido por checksum |
| `addons/crowdsec` | `local_crowdsec` | IPS que lê o access log do Traefik e alimenta o bouncer |

Os quatro rodam **sem root**: o `run.sh` prepara os arquivos como root e entrega o processo a um usuário próprio
(`su-exec`): traefik 10010, frpc 10011, forwardauth 10012, crowdsec 10013.

Segredos (token do Cloudflare, chave da LAPI do CrowdSec, credenciais OAuth, token do frp, API keys) ficam **nas
opções do add-on**, nunca nos arquivos deste diretório.

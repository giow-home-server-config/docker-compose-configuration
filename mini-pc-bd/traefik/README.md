# Regras do Traefik do mini-pc-bd

O add-on `local_traefik` lê **direto** `rules/` deste repositório (`/addons/homelab/mini-pc-bd/traefik/rules`,
montado só para leitura) e recarrega sozinho quando os arquivos mudam. Para publicar uma rota nova não é preciso
rebuild:

```bash
# no mk1
git commit -am "..." && mini-pc-bd/deploy.sh      # sem nome de add-on: só envia os arquivos
```

| Arquivo | Conteúdo |
|---|---|
| `rules/middlewares.yml` | `ratelimit`, `crowdsec`, `oauth`, `secure-headers` e as cadeias (`chain-ha`, `chain-ha-oauth`, `chain-no-auth`, `chain-oauth`) |
| `rules/mini-pc-bd.yml` | serviços do próprio mini-pc-bd (casa, frigate, oauth) |

Para um domínio chegar aqui pela internet, ele também precisa estar em `custom_domains` do add-on `local_frpc`.
Domínio fora dessa lista continua no mk1 (wildcard `*.giow.dev`).

## Segredos

Nunca no arquivo. Cadastre na opção **`secrets`** do add-on (lista de `name`/`value`) e use nas regras com
`{{ env "NOME" }}`, que é o Go template do file provider do Traefik:

```yaml
crowdsecLapiKey: '{{ env "CROWDSEC_LAPI_KEY" }}'
```

Na subida, o add-on avisa no log se alguma regra usa um nome que não está em `secrets`.

**Bypass por API key:** proteja o router com `{{ if env "X" }}`. Um segredo vazio viraria `Header(..., ``)`, que
pode casar com requisições **sem** o header e liberar o acesso sem login:

```yaml
http:
  routers:
{{ if env "SONARR_API_KEY" }}
    sonarr-bypass:
      rule: 'Host(`sonarr.giow.dev`) && (Header(`X-Api-Key`, `{{ env "SONARR_API_KEY" }}`) || Query(`apikey`, `{{ env "SONARR_API_KEY" }}`))'
      ...
{{ end }}
```

## Usuário e porta

O Traefik roda como `traefik` (uid 10010), sem root, na porta **8443** (`listen_port`). O frpc entrega em
`127.0.0.1:8443` (`local_port` do `local_frpc`).

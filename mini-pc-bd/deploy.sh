#!/usr/bin/env bash
# Publica no mini-pc-bd o que está commitado e reconstrói os add-ons indicados.
# Roda no mk1, a partir do clone do repositório.
#
#   mini-pc-bd/deploy.sh                 # só sincroniza os arquivos
#   mini-pc-bd/deploy.sh traefik frpc    # sincroniza e reconstrói local_traefik e local_frpc
#
# O clone do mini-pc-bd (/addons/homelab) aceita push com receive.denyCurrentBranch=updateInstead:
# o push atualiza os arquivos lá e é recusado se houver mudança não commitada no mini-pc-bd.
set -euo pipefail

HOST=root@192.168.1.232
cd "$(git rev-parse --show-toplevel)"

if [ -n "$(git status --porcelain -- mini-pc-bd)" ]; then
  echo "Há mudanças não commitadas em mini-pc-bd/. Faça o commit antes de publicar." >&2
  exit 1
fi

git push origin main
git push mini-pc-bd main
ssh "$HOST" 'ha store reload >/dev/null'

for addon in "$@"; do
  slug="local_${addon}"
  # Versão nova no config.yaml vira "update"; sem mudança de versão, "rebuild".
  if ssh "$HOST" "ha apps info ${slug} --raw-json" | grep -qE '"update_available": ?true'; then
    echo "==> ha apps update ${slug}"
    ssh "$HOST" "ha apps update ${slug}"
  else
    echo "==> ha apps rebuild ${slug}"
    ssh "$HOST" "ha apps rebuild ${slug}"
  fi
  ssh "$HOST" "ha apps info ${slug}" | grep -E '^(state|version):'
done

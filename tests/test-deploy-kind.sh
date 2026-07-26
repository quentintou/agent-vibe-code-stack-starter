#!/usr/bin/env bash
# Vérifie la bifurcation de deploy.sh entre les deux types de projet.
#
#   ./tests/test-deploy-kind.sh
#
# `deploy.sh` sert deux chemins : « app » (TanStack + Postgres + Docker) et
# « content » (Astro statique, ni base ni conteneur en service). Les erreurs
# guettées ici sont de deux natures :
#   - un `kind` inconnu qui passerait au lieu d'être refusé ;
#   - une régression du chemin « app », qui est en production.
#
# Comme pour test-injections.sh, de faux `ssh`/`rsync`/`curl` sont placés en
# tête du PATH : un test ne vaut que si l'on prouve qu'aucun appel distant n'a
# eu lieu avant le refus attendu.
set -uo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$ICI")"
ATELIER=$(mktemp -d)
trap 'rm -rf "$ATELIER"' EXIT

mkdir -p "$ATELIER/faux-bin"
for outil in ssh rsync scp curl; do
  cat > "$ATELIER/faux-bin/$outil" <<EOF
#!/bin/sh
echo "APPEL-$outil: \$*" >> "\$JOURNAL"
exit 1
EOF
  chmod +x "$ATELIER/faux-bin/$outil"
done
export PATH="$ATELIER/faux-bin:$PATH"

ECHECS=0

# prepare <dossier> <json> — installe un projet jouet prêt à déployer.
prepare() {
  local dir="$1" json="$2"
  cp "$REPO/scripts/deploy.sh" "$dir/deploy.sh"
  cp -R "$REPO/scripts" "$dir/scripts"
  printf '%s' "$json" > "$dir/deploy.config.json"
  printf 'DATABASE_URL=postgres://u:p@demo-db:5432/demo\n' > "$dir/.env.production"
  printf 'services:\n  app:\n    image: demo\n' > "$dir/docker-compose.yml"
}

# essai <description> <json> <attendu: refus|accepte>
#   « refus »   : le script doit s'arrêter AVANT tout appel distant.
#   « accepte » : la configuration est valide ; le script doit aller jusqu'au
#                 premier appel distant (que notre faux ssh fait échouer).
essai() {
  local description="$1" json="$2" attendu="$3"
  local dir; dir=$(mktemp -d)
  export JOURNAL="$dir/appels.log"; : > "$JOURNAL"
  prepare "$dir" "$json"
  local sortie code appels
  sortie=$(cd "$dir" && ./deploy.sh 2>&1); code=$?
  appels=$(wc -l < "$JOURNAL" | tr -d ' ')

  local ok=0
  if [ "$attendu" = refus ]; then
    [ "$code" -ne 0 ] && [ "$appels" -eq 0 ] && ok=1
  else
    # Configuration acceptée : la validation locale est passée, donc le script
    # a tenté de joindre le serveur.
    [ "$appels" -ge 1 ] && ok=1
  fi

  if [ "$ok" = 1 ]; then
    echo "  OK    $description"
  else
    echo "  ECHEC $description → code=$code, appels distants=$appels (attendu : $attendu)"
    printf '%s\n' "$sortie" | head -4 | sed 's/^/        /'
    ECHECS=$((ECHECS + 1))
  fi
  rm -rf "$dir"
}

APP='{"project":"demo","domain":"exemple.fr","vps":{"host":"root@192.0.2.1"},
 "app":{"dir":"/opt/apps/demo","image_name":"demo","db_container":"demo-db","app_port":"8300"},
 "health_url":"https://exemple.fr/api/health","secrets_file":".env.production"}'

CONTENU='{"kind":"content","project":"demo","domain":"exemple.fr",
 "vps":{"host":"root@192.0.2.1"},"app":{"dir":"/opt/apps/demo"},
 "health_url":"https://exemple.fr/"}'

echo "-- reconnaissance du type de projet --"
essai "kind absent → traité comme « app » (rétrocompatibilité)" "$APP" accepte
essai "kind: content accepté sans base ni image ni port" "$CONTENU" accepte
essai "kind: content accepté sans fichier de secrets" \
  "${CONTENU%\}}, \"secrets_file\":\"\"}" accepte
essai "kind inconnu refusé" \
  '{"kind":"nimportequoi","project":"demo","domain":"exemple.fr","vps":{"host":"root@192.0.2.1"},
    "app":{"dir":"/opt/apps/demo"},"health_url":"https://exemple.fr/"}' refus

echo
echo "-- le chemin « app » garde ses garde-fous --"
essai "app sans DATABASE_URL refusé" \
  "${APP/\"secrets_file\":\".env.production\"/\"secrets_file\":\".env.vide\"}" refus

# Cas particulier : DATABASE_URL pointant « db ». On réécrit le fichier de
# secrets plutôt que la configuration.
dir=$(mktemp -d); export JOURNAL="$dir/appels.log"; : > "$JOURNAL"
prepare "$dir" "$APP"
printf 'DATABASE_URL=postgres://u:p@db:5432/demo\n' > "$dir/.env.production"
sortie=$(cd "$dir" && ./deploy.sh 2>&1); code=$?
appels=$(wc -l < "$JOURNAL" | tr -d ' ')
if [ "$code" -ne 0 ] && [ "$appels" -eq 0 ] && printf '%s' "$sortie" | grep -q "alias"; then
  echo "  OK    app avec DATABASE_URL sur l'alias « db » refusé"
else
  echo "  ECHEC app avec DATABASE_URL sur l'alias « db » → code=$code, appels=$appels"
  ECHECS=$((ECHECS + 1))
fi
rm -rf "$dir"

echo
if [ "$ECHECS" -eq 0 ]; then
  echo "Resultat : les deux types sont reconnus, les fautes refusees"
  exit 0
fi
echo "Resultat : $ECHECS cas mal geres"
exit 1

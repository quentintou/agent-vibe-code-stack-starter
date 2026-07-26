#!/usr/bin/env bash
# Vérifie qu'aucune valeur malveillante n'atteint le shell distant.
#
#   ./tests/test-injections.sh
#
# `deploy.sh` et `bootstrap-vps.sh` construisent des commandes exécutées en root
# sur le serveur. Toute valeur venant de `deploy.config.json` ou de la ligne de
# commande doit être refusée AVANT le premier appel réseau.
#
# La preuve est matérielle : de faux `ssh`, `rsync`, `scp` et `curl` sont placés
# en tête du PATH et journalisent tout appel. Un test ne passe que si le script
# a échoué ET que ce journal est resté vide. Vérifier le seul code de sortie ne
# suffirait pas : un script peut échouer après avoir déjà exécuté la charge.
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

config() { # config <fichier> <cle.pointee> <valeur>
  python3 - "$@" <<'PY'
import json, sys
cfg = {
    "project": "demo",
    "domain": "exemple.fr",
    "vps": {"host": "root@192.0.2.1"},
    "app": {
        "dir": "/opt/apps/demo",
        "image_name": "demo",
        "db_container": "demo-db",
        "app_port": "8300",
    },
    "health_url": "https://exemple.fr/api/health",
    "secrets_file": ".env.production",
}
chemin, cle, valeur = sys.argv[1], sys.argv[2], sys.argv[3]
noeud, parties = cfg, cle.split(".")
for p in parties[:-1]:
    noeud = noeud[p]
noeud[parties[-1]] = valeur
with open(chemin, "w") as fh:
    json.dump(cfg, fh)
PY
}

essai_deploy() { # essai_deploy <description> <cle> <valeur>
  local description="$1" cle="$2" valeur="$3"
  local dir; dir=$(mktemp -d)
  export JOURNAL="$dir/appels.log"; : > "$JOURNAL"
  cp "$REPO/scripts/deploy.sh" "$dir/deploy.sh"
  cp -R "$REPO/scripts" "$dir/scripts"
  config "$dir/deploy.config.json" "$cle" "$valeur"
  touch "$dir/.env.production"
  local sortie code appels
  sortie=$(cd "$dir" && ./deploy.sh 2>&1); code=$?
  appels=$(wc -l < "$JOURNAL" | tr -d ' ')
  if [ "$code" -ne 0 ] && [ "$appels" -eq 0 ]; then
    echo "  OK    $description"
  else
    echo "  ECHEC $description → code=$code, appels distants=$appels"
    printf '%s\n' "$sortie" | head -3 | sed 's/^/        /'
    ECHECS=$((ECHECS + 1))
  fi
  rm -rf "$dir"
}

essai_bootstrap() { # essai_bootstrap <description> <cible-ssh>
  local description="$1" cible="$2"
  local dir; dir=$(mktemp -d)
  export JOURNAL="$dir/appels.log"; : > "$JOURNAL"
  local code appels
  "$REPO/scripts/bootstrap-vps.sh" "$cible" >/dev/null 2>&1; code=$?
  appels=$(wc -l < "$JOURNAL" | tr -d ' ')
  if [ "$code" -ne 0 ] && [ "$appels" -eq 0 ]; then
    echo "  OK    $description"
  else
    echo "  ECHEC $description → code=$code, appels distants=$appels"
    ECHECS=$((ECHECS + 1))
  fi
  rm -rf "$dir"
}

echo "-- deploy.sh : valeurs de deploy.config.json --"
essai_deploy "saut de ligne dans project (contourne un grep ligne à ligne)" "project" 'demo
;id;#'
essai_deploy "point-virgule dans project"              "project"       'demo; id; #'
essai_deploy "substitution de commande dans vps.host"  "vps.host"      'root@$(id).invalid'
essai_deploy "remontée de répertoire dans project"     "project"       '../../etc'
essai_deploy "health_url pointant vers un site tiers"  "health_url"    'https://exemple-attaquant.fr/ok'
essai_deploy "health_url en http au lieu de https"     "health_url"    'http://exemple.fr/api/health'
essai_deploy "saut de ligne dans domain"               "domain"        'exemple.fr
;curl attaquant;#'
essai_deploy "port non numérique"                      "app.app_port"  '8300; rm -rf /'

echo
echo "-- bootstrap-vps.sh : cible SSH --"
essai_bootstrap "option ssh déguisée en hôte (-oProxyCommand)" '-oProxyCommand=id'
essai_bootstrap "point-virgule dans la cible"                  'root@1.2.3.4; id'
essai_bootstrap "saut de ligne dans la cible"                  $'root@1.2.3.4\n;id;#'
essai_bootstrap "option longue déguisée en hôte"               '--rsync-path=id'

echo
if [ "$ECHECS" -eq 0 ]; then
  echo "Resultat : aucune injection n'atteint le shell distant"
  exit 0
fi
echo "Resultat : $ECHECS injection(s) passent encore"
exit 1

#!/usr/bin/env bash
# Prépare un VPS Debian/Ubuntu neuf : Docker, Caddy, réseau, arborescence.
#
# Usage:
#   ./scripts/bootstrap-vps.sh root@203.0.113.10
#
# Idempotent : peut être relancé sans risque sur un VPS déjà préparé.
# N'écrase jamais une configuration Caddy existante sans en faire une copie.
set -euo pipefail

VPS="${1:-}"
if [ -z "$VPS" ]; then
  echo "Usage: $0 user@host"
  echo "Exemple: $0 root@203.0.113.10"
  exit 1
fi

# Sans ce controle, une valeur commencant par « - » est prise par ssh pour une
# option : « -oProxyCommand=... » executerait une commande sur CETTE machine.
if ! python3 -c '
import re, sys
sys.exit(0 if re.fullmatch(r"[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+", sys.argv[1], re.DOTALL) else 1)
' "$VPS"; then
  echo "ERREUR : cible SSH invalide : « $VPS »"
  echo "  Format attendu : utilisateur@hôte"
  exit 1
fi

echo "=== Préparation de $VPS ==="

ssh -o StrictHostKeyChecking=accept-new -- "$VPS" bash -s <<'REMOTE'
set -euo pipefail

echo "--- Docker ---"
if command -v docker >/dev/null 2>&1; then
  echo "Docker déjà installé : $(docker --version)"
else
  # Dépôt officiel signé, pas `curl | sh` : ce dernier exécute en root un
  # script téléchargé sans vérification. Une compromission en amont donnerait
  # un accès root immédiat au serveur.
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian %s stable\n' \
    "$(dpkg --print-architecture)" "$(. /etc/os-release && echo "$VERSION_CODENAME")" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  echo "Docker installé (dépôt signé)."
fi

echo "--- Caddy ---"
if command -v caddy >/dev/null 2>&1; then
  echo "Caddy déjà installé : $(caddy version | head -1)"
else
  apt-get update -qq
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl gnupg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
  echo "Caddy installé."
fi

echo "--- Arborescence et réseau ---"
mkdir -p /etc/caddy/sites /opt/apps
if docker network inspect web >/dev/null 2>&1; then
  echo "Réseau 'web' déjà présent."
else
  # Sans redirection avalant l'erreur : un échec de création doit arrêter le
  # script, pas être annoncé comme « déjà présent ».
  docker network create web >/dev/null
  echo "Réseau 'web' créé."
fi

echo "--- Caddyfile central ---"
# Ce dont le starter a besoin : que le Caddyfile IMPORTE /etc/caddy/sites/.
# Rien de plus. Il peut contenir tout ce qu'il veut par ailleurs — options
# globales, autres imports, sites hérités.
#
# Exiger qu'il ne contienne QUE cette ligne bloquait toute machine hébergeant
# déjà quelque chose, en demandant de « fusionner » ce qu'il n'y avait pas à
# fusionner. Constaté sur un serveur pourtant conforme, le 2026-07-26.
ATTENDU='import /etc/caddy/sites/*.caddy'

if [ ! -f /etc/caddy/Caddyfile ]; then
  printf '%s\n' "$ATTENDU" > /etc/caddy/Caddyfile
  echo "Caddyfile créé."

elif grep -qE '^\s*import\s+/etc/caddy/sites/' /etc/caddy/Caddyfile; then
  # Cas de loin le plus courant après la première installation : rien à faire.
  echo "Caddyfile déjà configuré (import présent) — inchangé."

else
  # Pas d'import. Soit c'est le fichier d'exemple du paquet Debian, soit une
  # vraie configuration qu'il ne faut surtout pas écraser.
  #
  # Le paquet installe un bloc « :80 { } » servant /usr/share/caddy. Le prendre
  # pour de la production bloquerait toute machine neuve. Un bloc de site réel
  # commence par un nom de domaine, donc contient un point suivi d'une
  # extension ; « :80 { » n'en a pas.
  if grep -vE '^\s*#' /etc/caddy/Caddyfile \
     | grep -qE '^\s*[a-z0-9*][a-z0-9.*-]*\.[a-z]{2,}[^{]*\{'; then
    SAUVE="/etc/caddy/Caddyfile.avant-starter.$(date +%Y%m%d-%H%M%S)"
    cp /etc/caddy/Caddyfile "$SAUVE"
    echo
    echo "ARRÊT : /etc/caddy/Caddyfile contient des sites, et n'importe pas"
    echo "        /etc/caddy/sites/."
    echo
    echo "  Écraser ce fichier mettrait hors ligne les sites déjà hébergés ici."
    echo "  Sauvegarde : $SAUVE"
    echo
    echo "  Ajoutez cette ligne à la fin de /etc/caddy/Caddyfile :"
    echo
    echo "      $ATTENDU"
    echo
    echo "  Vos sites existants ne bougent pas. Relancez ensuite ce script."
    exit 1
  fi
  # Fichier d'exemple du paquet : on le remplace.
  printf '%s\n' "$ATTENDU" > /etc/caddy/Caddyfile
  echo "Caddyfile d'exemple remplacé par l'import."
fi

# Un dossier sites/ vide ferait échouer l'import : on garantit au moins un fichier.
if [ -z "$(ls -A /etc/caddy/sites 2>/dev/null)" ]; then
  printf '# Les fragments de sites arrivent ici, un fichier par projet.\n' \
    > /etc/caddy/sites/00-placeholder.caddy
fi

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl reload caddy 2>/dev/null || systemctl restart caddy
systemctl is-active --quiet caddy && echo "Caddy actif."

echo
echo "=== VPS prêt ==="
echo "  Docker  : $(docker --version)"
echo "  Caddy   : $(caddy version | head -1)"
echo "  Réseau  : web"
echo "  Dossiers: /opt/apps, /etc/caddy/sites"
REMOTE

echo
echo "Vérification depuis votre machine :"
echo "  ssh $VPS 'docker ps && caddy version'"

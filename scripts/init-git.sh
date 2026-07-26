#!/usr/bin/env bash
# Met le projet sous git et le pousse sur GitHub, en depot PRIVE.
#
#   ./scripts/init-git.sh <nom-du-depot>
#
# L'ordre des operations est le point important : le garde-fou anti-secrets
# tourne AVANT la creation du depot distant. Un secret pousse sur GitHub, meme
# supprime dans le commit suivant, reste dans l'historique et doit etre
# considere comme compromis — il faut alors le faire tourner, pas le cacher.
set -euo pipefail

NOM="${1:-}"
if [ -z "$NOM" ]; then
  echo "Usage : ./scripts/init-git.sh <nom-du-depot>"
  echo "Exemple : ./scripts/init-git.sh mon-tableau-de-bord"
  exit 1
fi

# Meme principe que deploy.sh : ce nom finit dans une commande. `re.fullmatch`
# et non `grep -E "^...$"`, qui teste ligne par ligne et laisserait passer une
# valeur contenant un saut de ligne.
if ! python3 -c '
import re, sys
sys.exit(0 if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}", sys.argv[1], re.DOTALL) else 1)
' "$NOM"; then
  echo "ERREUR : nom de dépôt invalide : « $NOM »"
  echo "  Lettres, chiffres, point, tiret et souligné uniquement."
  exit 1
fi

ICI="$(cd "$(dirname "$0")" && pwd)"

command -v git >/dev/null || { echo "ERREUR : git absent."; exit 1; }
command -v gh  >/dev/null || {
  echo "ERREUR : la commande gh est absente."
  echo "  Installer GitHub CLI : https://cli.github.com — puis « gh auth login »."
  exit 1
}

# L'agent ne peut pas s'authentifier a la place de l'utilisateur : cela demande
# un navigateur et un compte. On s'arrete et on explique.
if ! gh auth status >/dev/null 2>&1; then
  echo "ERREUR : gh n'est pas authentifié."
  echo
  echo "  Lancez vous-même, dans votre terminal :"
  echo "      gh auth login"
  echo
  echo "  Puis relancez cette commande."
  exit 1
fi

# --- .gitignore -------------------------------------------------------------
# On n'ecrase pas un .gitignore existant : on complete ce qui manque. Ecraser
# ferait disparaitre des exclusions propres au projet.
IGNORES=(".env" ".env.*" "!.env.example" "node_modules/" "dist/" ".output/"
         ".astro/" "*.log" ".DS_Store" "deploy.config.json")
touch .gitignore
AJOUTS=0
for motif in "${IGNORES[@]}"; do
  if ! grep -qxF "$motif" .gitignore; then
    printf '%s\n' "$motif" >> .gitignore
    AJOUTS=$((AJOUTS + 1))
  fi
done
[ "$AJOUTS" -gt 0 ] && echo "-- .gitignore : $AJOUTS motif(s) ajouté(s)."

# --- Dépôt local ------------------------------------------------------------
if [ -d .git ]; then
  echo "-- Dépôt git déjà initialisé."
else
  git init -q
  git symbolic-ref HEAD refs/heads/main
  echo "-- Dépôt git initialisé (branche main)."
fi

if git remote get-url origin >/dev/null 2>&1; then
  echo "ERREUR : ce dépôt a déjà un remote « origin » :"
  echo "    $(git remote get-url origin)"
  echo "  Rien n'a été modifié. Pousser à la main si c'est voulu."
  exit 1
fi

# --- Hook anti-secrets ------------------------------------------------------
if [ -x "$ICI/install-hooks.sh" ]; then
  "$ICI/install-hooks.sh" || true
fi

# --- Garde-fou, AVANT toute publication -------------------------------------
echo "-- Recherche de secrets..."
if ! python3 "$ICI/check-secrets.py" .; then
  echo
  echo "ARRÊT : aucun dépôt n'a été créé, rien n'a été poussé."
  echo
  echo "  Retirez les valeurs signalées, puis relancez."
  echo "  Si l'une d'elles a DÉJÀ été poussée quelque part, considérez-la"
  echo "  comme compromise : révoquez-la et générez-en une nouvelle."
  exit 1
fi

# --- Premier commit ---------------------------------------------------------
git add -A
if git diff --cached --quiet; then
  echo "-- Rien à committer."
else
  git commit -q -m "Premier commit"
  echo "-- Premier commit créé."
fi

# --- Dépôt distant ----------------------------------------------------------
# --private par defaut, sans option pour faire autrement depuis ce script :
# rendre public est une decision qui se prend en conscience, sur github.com.
echo "-- Création du dépôt privé « $NOM » sur GitHub..."
gh repo create "$NOM" --private --source=. --remote=origin --push

echo
echo "=== Terminé ==="
echo "  Dépôt : $(gh repo view --json url -q .url 2>/dev/null || echo "$NOM")"
echo "  Il est PRIVÉ. Pour le rendre public plus tard, passez par github.com"
echo "  après avoir relu l'historique : un secret déjà commité y reste."

#!/usr/bin/env bash
# Crée un compte utilisateur sur une application déployée.
#
#   ./create-user.sh <email> "<nom>"
#
# Le mot de passe est demandé de façon interactive : le passer en argument le
# rendrait visible dans `ps` et le conserverait dans l'historique du shell.
#
# L'opération se déroule dans un conteneur JETABLE. Le service en ligne n'est
# jamais modifié et continue de refuser toute inscription pendant ce temps —
# ouvrir l'inscription publique, même quelques secondes, suffirait à ce qu'un
# robot de scan crée un compte.
set -euo pipefail

EMAIL="${1:-}"
NAME="${2:-}"

if [ -z "$EMAIL" ] || [ -z "$NAME" ]; then
  echo "Usage : ./create-user.sh <email> \"<nom>\""
  echo "Le mot de passe sera demandé ; il ne se passe pas en argument."
  exit 1
fi

CFG="${DEPLOY_CONFIG:-deploy.config.json}"
[ -f "$CFG" ] || { echo "ERREUR : $CFG introuvable. Lancer depuis la racine du projet."; exit 1; }

cfg() {
  python3 -c '
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for key in sys.argv[2].split("."):
    data = data[key]
print(data)
' "$CFG" "$1"
}

PROJECT=$(cfg project)
VPS=$(cfg vps.host)
DOMAIN=$(cfg domain)

# Mêmes contrôles que deploy.sh. Sans eux, une valeur du fichier de
# configuration s'exécute en root sur le serveur : `"x; curl … | bash; #"`.
valide() { # valide <nom> <valeur> <motif> <explication>
  if ! printf '%s' "$2" | grep -qE "^$3$"; then
    echo "ERREUR : $1 invalide dans $CFG : « $2 »"
    echo "  $4"
    exit 1
  fi
}
valide "project"  "$PROJECT" '[a-z0-9][a-z0-9-]{0,38}'         "minuscules, chiffres et tirets uniquement"
valide "vps.host" "$VPS"     '[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+' "utilisateur@hôte"
valide "domain"   "$DOMAIN"  '[a-z0-9][a-z0-9.-]{2,252}[a-z]'  "un nom de domaine"

# Le répertoire est déduit du projet, jamais lu depuis la configuration : c'est
# ce qui empêche une valeur arbitraire d'atteindre le shell distant.
APP_DIR="/opt/apps/$PROJECT"

if ! printf '%s' "$EMAIL" | grep -qE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
  echo "ERREUR : adresse e-mail invalide."
  exit 1
fi

printf 'Mot de passe (8 caractères minimum, saisie masquée) : '
read -rs PASSWORD
echo
if [ "${#PASSWORD}" -lt 8 ]; then
  echo "ERREUR : le mot de passe doit faire au moins 8 caractères."
  exit 1
fi

echo "-- Création du compte dans un conteneur jetable..."

# `docker compose run --rm` démarre un conteneur temporaire à partir de la même
# image, avec sa propre variable d'environnement. Le conteneur en service reste
# inchangé, et le mot de passe transite par l'entrée standard.
if printf '%s' "$PASSWORD" | ssh "$VPS" \
     "cd $(printf '%q' "$APP_DIR") && \
      NEW_USER_EMAIL=$(printf '%q' "$EMAIL") \
      NEW_USER_NAME=$(printf '%q' "$NAME") \
      docker compose run --rm -T \
        -e ALLOW_PUBLIC_SIGNUP=true \
        -e NEW_USER_EMAIL -e NEW_USER_NAME \
        app node create-user.mjs"; then
  echo
  echo "Compte créé : $EMAIL"
else
  echo
  echo "ÉCHEC de la création du compte."
  echo "  Vérifier que le déploiement est à jour : ./deploy.sh"
  exit 1
fi

# Contrôle final : le service en ligne doit toujours refuser les inscriptions.
# Adresse ALEATOIRE : une adresse fixe pourrait exister en base, et better-auth
# repondrait 422 « deja pris » — ce qui serait pris a tort pour un refus.
# On exige en outre le message exact emis par le hook, pas seulement un code.
CONTROLE="controle-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')@exemple.invalid"
REPONSE_CTRL=$(curl -sS -X POST "https://$DOMAIN/api/auth/sign-up/email" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$CONTROLE\",\"name\":\"Controle\",\"password\":\"motdepasse12345\"}" 2>/dev/null)
CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "https://$DOMAIN/api/auth/sign-up/email" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$CONTROLE\",\"name\":\"Controle\",\"password\":\"motdepasse12345\"}" 2>/dev/null)

case "$CODE" in
  400|403)
    if printf '%s' "$REPONSE_CTRL" | grep -q "inscription est fermée"; then
      echo "Inscription publique toujours fermée (HTTP $CODE + message du hook, vérifié)."
    else
      echo "ALERTE : refus HTTP $CODE mais message inattendu — vérifier la configuration."
      exit 1
    fi
    ;;
  *)
    echo "ALERTE : l'inscription publique répond $CODE — elle semble ouverte."
    echo "  Vérifier ALLOW_PUBLIC_SIGNUP dans $APP_DIR/.env sur le serveur."
    exit 1
    ;;
esac

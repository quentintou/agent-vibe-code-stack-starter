#!/usr/bin/env bash
# Vérifie l'envoi de courrier : configuration, garde-fous, et absence de dérive
# entre le module de l'application et l'outil de test.
#
#   ./tests/test-mail.sh
#
# Deux implémentations parlent au même service : `src/lib/mail.ts`, utilisé par
# l'application, et `tester-email.mjs`, l'outil qui prouve que l'envoi marche.
# Si les deux divergent, l'outil validerait une configuration que l'application
# n'utilise pas — un test qui ment est pire que pas de test. Les premiers
# contrôles ci-dessous existent uniquement pour empêcher cette dérive.
#
# Aucun message n'est envoyé ici : ces tests tournent hors ligne. La preuve que
# l'envoi fonctionne se fait avec `node tester-email.mjs` sur le serveur, contre
# le vrai service — voir docs/08-workers-et-emails.md.
set -uo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$ICI")"
APP="$REPO/templates/app"
MODULE="$APP/src/lib/mail.ts"
OUTIL="$APP/tester-email.mjs"

ECHECS=0

verifie() {
  local intitule="$1" attendu="$2" obtenu="$3"
  if [ "$attendu" = "$obtenu" ]; then
    printf '  ok   %s\n' "$intitule"
  else
    printf '  ÉCHEC %s\n       attendu : %s\n       obtenu  : %s\n' \
      "$intitule" "$attendu" "$obtenu"
    ECHECS=$((ECHECS + 1))
  fi
}

echo "== Les deux implémentations sont d'accord =="

url_module=$(grep -oE "https://api\.cloudflare\.com[^']+" "$MODULE" | head -1)
url_outil=$(grep -oE "https://api\.cloudflare\.com[^']+" "$OUTIL" | head -1)
verifie "même adresse d'API" "$url_module" "$url_outil"

# Une adresse vide des deux côtés serait « d'accord » sans rien prouver.
case "$url_module" in
  https://api.cloudflare.com/client/v4/accounts/*/email/sending/send)
    printf "  ok   l'adresse d'API est celle d'Email Sending\n" ;;
  *)
    printf "  ÉCHEC adresse d'API inattendue : « %s »\n" "$url_module"
    ECHECS=$((ECHECS + 1)) ;;
esac

for variable in CF_EMAIL_ACCOUNT_ID CF_EMAIL_API_TOKEN MAIL_FROM MAIL_FROM_NAME; do
  m=$(grep -c "$variable" "$MODULE"); o=$(grep -c "$variable" "$OUTIL")
  if [ "$m" -ge 1 ] && [ "$o" -ge 1 ]; then
    printf '  ok   %s présente des deux côtés\n' "$variable"
  else
    printf '  ÉCHEC %s absente (module:%s outil:%s)\n' "$variable" "$m" "$o"
    ECHECS=$((ECHECS + 1))
  fi
done

echo
echo "== Le .env.example documente les mêmes variables =="
for variable in CF_EMAIL_ACCOUNT_ID CF_EMAIL_API_TOKEN MAIL_FROM MAIL_FROM_NAME; do
  if grep -qE "^$variable=" "$APP/.env.example"; then
    printf '  ok   %s\n' "$variable"
  else
    printf '  ÉCHEC %s absente du .env.example\n' "$variable"
    ECHECS=$((ECHECS + 1))
  fi
done

echo
echo "== Configuration incomplète : échec au démarrage =="

# Le module lit l'environnement à l'import. Une configuration à moitié remplie
# doit faire échouer le démarrage, pas se découvrir au premier message.
importe() {
  env -u CF_EMAIL_ACCOUNT_ID -u CF_EMAIL_API_TOKEN -u MAIL_FROM -u MAIL_FROM_NAME \
    "$@" node --experimental-strip-types --input-type=module \
    -e "const m = await import('file://$MODULE'); console.log(m.envoiConfigure ? 'CONFIGURE' : 'INACTIF')" 2>&1
}

sortie=$(importe)
verifie "aucune variable : démarre, envoi inactif" "INACTIF" "$(printf '%s' "$sortie" | tail -1)"

sortie=$(importe CF_EMAIL_ACCOUNT_ID=abc)
if printf '%s' "$sortie" | grep -q 'incomplète'; then
  printf '  ok   une seule variable : refus au démarrage\n'
else
  printf '  ÉCHEC une seule variable aurait dû refuser. Obtenu : %s\n' "$sortie"
  ECHECS=$((ECHECS + 1))
fi

sortie=$(importe CF_EMAIL_ACCOUNT_ID=abc CF_EMAIL_API_TOKEN=CHANGE_ME)
if printf '%s' "$sortie" | grep -q 'incomplète'; then
  printf '  ok   deux variables sur trois : refus au démarrage\n'
else
  printf '  ÉCHEC deux variables auraient dû refuser. Obtenu : %s\n' "$sortie"
  ECHECS=$((ECHECS + 1))
fi

sortie=$(importe CF_EMAIL_ACCOUNT_ID=abc CF_EMAIL_API_TOKEN=CHANGE_ME MAIL_FROM=a@b.fr)
verifie "les trois variables : envoi actif" "CONFIGURE" "$(printf '%s' "$sortie" | tail -1)"

# Le cas le plus fréquent de tous : le .env.example recopié sans être rempli.
# Les trois variables existent, toutes vides. Ce n'est PAS une configuration
# incomplète, c'est l'absence de configuration — le démarrage doit passer.
# Les affectations vides sont construites plutôt qu'écrites : une ligne portant
# littéralement `CF_EMAIL_API_TOKEN=` suivie d'autre chose est lue comme un
# secret par scripts/check-secrets.py, qui a raison d'être méfiant.
vides=()
for v in CF_EMAIL_ACCOUNT_ID CF_EMAIL_API_TOKEN MAIL_FROM MAIL_FROM_NAME; do
  vides+=("$v=")
done
sortie=$(importe "${vides[@]}")
verifie "les trois vides (.env non rempli) : démarre, envoi inactif" \
  "INACTIF" "$(printf '%s' "$sortie" | tail -1)"

# En revanche une seule valeur vide au milieu de deux remplies est bien une
# configuration à moitié faite : sans ce refus, l'application enverrait sans
# expéditeur et Cloudflare rejetterait chaque message, en production.
sortie=$(importe CF_EMAIL_ACCOUNT_ID=abc CF_EMAIL_API_TOKEN=CHANGE_ME MAIL_FROM=)
if printf '%s' "$sortie" | grep -q 'incomplète'; then
  printf '  ok   expéditeur vide parmi deux valeurs : refus au démarrage\n'
else
  printf "  ÉCHEC un expéditeur vide aurait dû refuser. Obtenu : %s\n" "$sortie"
  ECHECS=$((ECHECS + 1))
fi

echo
echo "== L'envoi ne lève jamais d'exception =="

# Une exception qui remonte d'un envoi raté transforme l'authentification en
# oracle d'énumération : adresse inconnue -> 200, adresse connue dont l'envoi
# échoue -> 500. On force un échec réseau et on exige un retour, pas un plantage.
sortie=$(env -u CF_EMAIL_ACCOUNT_ID -u CF_EMAIL_API_TOKEN -u MAIL_FROM \
  CF_EMAIL_ACCOUNT_ID=compte-inexistant \
  CF_EMAIL_API_TOKEN=CHANGE_ME \
  MAIL_FROM=test@exemple.invalid \
  node --experimental-strip-types --input-type=module -e "
    const m = await import('file://$MODULE')
    const r = await m.envoyerMail({ to: 'a@b.fr', subject: 's', text: 't' })
    console.log('RETOUR', r.ok)
  " 2>&1)
if printf '%s' "$sortie" | grep -q 'RETOUR false'; then
  printf "  ok   un échec retourne { ok: false } sans lever\n"
else
  printf '  ÉCHEC exception ou retour inattendu : %s\n' "$(printf '%s' "$sortie" | tail -3)"
  ECHECS=$((ECHECS + 1))
fi

echo
echo "== L'outil de test refuse d'agir sans destinataire =="

sortie=$(cd "$APP" && node tester-email.mjs 2>&1); code=$?
verifie "sans argument : code de sortie 1" "1" "$code"
if printf '%s' "$sortie" | grep -q 'Usage'; then
  printf "  ok   sans argument : affiche l'usage\n"
else
  printf '  ÉCHEC message d'"'"'usage absent : %s\n' "$sortie"
  ECHECS=$((ECHECS + 1))
fi

sortie=$(cd "$APP" && node tester-email.mjs pas-une-adresse 2>&1); code=$?
verifie "adresse invalide : code de sortie 1" "1" "$code"

sortie=$(cd "$APP" && env -u CF_EMAIL_ACCOUNT_ID -u CF_EMAIL_API_TOKEN -u MAIL_FROM \
  node tester-email.mjs quelquun@exemple.fr 2>&1); code=$?
verifie "sans configuration : code de sortie 1" "1" "$code"
if printf '%s' "$sortie" | grep -q 'CF_EMAIL_ACCOUNT_ID'; then
  printf '  ok   sans configuration : nomme les variables manquantes\n'
else
  printf '  ÉCHEC les variables manquantes ne sont pas nommées : %s\n' "$sortie"
  ECHECS=$((ECHECS + 1))
fi

echo
echo "== Le jeton ne fuit pas dans les journaux =="

# `console.error(err)` sur une erreur de fetch peut embarquer l'en-tête
# d'autorisation. On exige qu'aucun des deux fichiers ne journalise le jeton.
for fichier in "$MODULE" "$OUTIL"; do
  nom=$(basename "$fichier")
  if grep -nE 'console\.(log|info|error|warn).*(jeton|apiToken|CF_EMAIL_API_TOKEN)' "$fichier" \
     | grep -vE 'manquantes|Variables' | grep -q .; then
    printf '  ÉCHEC %s journalise le jeton\n' "$nom"
    ECHECS=$((ECHECS + 1))
  else
    printf '  ok   %s ne journalise pas le jeton\n' "$nom"
  fi
done

echo
if [ "$ECHECS" -eq 0 ]; then
  echo "test-mail : tout passe."
  exit 0
fi
echo "test-mail : $ECHECS échec(s)."
exit 1

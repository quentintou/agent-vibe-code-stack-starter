#!/usr/bin/env bash
# Vérifie que init-git.sh ne publie jamais un secret.
#
#   ./tests/test-init-git.sh
#
# Le risque : `gh repo create --push` est irréversible du point de vue d'un
# secret. Une clé poussée reste dans l'historique GitHub même après suppression,
# et doit être révoquée. Le garde-fou doit donc s'exécuter AVANT.
#
# La preuve passe par un faux `gh` place en tête du PATH : un test ne vaut que
# s'il montre qu'aucun `gh repo create` n'a été émis.
set -uo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$ICI")"
ATELIER=$(mktemp -d)
trap 'rm -rf "$ATELIER"' EXIT

mkdir -p "$ATELIER/faux-bin"
cat > "$ATELIER/faux-bin/gh" <<'EOF'
#!/bin/sh
echo "APPEL-gh: $*" >> "$JOURNAL"
exit 0
EOF
chmod +x "$ATELIER/faux-bin/gh"
export PATH="$ATELIER/faux-bin:$PATH"

ECHECS=0

# La fausse clé est ASSEMBLÉE à l'exécution, jamais écrite en entier dans ce
# fichier. Sinon le garde-fou signalerait ce test lui-même — et la réponse
# facile (l'ajouter aux chemins exemptés) affaiblirait le garde-fou pour de bon.
PREFIXE='sk-proj'
CORPS=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
CLE_FACTICE="$PREFIXE-$CORPS"

essai() { # essai <description> <fichier> <contenu> <bloque|passe>
  local description="$1" fichier="$2" contenu="$3" attendu="$4"
  local dir; dir=$(mktemp -d)
  export JOURNAL="$dir/appels.log"; : > "$JOURNAL"
  mkdir -p "$dir/scripts"
  cp "$REPO/scripts/check-secrets.py" "$REPO/scripts/init-git.sh" \
     "$REPO/scripts/install-hooks.sh" "$dir/scripts/" 2>/dev/null
  printf 'Projet de test\n' > "$dir/README.md"
  printf '%s\n' "$contenu" > "$dir/$fichier"

  local code crees versionnes ok=0
  ( cd "$dir" && bash scripts/init-git.sh depot-de-test >/dev/null 2>&1 ); code=$?
  # grep -c affiche deja « 0 » puis sort en 1 : un « || echo 0 » ajouterait
  # un SECOND zero et casserait la comparaison numerique.
  crees=$(grep -c 'repo create' "$JOURNAL" 2>/dev/null) || true
  versionnes=$(cd "$dir" && git ls-files 2>/dev/null || true)

  if [ "$attendu" = bloque ]; then
    # Aucun dépôt créé, et rien de commité.
    [ "$crees" -eq 0 ] && [ "$code" -ne 0 ] && [ -z "$versionnes" ] && ok=1
  else
    # Dépôt créé, mais le fichier sensible NE DOIT PAS être versionné.
    [ "$crees" -ge 1 ] && ! printf '%s' "$versionnes" | grep -qxF "$fichier" && ok=1
  fi

  if [ "$ok" = 1 ]; then
    echo "  OK    $description"
  else
    echo "  ECHEC $description → dépôts créés=$crees, code=$code"
    echo "        versionnés : $(printf '%s' "$versionnes" | tr '\n' ' ')"
    ECHECS=$((ECHECS + 1))
  fi
  rm -rf "$dir"
}

echo "-- publication d'un secret --"
essai "clé dans un fichier versionné → aucun dépôt créé" \
  "config.js" "const cle = \"$CLE_FACTICE\"" bloque
essai "clé dans un .env ignoré → dépôt créé, .env non versionné" \
  ".env" "OPENAI_API_KEY=$CLE_FACTICE" passe

echo
echo "-- garde-fous d'usage --"
dir=$(mktemp -d); export JOURNAL="$dir/appels.log"; : > "$JOURNAL"
mkdir -p "$dir/scripts"
cp "$REPO/scripts/check-secrets.py" "$REPO/scripts/init-git.sh" "$dir/scripts/"
sortie=$( cd "$dir" && bash scripts/init-git.sh 'nom; rm -rf /' 2>&1 ); code=$?
# grep -c affiche deja « 0 » puis sort en 1 : un « || echo 0 » ajouterait
  # un SECOND zero et casserait la comparaison numerique.
  crees=$(grep -c 'repo create' "$JOURNAL" 2>/dev/null) || true
if [ "$code" -ne 0 ] && [ "$crees" -eq 0 ]; then
  echo "  OK    nom de dépôt contenant un point-virgule refusé"
else
  echo "  ECHEC nom de dépôt malveillant accepté (code=$code, dépôts=$crees)"
  ECHECS=$((ECHECS + 1))
fi
rm -rf "$dir"

dir=$(mktemp -d); export JOURNAL="$dir/appels.log"; : > "$JOURNAL"
mkdir -p "$dir/scripts"
cp "$REPO/scripts/check-secrets.py" "$REPO/scripts/init-git.sh" "$dir/scripts/"
printf 'Projet\n' > "$dir/README.md"
( cd "$dir" && git init -q && git remote add origin https://exemple.invalid/x.git )
sortie=$( cd "$dir" && bash scripts/init-git.sh autre-nom 2>&1 ); code=$?
# grep -c affiche deja « 0 » puis sort en 1 : un « || echo 0 » ajouterait
  # un SECOND zero et casserait la comparaison numerique.
  crees=$(grep -c 'repo create' "$JOURNAL" 2>/dev/null) || true
if [ "$code" -ne 0 ] && [ "$crees" -eq 0 ]; then
  echo "  OK    dépôt ayant déjà un « origin » laissé intact"
else
  echo "  ECHEC un remote existant a été écrasé (code=$code, dépôts=$crees)"
  ECHECS=$((ECHECS + 1))
fi
rm -rf "$dir"

echo
if [ "$ECHECS" -eq 0 ]; then
  echo "Resultat : aucun secret ne peut etre publie"
  exit 0
fi
echo "Resultat : $ECHECS cas mal geres"
exit 1

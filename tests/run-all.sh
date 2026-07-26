#!/usr/bin/env bash
# Lance toutes les vérifications du dépôt.
#
#   ./tests/run-all.sh
#
# À lancer après toute modification de `scripts/` ou `infra/`. Chaque suite
# correspond à une catégorie de panne déjà constatée : secrets versionnés,
# règles d'infrastructure enfreintes, contrôles de sécurité contournables,
# valeurs de configuration atteignant le shell distant.
set -uo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$ICI")"
cd "$REPO"

ECHECS=0

suite() { # suite <titre> <commande...>
  local titre="$1"; shift
  echo
  echo "=== $titre ==="
  if "$@"; then
    return 0
  fi
  echo "    ^^^ ECHEC"
  ECHECS=$((ECHECS + 1))
}

echo "-- syntaxe des scripts shell --"
for fichier in scripts/*.sh tests/*.sh .githooks/pre-commit; do
  [ -f "$fichier" ] || continue
  if bash -n "$fichier" 2>/dev/null; then
    echo "  OK    $fichier"
  else
    echo "  ECHEC $fichier"
    bash -n "$fichier"
    ECHECS=$((ECHECS + 1))
  fi
done

suite "Aucun secret dans l'arbre ni dans l'historique" \
  python3 scripts/check-secrets.py .
suite "Le garde-fou anti-secrets attrape ce qu'il prétend attraper" \
  python3 tests/test-check-secrets.py
suite "Le compose de référence respecte les règles" \
  python3 tests/validate-compose.py
suite "Le validateur de compose rejette bien les fautes" \
  python3 tests/validate-compose.py --self-test
suite "Le compose de référence ne demande aucun privilège" \
  python3 scripts/verifier-compose.py infra/docker-compose.app.example.yml
suite "Les contournements du contrôle de compose sont bloqués" \
  python3 tests/test-verifier-compose.py
suite "Aucune injection n'atteint le shell distant" \
  ./tests/test-injections.sh
suite "Les deux types de projet sont reconnus, les fautes refusées" \
  ./tests/test-deploy-kind.sh
suite "Aucun secret ne peut être publié sur GitHub" \
  ./tests/test-init-git.sh
suite "Aucune route n'expose la base sans authentification" \
  python3 tests/test-routes-app.py
suite "L'envoi de courrier refuse une configuration à moitié faite" \
  ./tests/test-mail.sh

echo
if [ "$ECHECS" -eq 0 ]; then
  echo "======================================"
  echo " Toutes les verifications sont vertes."
  echo "======================================"
  exit 0
fi
echo "======================================"
echo " $ECHECS suite(s) en echec."
echo "======================================"
exit 1

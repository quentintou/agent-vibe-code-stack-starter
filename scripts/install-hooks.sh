#!/usr/bin/env bash
# Active le hook pre-commit qui bloque les commits contenant un secret.
# A lancer une fois apres avoir clone le depot.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "Hook pre-commit active : les commits contenant un secret seront refuses."
echo "Verification : python3 scripts/check-secrets.py ."

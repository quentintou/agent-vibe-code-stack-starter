#!/usr/bin/env python3
"""Valide infra/docker-compose.app.example.yml contre les règles du starter.

Chaque règle correspond à une panne réelle. Le validateur se teste lui-même
(`--self-test`) : un validateur qui ne rejette rien donne une fausse confiance,
ce qui est pire que pas de validateur du tout.

    python3 tests/validate-compose.py
    python3 tests/validate-compose.py --self-test
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML requis : python3 -m pip install pyyaml")

COMPOSE = Path(__file__).parent.parent / "infra" / "docker-compose.app.example.yml"
PROJET = "demo"


def render(src: str) -> str:
    out = src.replace("PROJET", PROJET).replace("APP_PORT", "8300").replace("DB_PORT", "5440")
    return re.sub(r"\$\{POSTGRES_PASSWORD[^}]*\}", "testpw", out)


def check(src: str) -> list[str]:
    """Retourne la liste des violations. Vide si tout va bien."""
    errors: list[str] = []

    try:
        doc = yaml.safe_load(render(src))
    except yaml.YAMLError as exc:
        return [f"YAML invalide : {exc}"]

    services = doc.get("services", {}) or {}
    db_key = f"{PROJET}-db"

    # 1. Aucune clé de service ne doit s'appeler "db".
    #    C'est la CLÉ qui devient l'alias DNS sur le réseau partagé, pas
    #    container_name. Contrôler container_name donne un faux négatif.
    if "db" in services:
        errors.append(
            "un service a pour clé 'db' : Compose publiera l'alias DNS 'db' sur "
            "le réseau partagé, quel que soit container_name"
        )

    # 2. Le service Postgres doit exister sous une clé propre au projet.
    if db_key not in services:
        errors.append(f"aucun service '{db_key}' : la clé doit être <projet>-db")

    # 3. Les ports ne sont publiés que sur la boucle locale.
    ports = [p for svc in services.values() for p in (svc.get("ports") or [])]
    exposed = [p for p in ports if not str(p).startswith("127.0.0.1:")]
    if exposed:
        errors.append(f"ports exposés publiquement : {exposed}")

    # 4. POSTGRES_PASSWORD doit être obligatoire (syntaxe ${VAR:?message}).
    if ":?" not in src:
        errors.append("POSTGRES_PASSWORD doit utiliser la syntaxe ${VAR:?message}")

    # 5. L'app doit attendre que la base soit saine, sur la bonne clé.
    cond = ((services.get("app", {}) or {}).get("depends_on", {}) or {}).get(db_key, {})
    if (cond or {}).get("condition") != "service_healthy":
        errors.append(f"app doit dépendre de '{db_key}' avec condition service_healthy")

    # 6. DATABASE_URL ne doit PAS être composée ici : un mot de passe contenant
    #    @ / : ou % produirait une URL invalide. Elle vient du .env, encodée.
    env = (services.get("app", {}) or {}).get("environment") or []
    if any(str(e).startswith("DATABASE_URL=") for e in env):
        errors.append(
            "DATABASE_URL est composée dans le compose : un mot de passe "
            "contenant @ / : ou % casserait l'URL. La définir dans .env"
        )

    return errors


def self_test() -> int:
    """Vérifie que le validateur rejette bien les fautes qu'il prétend attraper."""
    base = COMPOSE.read_text()
    cases = [
        ("compose de référence", base, False),
        ("service nommé db", base.replace("PROJET-db:\n", "db:\n", 1), True),
        ("port exposé publiquement", base.replace('"127.0.0.1:APP_PORT:3000"', '"8300:3000"'), True),
        ("mot de passe non obligatoire", base.replace(":?POSTGRES_PASSWORD manquant dans .env", ""), True),
        (
            "DATABASE_URL composée",
            base.replace("      - NODE_ENV=production", "      - DATABASE_URL=postgres://a:b@c/d\n      - NODE_ENV=production"),
            True,
        ),
    ]
    failures = 0
    for label, src, should_fail in cases:
        errs = check(src)
        ok = bool(errs) == should_fail
        print(f"  {'OK  ' if ok else 'ECHEC'} {label} → {len(errs)} violation(s)")
        if not ok:
            failures += 1
    print()
    print("Auto-test :", "le validateur rejette bien les fautes" if not failures else f"{failures} cas mal geres")
    return 1 if failures else 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()

    errors = check(COMPOSE.read_text())
    if errors:
        print("ECHEC :")
        for err in errors:
            print(f"  - {err}")
        return 1
    print("RESULTAT : toutes les regles respectees")
    return 0


if __name__ == "__main__":
    sys.exit(main())

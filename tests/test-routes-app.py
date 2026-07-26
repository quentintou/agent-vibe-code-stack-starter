#!/usr/bin/env python3
"""Verifie qu'aucune route du squelette n'ouvre la base sans authentification.

    python3 tests/test-routes-app.py

La CLI TanStack genere des routes d'exemple qui lisent et ecrivent une table
sans verifier la session. Elles sont faites pour etre supprimees, mais rien ne
le rappelle : elles partent en production avec le reste. Constate en ligne le
2026-07-26 — une ligne inseree en base apparaissait dans une requete sans le
moindre cookie.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

RACINE = Path(__file__).parent.parent / "templates" / "app" / "src"

# Ces chemins servent l'authentification elle-meme : exiger une session pour
# se connecter serait absurde.
EXEMPTS = {"routes/api/auth/$.ts", "routes/connexion.tsx", "lib/auth.ts"}

ACCES_BASE = re.compile(r"from ['\"]#/db['\"]|db\.(select|insert|update|delete|execute|query)\b")
CONTROLE = re.compile(r"getSession|exigeSession|requireSession")


def main() -> int:
    if not RACINE.exists():
        print(f"ECHEC : {RACINE} introuvable")
        return 1

    fautifs: list[tuple[str, str]] = []
    examines = 0

    for fichier in sorted(RACINE.rglob("*")):
        if fichier.suffix not in {".ts", ".tsx"} or not fichier.is_file():
            continue
        rel = fichier.relative_to(RACINE).as_posix()
        if rel in EXEMPTS or rel.endswith(".gen.ts"):
            continue
        texte = fichier.read_text(errors="ignore")
        if not ACCES_BASE.search(texte):
            continue
        examines += 1
        # /api/health interroge la base pour prouver qu'elle repond : c'est son
        # role, et il ne renvoie aucune donnee.
        if rel == "routes/api/health.ts":
            if "Response.json({ ok: true })" not in texte:
                fautifs.append((rel, "health ne devrait renvoyer que { ok }"))
            continue
        if not CONTROLE.search(texte):
            fautifs.append((rel, "touche la base sans verifier la session"))

    for rel, raison in fautifs:
        print(f"  ECHEC {rel} — {raison}")
    if fautifs:
        print(f"\nResultat : {len(fautifs)} fichier(s) exposent la base")
        return 1

    print(f"  OK    {examines} fichier(s) touchant la base, tous protégés")
    print("\nResultat : aucune route n'expose la base sans authentification")
    return 0


if __name__ == "__main__":
    sys.exit(main())

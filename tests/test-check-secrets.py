#!/usr/bin/env python3
"""Non-régression du garde-fou anti-secrets.

Chaque cas correspond à un défaut réellement trouvé lors d'un audit adverse.
Les valeurs sont assemblées morceau par morceau : aucune chaîne ressemblant à
un secret n'existe en clair dans ce fichier.

    python3 tests/test-check-secrets.py
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

CHECK = Path(__file__).parent.parent / "scripts" / "check-secrets.py"


def run(*args: str) -> int:
    return subprocess.run(
        [sys.executable, str(CHECK), *args], capture_output=True, text=True
    ).returncode


def main() -> int:
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)

        cases: list[tuple[str, Path | str, int]] = []

        f = d / "quote.txt"
        f.write_text('POSTGRES_PASSWORD="' + "k9Jm2Xq7Rt4Bv8Nz" + '"\n')
        cases.append(("secret entre guillemets", f, 1))

        f = d / "mix.txt"
        f.write_text("url=https://example.com cle=" + "sk-" + "9fK2mQ7vRt4xZ1nB8pL3wH6yC0s\n")
        cases.append(("ligne avec example.com ET une vraie cle", f, 1))

        f = d / "path.txt"
        f.write_text("chemin=" + "/Users" + "/dupont/Developer/x\n")
        cases.append(("chemin personnel", f, 1))

        f = d / "aws.txt"
        f.write_text("cle=" + "AKIA" + "5J7QMZ2XKPT4RNVW\n")
        cases.append(("cle AWS", f, 1))

        f = d / "subst.txt"
        f.write_text("POSTGRES_PASSWORD=${VAR:?message}\n")
        cases.append(("substitution de variable acceptee", f, 0))

        f = d / "todo.txt"
        f.write_text("BETTER_AUTH_SECRET= # a generer\n")
        cases.append(("valeur vide suivie d'un commentaire", f, 0))

        f = d / "ph.txt"
        f.write_text("POSTGRES_PASSWORD=CHANGE_ME\nBETTER_AUTH_SECRET=CHANGE_ME\n")
        cases.append(("placeholders d'un .env.example", f, 0))

        # Cas issus du contre-audit de securite du 2026-07-26.
        f = d / "sansprefixe.txt"
        f.write_text("PASSWORD=" + "hunter2xyz\n")
        cases.append(("secret sans prefixe de variable", f, 1))

        f = d / "skproj.txt"
        f.write_text("CLE=" + "sk-" + "proj-AAAABBBBCCCCDDDDEEEEFFFFGGGG\n")
        cases.append(("cle au format sk-proj-", f, 1))

        f = d / "majuscules.txt"
        f.write_text("SERVICE_API_TOKEN=" + "ABCDEF123456789\n")
        cases.append(("valeur tout en majuscules non factice", f, 1))

        f = d / "urldistante.txt"
        f.write_text("DATABASE_URL=postgres://u:" + "S3cretReel99" + "@prod.exemple.com/db\n")
        cases.append(("URL de connexion vers un hote distant", f, 1))

        f = d / "urllocale.txt"
        f.write_text("DATABASE_URL=postgres://u:motdepasse@localhost:5432/db\n")
        cases.append(("URL de connexion locale acceptee", f, 0))

        f = d / "codegrep.txt"
        f.write_text("grep -qE '^DATABASE_URL=' \"$SECRETS\"\n")
        cases.append(("fragment de code non pris pour un secret", f, 0))

        # Une interface TypeScript decrit la FORME des variables, pas leurs
        # valeurs. Sans exemption, tout `env.d.ts` est signale et le garde-fou
        # devient bruyant — donc contourne.
        f = d / "env.d.ts"
        f.write_text(
            "interface ImportMetaEnv {\n"
            "  readonly STRIPE_SECRET_KEY: string\n"
            "  readonly NEWSLETTER_API_KEY: string\n"
            "}\n"
        )
        cases.append(("declaration de type TypeScript acceptee", f, 0))

        # Mais une vraie affectation dans un .ts reste signalee.
        f = d / "vrai.ts"
        f.write_text('const STRIPE_SECRET_KEY = "sk_live_9f3ba71c04e8d25617aa"\n')
        cases.append(("affectation reelle dans un .ts signalee", f, 1))

        cases.append(("chemin inexistant signale (code 2)", d / "absent", 2))

        for label, target, expected in cases:
            got = run(str(target))
            ok = got == expected
            print(f"  {'OK   ' if ok else 'ECHEC'} {label} (code {got}, attendu {expected})")
            failures += 0 if ok else 1

    for label, args, expected in [
        ("depot propre", ["."], 0),
        ("historique propre", ["--history"], 0),
    ]:
        got = run(*args)
        ok = got == expected
        print(f"  {'OK   ' if ok else 'ECHEC'} {label} (code {got}, attendu {expected})")
        failures += 0 if ok else 1

    print()
    print(f"Resultat : {failures} echec(s)" if failures else "Resultat : tous les cas passent")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

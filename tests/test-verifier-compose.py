#!/usr/bin/env python3
"""Rejoue les contournements du contrôleur de compose trouvés en audit.

    python3 tests/test-verifier-compose.py

Une première version de `verifier-compose.py` cherchait des motifs de texte.
Un audit adverse l'a franchie de six façons : une espace avant les deux-points,
`root` au lieu de `0`, la syntaxe longue d'un montage… Chaque cas ci-dessous
correspond à un contournement réel. Ils restent ici pour que la protection ne
retombe jamais à une simple recherche de motifs.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

VERIFIEUR = Path(__file__).parent.parent / "scripts" / "verifier-compose.py"

# (description, contenu du compose, doit_etre_refuse)
CAS = [
    (
        "privileged avec une espace avant les deux-points",
        "services:\n  app:\n    image: x\n    privileged : true\n",
        True,
    ),
    (
        "privileged en écriture normale",
        "services:\n  app:\n    image: x\n    privileged: true\n",
        True,
    ),
    (
        "user: root plutôt que user: 0",
        "services:\n  app:\n    image: x\n    user: root\n",
        True,
    ),
    (
        'user: "0:0" entre guillemets',
        'services:\n  app:\n    image: x\n    user: "0:0"\n',
        True,
    ),
    (
        "montage de la racine en syntaxe longue",
        "services:\n  app:\n    image: x\n    volumes:\n"
        "      - type: bind\n        source: /\n        target: /hote\n",
        True,
    ),
    (
        "socket Docker en syntaxe courte",
        "services:\n  app:\n    image: x\n    volumes:\n"
        "      - /var/run/docker.sock:/var/run/docker.sock\n",
        True,
    ),
    (
        "capacité noyau supplémentaire",
        "services:\n  app:\n    image: x\n    cap_add:\n      - SYS_ADMIN\n",
        True,
    ),
    (
        "pile réseau de l'hôte",
        "services:\n  app:\n    image: x\n    network_mode: host\n",
        True,
    ),
    (
        "espace de processus de l'hôte",
        "services:\n  app:\n    image: x\n    pid: host\n",
        True,
    ),
    (
        "protections seccomp désactivées",
        "services:\n  app:\n    image: x\n    security_opt:\n      - seccomp:unconfined\n",
        True,
    ),
    (
        "accès direct à un disque de l'hôte",
        "services:\n  app:\n    image: x\n    devices:\n      - /dev/sda:/dev/sda\n",
        True,
    ),
    (
        "configs: file: lisant une clé SSH de l'hôte",
        "services:\n  app:\n    image: x\n    configs:\n      - source: v\n        target: /app/c\n"
        "configs:\n  v:\n    file: /root/.ssh/id_ed25519\n",
        True,
    ),
    (
        "secrets: file: lisant /etc/shadow",
        "services:\n  app:\n    image: x\n    secrets:\n      - h\n"
        "secrets:\n  h:\n    file: /etc/shadow\n",
        True,
    ),
    (
        "env_file remontant hors du projet",
        "services:\n  app:\n    image: x\n    env_file: ../../root/.env\n",
        True,
    ),
    (
        "build.context pointant la racine",
        "services:\n  app:\n    build:\n      context: /\n",
        True,
    ),
    (
        "configs: file: relatif au projet accepté",
        "services:\n  app:\n    image: x\n    configs:\n      - source: v\n        target: /app/c\n"
        "configs:\n  v:\n    file: ./config/reglages.json\n",
        False,
    ),
    (
        "env_file relatif au projet accepté",
        "services:\n  app:\n    image: x\n    env_file: .env\n",
        False,
    ),
    (
        "compose légitime : volume nommé, utilisateur non privilégié",
        'services:\n  app:\n    image: x\n    user: "1000"\n    volumes:\n'
        "      - donnees:/var/lib/data\nvolumes:\n  donnees:\n",
        False,
    ),
]


def main() -> int:
    echecs = 0
    for description, contenu, doit_refuser in CAS:
        with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False) as fh:
            fh.write(contenu)
            chemin = fh.name
        try:
            res = subprocess.run(
                [sys.executable, str(VERIFIEUR), chemin],
                capture_output=True,
                text=True,
            )
        finally:
            Path(chemin).unlink()

        refuse = res.returncode == 1
        ok = refuse == doit_refuser
        obtenu = "refusé" if refuse else ("accepté" if res.returncode == 0 else f"code {res.returncode}")
        attendu = "refusé" if doit_refuser else "accepté"
        print(f"  {'OK   ' if ok else 'ECHEC'} {description} → {obtenu} (attendu {attendu})")
        if not ok:
            echecs += 1

    print()
    if echecs:
        print(f"Resultat : {echecs} contournement(s) passent encore")
        return 1
    print("Resultat : tous les contournements sont bloques")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Refuse la présence d'un secret dans le dépôt.

    ./scripts/check-secrets.py [chemin...]   analyse des fichiers (défaut : .)
    ./scripts/check-secrets.py --staged      analyse ce qui est sur le point d'être commité
    ./scripts/check-secrets.py --history     analyse tout l'historique git

Codes de sortie : 0 rien trouvé · 1 secret détecté · 2 le contrôle n'a pas pu
être effectué (chemin illisible, git absent). Un garde-fou qui répond « OK »
alors qu'il n'a rien pu vérifier est pire que pas de garde-fou.

Ce fichier ne contient AUCUNE valeur sensible : les motifs propres à votre
infrastructure (adresses IP, domaines) vont dans `.secrets-patterns.local`,
ignoré par git. Voir `.secrets-patterns.local.example`.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Motifs de contenu : la seule présence de la chaîne est une fuite.
CONTENT_PATTERNS = [
    (r"/Users/[a-z]", "chemin personnel macOS"),
    (r"/home/[a-z]+/(Developer|Documents|Desktop)", "chemin personnel Linux"),
    (r"BEGIN [A-Z ]*PRIVATE KEY", "clé privée"),
    (r"AGE-SECRET-KEY-1[a-z0-9]+", "clé privée age"),
    (r"sk-(proj-|ant-|or-)?[A-Za-z0-9_-]{20,}", "clé de type OpenAI/Anthropic"),
    (r"sk_live_[A-Za-z0-9]+", "clé Stripe de production"),
    (r"rk_live_[A-Za-z0-9]+", "clé Stripe restreinte"),
    (r"ghp_[A-Za-z0-9]{20,}", "jeton GitHub"),
    (r"github_pat_[A-Za-z0-9_]{20,}", "jeton GitHub"),
    (r"xox[baprs]-[A-Za-z0-9-]{10,}", "jeton Slack"),
    (r"AKIA[0-9A-Z]{16}", "clé AWS"),
    (r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.", "jeton JWT"),
]

# Variables dont la VALEUR est analysée : c'est la valeur qui peut être un
# placeholder légitime, jamais la ligne entière — sans quoi une ligne contenant
# à la fois « example.com » et une vraie clé passerait inaperçue.
# Toute variable dont le NOM annonce un secret. Une liste fermee laissait
# passer HETZNER_API_TOKEN, CLOUDFLARE_API_TOKEN et DATABASE_URL — verifie.
# URL de connexion : c'est le secret que deploy.sh exige, et il passait sans
# alerte. Le mot de passe est extrait puis analyse comme une valeur, pour ne pas
# signaler les placeholders des fichiers .example.
CONNECTION_URL = re.compile(
    r"(?P<schema>postgres|postgresql|mysql|mongodb|redis|amqp)://"
    r"[^:/@\s]+:(?P<value>[^@\s]{3,})@(?P<hote>[^:/\s]+)"
)

# Une base sur localhost est un environnement de developpement, pas un secret
# de production. L'exempter evite un bruit permanent qui ferait ignorer l'outil.
HOTES_LOCAUX = {"localhost", "127.0.0.1", "::1", "0.0.0.0", "db", "host.docker.internal"}

SECRET_ASSIGNMENTS = re.compile(
    # Le prefixe est OPTIONNEL : « PASSWORD=hunter2 » sans prefixe passait.
    r"\b(?P<nom>(?:[A-Z][A-Z0-9_]*_)?"
    r"(?:PASSWORD|PASSWD|SECRET|API_?KEY|APIKEY|TOKEN|CREDENTIAL|PRIVATE_KEY"
    r"|ACCESS_KEY|CLIENT_SECRET|DATABASE_URL|DB_URL|DSN))"
    r"\s*[:=]\s*(?P<value>\S+)"
)

# Une valeur EXACTEMENT égale à l'un de ces motifs est un placeholder.
# Une valeur EXACTEMENT egale a l'un de ces motifs est un placeholder.
#
# « password », « secret », « dev » et « test » ont ete RETIRES : ce sont de
# vrais mots de passe faibles, et les tolerer rendait POSTGRES_PASSWORD=password
# invisible. Mieux vaut un faux positif qu'un secret publie.
PLACEHOLDER_VALUE = re.compile(
    r"^(CHANGE_?ME|CHANGEME|changeme|placeholder|PLACEHOLDER|a_remplir"
    r"|your[-_ ]?\w*|YOUR[-_ ]?\w*|x{3,}|X{3,}|<[^>]+>|\$\{.*|\$[A-Z_][A-Z0-9_]*"
    r"|\.\.\.|[A-Z]{2,}(_[A-Z0-9]+)+|)$"
)

# Une DECLARATION DE TYPE n'est pas une affectation de valeur. En TypeScript,
# `readonly STRIPE_SECRET_KEY: string` decrit la forme d'un objet ; il n'y a
# aucun secret sur la ligne. Sans cette exemption, tout fichier decrivant ses
# variables d'environnement (`env.d.ts`, une interface, une doc) est signale —
# le garde-fou devient bruyant, et un garde-fou bruyant finit contourne.
TYPE_ANNOTATION = re.compile(
    r"^(string|number|boolean|bigint|symbol|unknown|any|never|null|undefined|object|Date"
    r"|str|int|float|bool|bytes|Optional\[.*\]|List\[.*\]|Dict\[.*\])(\[\])?(\s*\|\s*\w+)*$"
)

SKIP_DIRS = {".git", "node_modules", "dist", ".output", "__pycache__", ".venv"}
# Chemins EXACTS depuis la racine du depot. Exempter par simple nom de fichier
# laissait passer `git add -f sous-dossier/.secrets-patterns.local`.
SKIP_PATHS = {
    "scripts/check-secrets.py",
    "tests/test-check-secrets.py",
    ".secrets-patterns.local",
    # Anciens noms, encore presents dans l'historique git.
    "scripts/check-no-secrets.sh",
    "tests/test-check-no-secrets.sh",
}


def local_patterns() -> list[tuple[str, str]]:
    path = ROOT / ".secrets-patterns.local"
    if not path.exists():
        return []
    out = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            out.append((line, "motif privé de votre infrastructure"))
    return out


def strip_quotes(value: str) -> str:
    value = value.strip().rstrip(",;")
    # Placeholder ouvrant mais tronque par la coupure sur l'espace :
    # `'<jeton fourni par...` doit etre reconnu comme placeholder.
    if value.startswith(("'<", '"<', "<")):
        return "<placeholder>"
    # Une valeur vide suivie d'un commentaire (`SECRET= # à générer`) n'est pas
    # un secret : c'est un champ à remplir.
    if value.startswith("#"):
        return ""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value


def git_ignored(paths: list[Path]) -> set[Path]:
    """Fichiers exclus par .gitignore : ils ne seront jamais publiés."""
    if not paths:
        return set()
    result = subprocess.run(
        ["git", "check-ignore", "--stdin"],
        input="\n".join(str(p) for p in paths),
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    # code 0 = au moins un ignoré, 1 = aucun, >1 = git indisponible
    if result.returncode > 1:
        return set()
    return {Path(line) for line in result.stdout.splitlines() if line}


def scan_text(text: str, origin: str, patterns: list[tuple[str, str]]) -> list[str]:
    findings = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for pattern, label in patterns:
            try:
                if re.search(pattern, line):
                    # La valeur n'est jamais affichee : un rapport de fuite ne
                    # doit pas recopier le secret dans les journaux.
                    findings.append(f"{origin}:{lineno} — {label} (valeur masquee)")
            except re.error as exc:
                raise SystemExit(f"[code 2] motif prive invalide (ligne {patterns.index((pattern, label)) + 1} de .secrets-patterns.local) : {exc.msg}")
        for match in CONNECTION_URL.finditer(line):
            value = strip_quotes(match.group("value"))
            if match.group("hote") in HOTES_LOCAUX:
                continue
            if not PLACEHOLDER_VALUE.match(value):
                findings.append(
                    f"{origin}:{lineno} — URL {match.group('schema')} avec un mot de "
                    f"passe non factice (valeur masquee)"
                )
        for match in SECRET_ASSIGNMENTS.finditer(line):
            value = strip_quotes(match.group("value"))
            # Une URL de connexion est deja analysee plus haut, avec ses regles
            # propres (hotes locaux, placeholder dans le mot de passe). La
            # traiter ici en plus produirait un doublon et des faux positifs.
            if "://" in value:
                continue
            # Motif de recherche ou fragment de code, pas un secret :
            # `grep -qE '^DATABASE_URL='` ou `startswith("DATABASE_URL=")`.
            if any(c in value for c in "^*\\|()[]{}") or value.endswith(('"', "'")):
                continue
            # Un secret fait au moins quelques caracteres.
            if len(value) < 6:
                continue
            # `readonly STRIPE_SECRET_KEY: string` decrit un type, pas une valeur.
            if TYPE_ANNOTATION.match(value):
                continue
            if not PLACEHOLDER_VALUE.match(value):
                findings.append(
                    f"{origin}:{lineno} — {match.group('nom')} a une valeur non factice "
                    f"(valeur masquee)"
                )
    return findings


def iter_files(targets: list[str]):
    for target in targets:
        path = Path(target)
        if not path.exists():
            raise SystemExit(f"[code 2] chemin introuvable : {target}")
        if path.is_file():
            yield path
            continue
        for child in path.rglob("*"):
            if not child.is_file():
                continue
            if SKIP_DIRS & set(child.parts):
                continue
            if str(child).lstrip("./") in SKIP_PATHS:
                continue
            yield child


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, cwd=ROOT
    )
    if result.returncode != 0:
        raise SystemExit(f"[code 2] git {' '.join(args)} a échoué : {result.stderr.strip()}")
    return result.stdout


def main() -> int:
    argv = sys.argv[1:]
    patterns = CONTENT_PATTERNS + local_patterns()
    findings: list[str] = []

    if "--staged" in argv:
        # Analyse l'INDEX, pas le disque : un secret ajouté puis retiré du
        # fichier local resterait sinon dans le commit.
        names = [n for n in git("diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-M").split("\n") if n]
        for name in names:
            if name in SKIP_PATHS:
                continue
            findings += scan_text(git("show", f":{name}"), name, patterns)

    elif "--history" in argv:
        text = git("log", "-p", "--all")
        kept, skipping = [], False
        for line in text.splitlines():
            if line.startswith("diff --git "):
                skipping = any(name in line for name in SKIP_PATHS)
            if skipping or line.startswith(("Author:", "Commit:", "Date:", "Merge:")):
                continue
            kept.append(line)
        findings += scan_text("\n".join(kept), "historique", patterns)

    else:
        targets = [a for a in argv if not a.startswith("--")] or ["."]
        files = list(iter_files(targets))
        # Ce que .gitignore exclut ne sera jamais publié : le signaler
        # produirait un bruit permanent (fichiers .env locaux, caches).
        ignored = git_ignored(files)
        for path in files:
            if path in ignored:
                continue
            try:
                findings += scan_text(path.read_text(errors="ignore"), str(path), patterns)
            except OSError as exc:
                raise SystemExit(f"[code 2] lecture impossible : {path} ({exc})")

    if findings:
        print("SECRET DETECTE — ne pas publier :")
        for finding in findings[:20]:
            print(f"  {finding}")
        if len(findings) > 20:
            print(f"  … et {len(findings) - 20} autres")
        return 1

    print("OK : aucun secret detecte.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(exc.code, file=sys.stderr)
            sys.exit(2)
        raise

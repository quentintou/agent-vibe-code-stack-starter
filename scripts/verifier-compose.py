#!/usr/bin/env python3
"""Refuse un docker-compose.yml qui donnerait au conteneur un accès à l'hôte.

    python3 scripts/verifier-compose.py docker-compose.yml

Ce fichier est confié à un service Docker qui tourne en root. Un compose
déclarant `privileged`, un montage de `/`, ou le socket Docker donne un accès
complet au serveur — clés SSH comprises.

L'analyse porte sur le YAML **interprété**, jamais sur des motifs de texte :
`privileged : true` avec une espace, `user: root` au lieu de `user: 0`, ou la
syntaxe longue d'un montage (`type: bind`) échappent à toute recherche de motifs.

Sortie 0 si le fichier est sûr, 1 sinon, 2 si l'analyse est impossible.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("[code 2] PyYAML requis : python3 -m pip install pyyaml")

CLES_INTERDITES = {
    "privileged": "accès privilégié complet à l'hôte",
    "cap_add": "capacités noyau supplémentaires",
    "devices": "accès direct aux périphériques de l'hôte",
    "security_opt": "désactivation possible des protections seccomp/AppArmor",
    "userns_mode": "contournement de l'isolation des utilisateurs",
    "sysctls": "modification des paramètres noyau",
    "pid": "partage de l'espace de processus",
    "ipc": "partage de la mémoire partagée",
    "network_mode": "partage de la pile réseau de l'hôte",
}

UTILISATEURS_INTERDITS = {"0", "root", "0:0", "root:root"}


def sort_du_projet(chemin: str) -> bool:
    """Vrai si ce chemin designe un fichier hors du dossier du projet.

    Un chemin absolu (« /root/.ssh/id_ed25519 ») ou remontant (« ../ ») vise
    l'hote. Un chemin relatif descendant (« ./config/nginx.conf ») reste dans
    le projet : c'est l'usage legitime et il doit passer.
    """
    chemin = chemin.strip().strip('"').strip("'")
    if not chemin:
        return False
    if chemin.startswith(("/", "~", "$")):
        return True
    return any(part == ".." for part in chemin.replace("\\", "/").split("/"))


def fichiers_de_lhote(doc: dict) -> list[tuple[str, str]]:
    """Fichiers de l'hote injectes autrement que par un volume.

    `volumes:` n'est pas le seul chemin d'entree. Les blocs `configs:` et
    `secrets:` acceptent `file:` et copient N'IMPORTE QUEL fichier de l'hote
    dans le conteneur — cle SSH, /etc/shadow. `env_file` et `build.context`
    lisent eux aussi l'hote. Ne controler que `volumes:` laissait ces quatre
    portes ouvertes. Trouve par audit adverse le 2026-07-26.
    """
    trouves: list[tuple[str, str]] = []

    for bloc in ("configs", "secrets"):
        for nom, definition in (doc.get(bloc) or {}).items():
            if isinstance(definition, dict) and "file" in definition:
                chemin = str(definition["file"])
                if sort_du_projet(chemin):
                    trouves.append((f"{bloc} « {nom} »", chemin))

    for nom, service in (doc.get("services") or {}).items():
        if not isinstance(service, dict):
            continue

        env_file = service.get("env_file")
        entrees = [env_file] if isinstance(env_file, str) else (env_file or [])
        for entree in entrees:
            chemin = entree.get("path", "") if isinstance(entree, dict) else str(entree)
            if sort_du_projet(chemin):
                trouves.append((f"service « {nom} » : env_file", chemin))

        build = service.get("build")
        contexte = build.get("context") if isinstance(build, dict) else build
        if isinstance(contexte, str) and sort_du_projet(contexte):
            trouves.append((f"service « {nom} » : build.context", contexte))

    return trouves


def chemins_montes(service: dict) -> list[str]:
    """Retourne les chemins de l'hôte montés, syntaxe courte comme longue."""
    trouves = []
    for volume in service.get("volumes") or []:
        if isinstance(volume, str):
            source = volume.split(":")[0]
            # Un volume nommé n'a pas de séparateur de chemin.
            if source.startswith((".", "/", "~", "$")):
                trouves.append(source)
        elif isinstance(volume, dict):
            if volume.get("type") == "bind":
                trouves.append(str(volume.get("source", "?")))
    return trouves


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage : verifier-compose.py <docker-compose.yml>")
        return 2

    chemin = Path(sys.argv[1])
    if not chemin.exists():
        print(f"[code 2] fichier introuvable : {chemin}")
        return 2

    texte = chemin.read_text()
    # Les substitutions d'environnement empêchent le parsing : on les neutralise.
    import re

    texte = re.sub(r"\$\{[^}]*\}", "x", texte)

    try:
        doc = yaml.safe_load(texte) or {}
    except yaml.YAMLError as exc:
        print(f"[code 2] YAML illisible : {exc}")
        return 2

    problemes: list[str] = []

    for nom, service in (doc.get("services") or {}).items():
        if not isinstance(service, dict):
            continue

        for cle, raison in CLES_INTERDITES.items():
            if cle not in service:
                continue
            valeur = service[cle]
            # pid/ipc/network_mode ne posent problème qu'en mode « host ».
            if cle in {"pid", "ipc", "network_mode"} and "host" not in str(valeur):
                continue
            problemes.append(f"service « {nom} » : {cle} — {raison}")

        utilisateur = str(service.get("user", "")).strip().strip('"').strip("'")
        if utilisateur.lower() in UTILISATEURS_INTERDITS:
            problemes.append(f"service « {nom} » : user={utilisateur} — exécution en root")

        for source in chemins_montes(service):
            problemes.append(
                f"service « {nom} » : monte « {source} » depuis l'hôte — utiliser un volume nommé"
            )
            if "docker.sock" in source:
                problemes[-1] += " (le socket Docker équivaut à un accès root)"

    for origine, chemin in fichiers_de_lhote(doc):
        probleme = f"{origine} lit « {chemin} » sur l'hôte"
        if any(m in chemin for m in (".ssh", "shadow", "passwd", "docker.sock")):
            probleme += " — fichier sensible de l'hôte"
        problemes.append(probleme)

    if problemes:
        print("ERREUR : docker-compose.yml contient des directives interdites :")
        for probleme in problemes:
            print(f"  - {probleme}")
        return 1

    print("   compose sûr : aucune directive privilégiée, aucun montage de l'hôte.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

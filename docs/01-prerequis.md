# 1. Prérequis

À vérifier avant toute chose. Si l'un manque, s'arrêter et le demander à
l'utilisateur — ne pas contourner.

## Sur la machine de l'utilisateur

```bash
git --version      # n'importe quelle version récente
node --version     # v22 ou plus
python3 --version  # v3.9 ou plus — les garde-fous sont écrits en Python
ssh -V             # présent sur macOS et Linux
rsync --version    # présent sur macOS et Linux
curl --version     # contrôles de santé
dig -v             # vérification DNS  (paquet bind9-dnsutils / bind)
openssl version    # génération des secrets
gh --version       # étape GitHub — https://cli.github.com
```

Si `node` manque : https://nodejs.org (version LTS).
Si `dig` manque : `brew install bind` (macOS) ou
`apt install bind9-dnsutils` (Debian/Ubuntu).

**Ne pas se contenter de « ça doit être installé ».** Lancer réellement ces
commandes : une seule absente fait échouer une étape au milieu, là où le
diagnostic est le plus pénible.

**Docker n'est pas requis sur cette machine.** L'image est construite sur le
serveur. Pour développer en local il faut seulement une base Postgres : voir
`docs/06-developper-en-local.md`, qui propose quatre options dont deux sans
Docker.

## Comptes nécessaires

| Compte | Usage | Coût |
|---|---|---|
| Hébergeur VPS | faire tourner l'application | ~5 €/mois |
| Cloudflare | domaine, HTTPS, anti-robots | gratuit |
| GitHub | héberger le code, revenir en arrière | gratuit |

## Ce que l'utilisateur doit fournir

1. **L'accès SSH au serveur** — sous la forme `root@203.0.113.10`.
   Vérification : `ssh root@203.0.113.10 'echo ok'` doit afficher `ok`.
2. **Le nom de domaine**, et confirmation qu'il est géré chez Cloudflare
   (les serveurs de noms du domaine pointent vers Cloudflare).

Sans ces deux éléments, on ne va pas plus loin. Les demander explicitement.

# Mettre le code sur GitHub

À faire **avant** le premier déploiement, pas après. Le dépôt est ce qui permet
de revenir en arrière quand un déploiement casse quelque chose ; sans lui, la
seule copie du travail est le dossier local.

---

## Ce que l'agent ne peut pas faire

Il ne peut ni créer un compte GitHub, ni s'y authentifier : cela demande un
navigateur, une adresse e-mail à confirmer, et parfois une double
authentification. Ces étapes reviennent à l'utilisateur.

Une fois `gh auth login` fait **une seule fois** sur la machine, l'agent
travaille seul.

## 1. Installer et connecter GitHub CLI

```bash
# macOS
brew install gh
# Debian / Ubuntu : voir https://cli.github.com

gh auth login
```

Choisir `GitHub.com`, puis `HTTPS`, puis l'authentification par navigateur.

Vérifier :

```bash
gh auth status
```

Attendu : `Logged in to github.com account <votre-compte>`.

## 2. Publier le projet

Depuis la racine du projet :

```bash
./scripts/init-git.sh mon-tableau-de-bord
```

Le script, dans cet ordre :

1. complète le `.gitignore` (`.env`, `node_modules/`, `dist/`,
   `deploy.config.json`…) sans écraser ce qui s'y trouve déjà ;
2. initialise le dépôt local sur la branche `main` ;
3. installe le hook `pre-commit` qui lance le garde-fou anti-secrets ;
4. **cherche les secrets et s'arrête s'il en trouve** ;
5. crée le premier commit ;
6. crée le dépôt **privé** sur GitHub et pousse.

L'ordre du point 4 est le cœur du script. Voir plus bas pourquoi.

## 3. Vérifier

```bash
gh repo view --json url,visibility -q '"\(.visibility) — \(.url)"'
git log --oneline
```

Attendu : `PRIVATE — https://github.com/...` et au moins un commit.

---

## Pourquoi privé par défaut

Le dépôt contient la configuration de votre infrastructure : le nom de domaine,
la forme du déploiement, parfois l'adresse du serveur. Rien de tout cela n'est
un secret au sens strict, mais rien n'oblige à le publier non plus.

`init-git.sh` ne propose pas d'option pour créer un dépôt public. Rendre un
dépôt public est une décision qui se prend en conscience, sur github.com, après
avoir relu l'historique.

## Un secret poussé est un secret compromis

C'est la raison pour laquelle le garde-fou tourne **avant** `gh repo create`.

Une clé poussée sur GitHub ne se rattrape pas en la supprimant dans le commit
suivant : elle reste dans l'historique, et les dépôts publics sont indexés par
des robots en quelques secondes. Même sur un dépôt privé, il faut la considérer
comme lue.

La seule réponse correcte est de **révoquer la clé et d'en générer une
nouvelle**. Réécrire l'historique (`git filter-repo`, `--force`) ne suffit pas :
GitHub conserve les objets orphelins un certain temps, et toute copie déjà
clonée les garde.

Si le garde-fou vous arrête, il vous rend service. Ne le contournez pas.

## Ce qui n'est jamais versionné

| Fichier | Pourquoi |
|---|---|
| `.env`, `.env.production` | mots de passe, clés, secret d'authentification |
| `deploy.config.json` | adresse du serveur et chemins de déploiement |
| `node_modules/` | reconstruit par `npm ci`, des milliers de fichiers |
| `dist/`, `.output/` | produits par la construction, jamais édités |

`.env.example` **est** versionné : il documente les variables attendues, sans
valeurs.

## Ensuite

Le dépôt n'est pas relié au déploiement : `deploy.sh` envoie le contenu du
dossier local, pas celui de GitHub. Les deux sont indépendants — on peut
déployer sans avoir poussé, et pousser sans déployer.

Un enchaînement raisonnable :

```bash
git add -A && git commit -m "Ce que j'ai changé" && git push
./scripts/deploy.sh
```

Committer d'abord : si le déploiement casse quelque chose, l'état d'avant est
récupérable.

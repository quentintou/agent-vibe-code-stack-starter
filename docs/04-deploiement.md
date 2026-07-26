# 4. Déployer

Deux chemins, deux mises en place. Choisir d'abord dans `DECIDE.md` :

- **Application** — comptes, base de données. Squelette `templates/app/`.
- **Contenu** — site statique, aucune base. Squelette `templates/content/`.

Dans tout ce document, `$STARTER` désigne le dossier où ce dépôt a été cloné :

```bash
STARTER=~/agent-vibe-code-stack-starter    # à adapter
```

C'est nécessaire : une fois dans le dossier du projet, `infra/` et `scripts/`
ne sont plus à portée de main. Les oublier bloque tout au premier essai.

---

## A. Chemin application

### Mise en place, une seule fois

```bash
cp -r "$STARTER/templates/app/" ~/mon-projet
cd ~/mon-projet

cp "$STARTER/infra/Dockerfile.app.example"          Dockerfile
cp "$STARTER/infra/docker-compose.app.example.yml"  docker-compose.yml
cp "$STARTER/infra/deploy.config.example.json"      deploy.config.json
cp -r "$STARTER/scripts"                            scripts
chmod +x scripts/*.sh
```

Le dossier `scripts/` se copie **en entier** : `deploy.sh` appelle
`verifier-compose.py`, qui relit le fichier compose avant de le confier au
service Docker. Copier `deploy.sh` seul fait échouer le déploiement.

Ensuite :

1. Dans `docker-compose.yml`, remplacer `PROJET` et `APP_PORT`.
   Choisir un port libre sur le serveur (`ss -tlnp` pour vérifier).
2. Remplir `deploy.config.json` (tableau plus bas).
3. Créer `.env.production` à partir de `.env.example`, et le remplir.

### Les secrets

Générer chaque secret avec `openssl rand -base64 32`. `DATABASE_URL` doit être
**complète**, mot de passe déjà encodé :

```
DATABASE_URL=postgres://cockpit:MOT_DE_PASSE@cockpit-db:5432/cockpit
```

L'hôte est le nom du conteneur Postgres, **jamais** l'alias `db` : sur un
serveur partagé, cet alias peut résoudre vers la base d'un autre projet.

Si le mot de passe contient `@`, `/`, `:` ou `%`, il faut l'encoder :

```bash
python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" 'mon@mot:de/passe'
```

Le plus simple reste d'en générer un sans caractère spécial :
`openssl rand -hex 24`.

---

## B. Chemin contenu

### Mise en place, une seule fois

```bash
cp -r "$STARTER/templates/content/" ~/mon-site
cd ~/mon-site

cp "$STARTER/infra/deploy.config.contenu.example.json" deploy.config.json
cp -r "$STARTER/scripts"                               scripts
chmod +x scripts/*.sh
npm install
```

Ni `Dockerfile`, ni `docker-compose.yml`, ni fichier de secrets : un site
statique n'a ni conteneur en service, ni base de données. La construction a
lieu sur le serveur, dans un conteneur jetable.

Un fichier `.env` reste possible si le site utilise des variables `PUBLIC_*` —
déclarer alors `secrets_file` dans la configuration. **L'adresse du site n'en
fait pas partie** : `deploy.sh` l'impose depuis le champ `domain`, pour que le
plan du site et les liens canoniques soient corrects.

---

## `deploy.config.json`, champ par champ

| Champ | Chemin | Ce que c'est | Exemple |
|---|---|---|---|
| `kind` | les deux | `"app"` ou `"content"`. Absent = `"app"` | `"content"` |
| `project` | les deux | nom court ; sert au dossier distant et au fichier Caddy | `cockpit` |
| `vps.host` | les deux | cible SSH | `root@203.0.113.10` |
| `app.dir` | les deux | dossier sur le serveur — **doit valoir** `/opt/apps/<project>` | `/opt/apps/cockpit` |
| `domain` | les deux | domaine servi | `cockpit.example.com` |
| `health_url` | les deux | URL de contrôle, sur ce domaine uniquement | voir ci-dessous |
| `secrets_file` | application | fichier d'environnement local, jamais commité | `.env.production` |
| `app.image_name` | application | nom de l'image Docker | `cockpit-app` |
| `app.db_container` | application | nom du conteneur Postgres — jamais `db` | `cockpit-db` |
| `app.app_port` | application | port local de l'application sur le serveur | `8300` |

`health_url` : `https://<domaine>/api/health` pour une application,
`https://<domaine>/` pour un site de contenu.

**Accès SSH particulier** (port non standard, clé dédiée) : le déclarer dans
`~/.ssh/config`, pas dans ce fichier. Le script n'accepte aucune option SSH
libre — une valeur arbitraire y serait exécutée sur votre machine.

```
Host mon-serveur
    HostName 203.0.113.10
    User root
    Port 2222
    IdentityFile ~/.ssh/ma-cle
```

`vps.host` vaut alors `root@mon-serveur`.

---

## Déployer

Depuis la racine du projet, dans les deux cas :

```bash
./scripts/deploy.sh --check    # vérifie les accès sans rien déployer
./scripts/deploy.sh            # déploie
```

Sortie attendue :

```
=== Déploiement réussi — https://cockpit.example.com ===
```

Le script s'arrête **avant d'agir** si : la configuration manque, une valeur
est invalide, des `CHANGE_ME` subsistent, ou `DATABASE_URL` vise l'alias `db`.

## Ce que fait le script

1. vérifie les accès et l'état du serveur ;
2. pose un verrou pour ce projet, le temps du déploiement ;
3. envoie les sources (sans `node_modules`, sans `.env`) ;
4. envoie les secrets séparément, en `chmod 600` — chemin application ;
5. dépose son fragment Caddy dans `/etc/caddy/sites/<projet>.caddy` ;
6. construit, puis :
   - **application** : démarre la base, applique les migrations, et seulement
     ensuite met l'application en service ;
   - **contenu** : construit le site dans un conteneur jetable et bascule le
     dossier publié d'un bloc ;
7. recharge Caddy et vérifie qu'il écoute vraiment ;
8. interroge l'URL de santé depuis l'extérieur ;
9. télécharge un fichier statique cité par la page.

Les étapes 6 à 9 ne sont pas décoratives : chacune correspond à une panne où le
déploiement s'annonçait réussi pendant que le site était inutilisable. Le détail
est dans `docs/05-pannes.md`.

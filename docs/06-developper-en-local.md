# 6. Développer en local

**Docker n'est pas nécessaire sur votre machine.** Il ne sert que sur le serveur :
le déploiement construit l'image à distance, par SSH. En local, il faut
seulement `node` 22+, `git`, `ssh` et `rsync`.

Le seul service dont le développement a besoin, c'est une base Postgres.
Quatre façons de l'obtenir, de la plus simple à la plus proche de la production.

---

## Option A — Postgres.app (macOS, recommandé pour démarrer)

Une application à glisser dans le dossier Applications, un bouton « Start ».
Pas de service à configurer, pas de ligne de commande.

<https://postgresapp.com>

Puis, dans `.env` :

```
DATABASE_URL=postgres://postgres@localhost:5432/postgres
```

---

## Option B — Homebrew (macOS/Linux)

```bash
brew install postgresql@17
brew services start postgresql@17
createdb mon_projet
```

```
DATABASE_URL=postgres://$(whoami)@localhost:5432/mon_projet
```

Arrêter le service : `brew services stop postgresql@17`.

---

## Option C — une base distante gratuite

Aucune installation. Créez une base sur Neon ou Supabase, copiez l'URL de
connexion fournie dans `.env`. Pratique sur une machine d'appoint, ou quand on
travaille à plusieurs sur la même base de développement.

Inconvénient : il faut une connexion internet, et les latences sont plus élevées
qu'en local.

---

## Option D — Docker, si vous l'avez déjà

```bash
docker run --rm -d --name dev-db \
  -e POSTGRES_PASSWORD=CHANGE_ME -e POSTGRES_USER=dev -e POSTGRES_DB=dev \
  -p 127.0.0.1:5432:5432 postgres:17-alpine
```

```
DATABASE_URL=postgres://dev:CHANGE_ME@localhost:5432/dev
```

C'est la seule option identique à la production (même version, même image).
Utile avant un déploiement, superflu au quotidien.

---

## Lancer le projet

```bash
cd mon-projet
npm install
cp .env.example .env      # puis remplir DATABASE_URL
npm run db:migrate        # crée les tables
npm run dev               # http://localhost:3000
```

## Vérifier que la base répond

```bash
curl -s http://localhost:3000/api/health
```

Attendu : `{"ok":true}`.

Si la réponse est `{"ok":false}`, c'est que `DATABASE_URL` est
faux ou que la base n'est pas démarrée. En local, l'hôte est `localhost` — la
règle du nom de conteneur (`<projet>-db`) ne concerne que le serveur.

## Tester le build de production en local

```bash
npm run build
npm start                 # http://localhost:3000
```

`npm start` lance `server.mjs`, pas `dist/server/server.js` : ce dernier exporte
un handler et n'écoute aucun port. Voir `docs/05-pannes.md`, panne n°6.

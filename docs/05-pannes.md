# 5. Pannes connues

À lire quand quelque chose échoue. Chaque entrée vient d'une panne réelle.

---

## 1. Erreurs d'authentification à la base, par intermittence

**Symptôme.** L'application fonctionne, puis renvoie par moments
`28P01 password authentication failed`. Rien n'a changé. Un redémarrage
« corrige » le problème pour un temps.

**Cause.** Le réseau Docker `web` est partagé par tous les projets du serveur.
Si deux projets exposent un service nommé `db`, l'alias réseau `db` résout
alternativement vers l'un ou l'autre Postgres. Une requête sur deux atterrit sur
la mauvaise base.

**Correction.** Dans `DATABASE_URL`, utiliser le nom du conteneur, jamais
l'alias :

```
# faux
DATABASE_URL=postgres://user:pw@db:5432/base
# juste
DATABASE_URL=postgres://user:pw@cockpit-db:5432/base
```

`deploy.sh` refuse désormais de déployer une configuration qui vise `db`.

---

## 1 bis. Connexion impossible, ou tables inexistantes

**Symptôme.** Le site répond, mais toute connexion échoue en `401`, ou la base
ne contient aucune table.

**Deux causes, souvent ensemble :**

1. `src/lib/auth.ts` ne définit pas `database`. better-auth bascule alors sur un
   stockage **en mémoire** : rien n'est créé, rien ne persiste. Vérifier la
   présence de `database: drizzleAdapter(db, { provider: 'pg' })`.
2. Les migrations n'ont pas été appliquées. Vérifier :

```bash
ssh <vps> 'docker exec <projet>-db psql -U <projet> -d <projet> -c "\dt"'
```

Attendu : `user`, `session`, `account`, `verification`, plus vos tables métier.
Si la liste est vide, relancer `./scripts/deploy.sh` — il applique les migrations avant
le contrôle de santé.

Après tout changement de `src/db/schema.ts`, régénérer les migrations :

```bash
npm run db:generate    # puis committer le dossier drizzle/
```

---

## 2. Caddy ne sert pas le site

```bash
ssh <vps> 'ls /etc/caddy/sites/'
ssh <vps> 'caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile'
ssh <vps> 'journalctl -u caddy -n 30 --no-pager'
```

Causes fréquentes : le fragment du projet est absent de `/etc/caddy/sites/`, ou
un autre fragment contient une erreur de syntaxe — dans ce cas **tous** les sites
tombent, l'import étant global. `caddy validate` désigne le fichier fautif.

---

## 3. Pas de certificat HTTPS

- Le DNS ne pointe pas encore : `dig +short <domaine>`.
- Le mode SSL de Cloudflare est sur « Flexible » : le mettre sur **Full (strict)**.
- Le port 443 est fermé par le pare-feu de l'hébergeur.

---

## 4. `docker compose up` échoue sur le réseau `web`

```
network web declared as external, but could not be found
```

```bash
ssh <vps> 'docker network create web'
```

Ou relancer `scripts/bootstrap-vps.sh`, qui est idempotent.

---

## 5. Port déjà utilisé

```bash
ssh <vps> 'ss -tlnp | grep <port>'
```

Choisir un autre `app_port` ou `db_port` dans `deploy.config.json` **et** dans
`docker-compose.yml` — les deux doivent rester cohérents.

---

## 6. L'application démarre puis s'arrête aussitôt, sans message

**Cause.** `dist/server/server.js` n'est pas un serveur : il exporte un handler.
Lancé directement par `node`, il n'écoute rien et le processus se termine.

**Correction.** Démarrer par `node server.mjs` (ou `npm start`), qui monte le
handler sur un port. Le `Dockerfile` fourni le fait déjà.

---

## 7. Le build passe en local et échoue sur le serveur

Presque toujours une différence de version de Node. Le `Dockerfile` fixe
`node:22-alpine` ; vérifier que la machine locale est bien en Node 22 :
`node --version`.

---

## 8. Le garde-fou anti-secrets signale un fichier d'exemple

S'il s'agit d'un placeholder (`CHANGE_ME`, `<votre-domaine>`), c'est un faux
positif : compléter la liste `PLACEHOLDERS` dans `scripts/check-secrets.py`.
**Ne jamais désactiver le garde-fou** — un garde-fou bruyant qu'on éteint est
pire que pas de garde-fou du tout.


---

## 9. `deploy.sh` refuse mon `docker-compose.yml`

**Symptôme.** `ERREUR : docker-compose.yml contient une clause interdite`.

**Cause.** Le fichier déclare `privileged`, `cap_add`, `devices`,
`network_mode: host`, `user: 0`, le socket Docker, ou monte un chemin de l'hôte.
Ce compose est exécuté par un service Docker root : ces directives donnent au
conteneur un accès complet au serveur, y compris aux clés SSH.

**Correction.** Utiliser des volumes nommés, et laisser l'application tourner
sans privilège. Si la directive est réellement nécessaire (accès à un
périphérique, par exemple), déployer à la main après revue — ce n'est pas un
cas que ce dépôt couvre.

---

## 10. Créer un compte alors que l'inscription est fermée

```bash
./scripts/create-user.sh personne@exemple.fr "Nom Complet"
```

Le mot de passe est demandé de façon interactive. L'opération a lieu dans un
conteneur jetable : le service en ligne continue de refuser les inscriptions
pendant toute la durée, et le script le vérifie ensuite.

**Ne jamais** basculer `ALLOW_PUBLIC_SIGNUP=true` sur le service en ligne pour
créer un compte : même quelques secondes suffisent à ce qu'un robot de scan
s'inscrive.

## 11. Le déploiement s'annonce réussi mais le site ne répond pas du tout

**Symptôme.** `deploy.sh` affiche « Migrations appliquées » puis échoue à la
vérification de santé. Sur le serveur, l'application répond bien en local
(`curl http://127.0.0.1:<port>/api/health` → 200) et le fragment Caddy est
présent, mais depuis l'extérieur la connexion est refusée.

**Diagnostic.**

```bash
ssh <vps> 'ss -lnt | grep 443 || echo "aucun port 443 en ecoute"'
ssh <vps> 'curl -sS localhost:2019/config/'   # {} = configuration vide
```

**Cause.** Le script exécuté sur le serveur est envoyé à `bash -s` par
**l'entrée standard**. Toute commande de ce script qui lit elle aussi l'entrée
standard — `docker compose exec -T`, `docker compose run -T`, `cat` sans
fichier, `read` — consomme le reste du script. Bash arrive alors à la fin du
fichier et sort avec le **code 0** : les dernières étapes, dont le rechargement
de Caddy, n'ont jamais eu lieu, et rien ne le signale.

**Correctif.** Rediriger explicitement l'entrée de ces commandes :

```bash
docker compose exec -T app node migrate.mjs < /dev/null
```

`deploy.sh` place désormais un marqueur en fin de bloc distant et refuse de
continuer s'il ne le retrouve pas. Si vous ajoutez une commande au bloc distant
et voyez « le bloc distant s'est interrompu avant la fin », c'est cette cause.

## 12. Caddy réessaie sans fin d'obtenir un certificat pour `www.`

**Symptôme.** `journalctl -u caddy` répète toutes les vingt minutes :
`DNS problem: NXDOMAIN looking up A for www.<domaine>`.

**Cause.** Le fragment déclare un bloc `www.<domaine>` alors qu'aucun
enregistrement DNS ne pointe vers le serveur. Let's Encrypt refuse le
certificat, Caddy réessaie indéfiniment et finit par basculer sur son autorité
de secours — ce qui consomme le quota de demandes du domaine.

**Correctif.** `deploy.sh` ne génère plus ce bloc que si `www.<domaine>` résout
réellement. Pour l'obtenir, créez le CNAME `www` vers le domaine principal chez
Cloudflare (voir `docs/03-cloudflare.md`), puis relancez `./scripts/deploy.sh`.

## 13. Le site s'affiche sans style, en Times New Roman

**Symptôme.** La page se charge, le texte est là, mais tout est en police par
défaut, les liens sont bleus soulignés, aucune mise en page. Et
`curl https://<domaine>/api/health` répond pourtant `{"ok":true}`.

**Diagnostic.**

```bash
# Prendre une feuille de style citée par la page, puis la demander
curl -s https://<domaine>/ | grep -o '/assets/[^"]*\.css'
curl -o /dev/null -w '%{http_code}\n' https://<domaine>/assets/styles-XXXX.css
```

`404` confirme le diagnostic.

**Cause.** Le build de TanStack Start produit deux choses : `dist/server/`, qui
exporte un gestionnaire de requêtes, et `dist/client/`, qui contient les
fichiers destinés au navigateur. **Le gestionnaire ne sert pas `dist/client/`.**
Si personne ne le fait, chaque fichier statique renvoie 404 — pendant que les
routes applicatives, elles, répondent normalement.

C'est ce qui rend la panne pernicieuse : le contrôle de santé interroge une
route applicative et ne voit rien.

**Correctif.** `server.mjs` sert `dist/client/` avant de déléguer au
gestionnaire. Si vous écrivez votre propre entrée serveur, ne l'oubliez pas —
la documentation TanStack le précise : *« static assets must be served from the
client directory while all other requests are forwarded to the server entry's
fetch handler »*.

`deploy.sh` vérifie désormais qu'un fichier statique cité par la page d'accueil
se télécharge réellement, et refuse d'annoncer un déploiement réussi sinon.

## 14. Une route d'exemple expose la base sans authentification

**Symptôme.** Aucun. C'est ce qui rend la panne dangereuse.

**Diagnostic.**

Insérez une ligne témoin dans une table, puis demandez la page **sans aucun
cookie** — c'est exactement ainsi que la fuite a été confirmée ici :

```bash
curl -s https://<domaine>/<la-route-en-question> | grep -i '<votre témoin>'
```

Si le témoin apparaît, la route est ouverte à tous.

Les routes d'exemple de la CLI TanStack vivaient sous `/demo/`. Ce squelette ne
les livre plus ; le contrôle reste valable pour toute route que vous ajoutez.

**Cause.** La CLI TanStack génère des routes d'exemple sous `src/routes/demo/`.
L'une d'elles lit et écrit une table **sans vérifier la session**. Elles sont
faites pour être supprimées après lecture — mais rien ne le rappelle, et elles
partent en production avec le reste.

Trouvé par audit adverse sur la démonstration de ce dépôt, puis **confirmé en
ligne** : une ligne insérée en base apparaissait dans une requête sans le
moindre cookie.

**Correctif.** Ces routes ne sont plus livrées. Le squelette ne contient que
`/`, `/about`, `/connexion` et `/api/health`.

**Ce qu'il faut en retenir.** Une fonction serveur est un point d'entrée public.
Masquer un formulaire ne protège rien : **l'affichage n'est pas un contrôle
d'accès.** Toute fonction qui touche la base commence par vérifier la session :

```ts
const session = await auth.api.getSession({ headers: getRequest().headers })
if (!session?.user) throw new Error('Connexion requise.')
```

Voir `demos/tableau-de-bord/src/serveur/notes.ts` pour un exemple complet.

## 15. Le contrôle de santé publiait le message d'erreur de PostgreSQL

**Cause.** En cas d'échec, `/api/health` renvoyait `error.message` dans sa
réponse. Sur une URL ouverte à tous, cela révèle le nom d'hôte de la base,
l'utilisateur SQL, la table manquante et les conventions de déploiement.

**Correctif.** La réponse publique se limite à `{"ok":false}` avec un code 503.
Le détail part dans les journaux du conteneur :

```bash
ssh <vps> 'cd /opt/apps/<projet> && docker compose logs --tail 50 app'
```

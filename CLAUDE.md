# Instructions pour l'agent

Ce dépôt sert à monter et mettre en ligne une application web ou un site,
sur un serveur que l'utilisateur possède, avec un nom de domaine, du HTTPS et
une base de données. Tu es l'agent qui exécute ; l'utilisateur n'est pas
forcément développeur et ne saura probablement pas rattraper tes erreurs.

Lis ce fichier en entier avant d'agir.

---

## 1. Avant toute action : poser ces questions

Pose-les **une par une**, attends la réponse, et ne suppose jamais à la place de
l'utilisateur. S'il ne sait pas répondre, explique l'enjeu en une phrase et
propose l'option la plus simple.

1. « Ton projet sert-il surtout à **afficher du contenu** (site vitrine, blog,
   pages publiques), ou à faire **travailler des utilisateurs connectés**
   (tableau de bord, outil interne, application) ? »
2. « As-tu déjà un **nom de domaine** ? Si oui, lequel, et est-il géré chez
   Cloudflare ? »
3. « As-tu déjà un **serveur** (VPS) ? Si oui, donne-moi l'accès SSH. Sinon,
   il faudra en créer un — compte environ 5 € par mois. »
4. « Y a-t-il des données à **conserver** entre les redémarrages ? »

Puis lis `DECIDE.md` pour choisir le chemin.

**Sortie possible dès la première question.** Si l'utilisateur veut seulement un
site vitrine, sans formulaire à traiter, sans compte, et qu'il n'a pas déjà de
serveur : dis-lui que Cloudflare Pages ou Netlify feront le travail gratuitement
et plus simplement, et propose-lui de s'arrêter là. Ce dépôt lui deviendra utile
le jour où il aura un serveur, ou plusieurs sites à regrouper. Ne déroule pas les
étapes 0 à 6 pour rien.

---

## 2. Ordre des étapes

Ne saute aucune étape et ne les réordonne pas. À chaque étape, lis le document
indiqué **avant** de lancer quoi que ce soit.

| Étape | Document | Ce que tu fais |
|---|---|---|
| 0 | `docs/00-creer-un-serveur.md` | **Seulement si l'utilisateur n'a pas de serveur.** Comparer les hébergeurs, le faire ouvrir un compte, créer la machine par API |
| 1 | `docs/01-prerequis.md` | Vérifier les outils et les accès. S'arrêter si quelque chose manque. |
| 2 | `docs/02-vps.md` | Préparer le serveur : `scripts/bootstrap-vps.sh user@ip` |
| 3 | `docs/03-cloudflare.md` | Faire pointer le domaine vers le serveur |
| 4 | `docs/04-deploiement.md` §A ou §B | Copier le squelette du chemin choisi, remplir `deploy.config.json` |
| 5 | `docs/07-github.md` | Mettre le code sur GitHub — **avant** de déployer, pour pouvoir revenir en arrière |
| 6 | `docs/04-deploiement.md` §« Déployer » | Lancer `./scripts/deploy.sh --check`, puis `./scripts/deploy.sh` |
| 7 | `docs/06-developper-en-local.md` | **Chemin application uniquement** : mettre en place la base de développement. Pour un site de contenu, `npm run dev` suffit — il n'y a pas de base.
| 8 | `docs/09-captcha.md` | Facultatif : anti-robots sur la connexion (chemin application) |
| — | `docs/08-workers-et-emails.md` | À lire si l'utilisateur parle de Workers ou d'e-mails |
| — | `docs/05-pannes.md` | À lire **seulement** si quelque chose échoue |

**Deux chemins existent, et le choix se fait dans `DECIDE.md` :**

| Chemin | Squelette | `kind` dans `deploy.config.json` |
|---|---|---|
| Application — utilisateurs connectés, tableau de bord, outil interne | `templates/app/` | `"app"` (défaut) |
| Contenu — site vitrine, blog, documentation | `templates/content/` | `"content"` |

**N'adapte jamais le chemin application pour servir un site vitrine.** Celui-ci
n'a besoin ni de base de données ni d'authentification ; les lui imposer ajoute
une surface d'attaque, un conteneur à surveiller et une sauvegarde à gérer,
pour rien. À l'inverse, si le service demande une connexion, c'est le chemin
application — ne bricole pas une authentification par-dessus un site statique.

Sur le chemin contenu, appuie-toi sur la documentation officielle d'Astro
(<https://docs.astro.build>) plutôt que sur ta mémoire : les versions récentes
ont bougé sur les collections de contenu et la configuration.

**Tu ne peux ni ouvrir un compte chez un hébergeur, ni saisir une carte
bancaire, ni passer une vérification d'identité ou un CAPTCHA.** Ces étapes
reviennent à l'utilisateur. Demande-lui un jeton d'API : avec lui, tu crées et
détruis les serveurs toi-même. Voir `docs/00-creer-un-serveur.md`.

**Docker n'est pas nécessaire sur la machine de l'utilisateur.** Il ne sert que
sur le serveur : la construction de l'image a lieu à distance, par SSH. Ne le
faites pas installer en local, et ne le réclamez pas comme prérequis.

---

## 3. Interdits

Ces règles ne sont pas des préférences de style. Chacune correspond à une panne
déjà rencontrée en production.

- **N'invente jamais un fichier de configuration Caddy.** Utilise
  `infra/caddy/site.example.caddy`, ou laisse `scripts/deploy.sh` le générer.
- **Ne modifie jamais `/etc/caddy/Caddyfile` sur le serveur.** Il ne contient
  qu'un `import /etc/caddy/sites/*.caddy`. Chaque projet dépose son propre
  fichier dans `sites/`. Toucher au fichier central casse les autres sites.
- **Ne nomme jamais un conteneur Postgres `db`.** Toujours `<projet>-db`. Le
  réseau Docker est partagé : un service `db` peut résoudre vers la base d'un
  autre projet, ce qui provoque des erreurs d'authentification **intermittentes**,
  très difficiles à diagnostiquer.
- **Ne publie jamais un port autrement que sur `127.0.0.1`.** Écrire
  `"5432:5432"` expose la base sur Internet.
- **Ne committe jamais un fichier `.env` rempli.** Lance
  `scripts/check-secrets.py` avant tout commit.
- **Ne devine jamais une valeur que l'utilisateur possède** : nom de domaine,
  adresse IP, accès SSH, identifiants d'un service tiers. Si l'une manque,
  arrête-toi et demande-la.
- **En revanche, génère toi-même les secrets techniques** — mot de passe de la
  base, secret d'authentification — avec `openssl rand -base64 32`, et
  inscris-les dans le `.env`. Ne demande jamais à l'utilisateur d'inventer un
  mot de passe : il en choisirait un faible, et ce n'est pas son travail.
- **N'ajoute jamais au `docker-compose.yml` une clause `privileged`, `cap_add`,
  `devices`, `network_mode: host`, `user: 0`, ni un montage d'un chemin de
  l'hôte.** Le compose est exécuté par un service Docker root : ces directives
  donnent au conteneur un accès complet au serveur. `deploy.sh` refuse de
  déployer un compose qui en contient.
- **Ne mets jamais la base de données sur le réseau `web`.** Il est partagé
  entre tous les projets du serveur ; la base doit rester sur son réseau
  `interne`, joignable uniquement par son application.
- **Ne passe jamais un mot de passe en argument de commande.** Il serait visible
  dans `ps` et conservé dans l'historique du shell. Utilise `scripts/create-user.sh`,
  qui le lit sur l'entrée standard.
- **Ne contourne jamais un accès manquant.** Si le SSH échoue, si le domaine
  n'est pas délégué, si une clé API est absente : arrête-toi et explique ce
  qu'il faut fournir. Ne cherche pas de solution de repli.

---

## 4. Vérifier après chaque étape

N'annonce jamais qu'une étape a réussi sans avoir lancé sa commande de contrôle
et lu sa sortie.

| Après | Commande | Sortie attendue |
|---|---|---|
| Préparation du serveur | `ssh <vps> 'docker ps && caddy version'` | la liste des conteneurs, puis une version de Caddy |
| Configuration du domaine | `dig +short <domaine>` | l'IP du serveur, ou une IP Cloudflare si le proxy est actif |
| Avant de déployer | `./scripts/deploy.sh --check` | `tout est en place, rien n'a été déployé` |
| Après le déploiement — chemin application | `curl -s https://<domaine>/api/health` | `{"ok":true}` |
| Après le déploiement — chemin contenu | `curl -o /dev/null -w '%{http_code}' https://<domaine>/` | `200` |
| Avant tout commit | `python3 scripts/check-secrets.py .` | `OK : aucun secret detecte.` |
| Après avoir modifié `scripts/` ou `infra/` | `./tests/run-all.sh` | `Toutes les verifications sont vertes.` |

Si une commande ne renvoie pas la sortie attendue : **arrête-toi**, lis
`docs/05-pannes.md`, et rapporte ce que tu as observé. N'enchaîne pas.

Un déploiement qui affiche « réussi » n'est pas une preuve suffisante. Le seul
critère est la réponse du site depuis l'extérieur, ce que fait la vérification
de santé — et elle seule a détecté que Caddy n'était jamais rechargé.

---

## 5. Ce que contient ce dépôt

```
CLAUDE.md            ce fichier — à lire en premier
DECIDE.md            quel chemin choisir selon le projet
docs/                les étapes, plus les pannes connues
templates/app/       squelette application (TanStack Start, Postgres, auth)
templates/content/   squelette site de contenu (Astro) + 22 docs de référence
infra/               modèles Docker, Caddy, configuration de déploiement
scripts/             préparation du serveur, déploiement, GitHub, garde-fous
tests/               toutes les vérifications — `./tests/run-all.sh`
```

Le squelette `templates/app/` contient son propre `AGENTS.md`, généré par la
CLI TanStack : lis-le pour les questions de code applicatif (routes, requêtes,
composants). Le présent fichier traite du déploiement et de l'infrastructure.

---

## 6. Ce dépôt est fourni tel quel

Aucun support n'est garanti. Si quelque chose ne fonctionne pas et que
`docs/05-pannes.md` ne couvre pas le cas, dis-le clairement à l'utilisateur
plutôt que d'improviser une solution que personne ne pourra maintenir.

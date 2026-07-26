# agent-vibe-code-stack-starter

Un dépôt qu'on donne à son agent de code pour qu'il mette une application en
ligne tout seul : serveur, domaine, HTTPS, base de données, authentification,
déploiement.

## À qui ça s'adresse

À ceux qui savent déjà construire une application avec une IA, et qui butent sur
l'étape d'après : la mettre en ligne pour de vrai, sur leur domaine, et la
remettre debout quand elle tombe.

## Comment on s'en sert

Donnez l'URL de ce dépôt à votre agent :

```
Voici un repo : https://github.com/quentintou/agent-vibe-code-stack-starter
Monte-moi un tableau de bord interne avec connexion et une base de données.
```

L'agent lit `CLAUDE.md`, vous pose quelques questions, puis exécute. Il s'arrête
et vous demande dès qu'un accès lui manque.

## Voir le résultat

Deux démonstrations en ligne, déployées par ce dépôt :

- **<https://contenu.app-run.pro>** — chemin *contenu* : la vitrine du projet,
  un site Astro statique qui décrit le dépôt qui l'a déployé
- **<https://stack.app-run.pro>** — chemin *application* : un tableau de bord
  d'équipe avec connexion et base de données. Sa page d'accueil propose une
  **visite guidée** : quatre boutons qui envoient de vraies requêtes au serveur
  et affichent la réponse — inscription fermée, session exigée, base joignable,
  fichiers statiques servis. Aucun compte nécessaire pour l'essayer.

Les deux tournent sur le même serveur, avec le **même script** de déploiement.
Leurs configurations diffèrent par le domaine, le nom du projet et le champ
`kind` — mais c'est bien `deploy.sh` qui distingue les deux chemins. Le code des
deux démonstrations est dans `demos/`.

## Ce qu'il vous faut

- un serveur (VPS) chez n'importe quel hébergeur, environ 5 € par mois
- un nom de domaine
- un compte Cloudflare (gratuit) pour le domaine et le HTTPS
- `git`, `node` 22+, `python3`, `ssh`, `rsync`, `curl`, `dig`, `openssl` et
  `gh` sur votre machine — la liste exacte, avec les commandes de vérification,
  est dans `docs/01-prerequis.md`
- **pas besoin de Docker en local** : l'image est construite sur le serveur

## La stack

| Couche | Choix |
|---|---|
| Application | TanStack Start, React 19, Tailwind 4 |
| Site de contenu | Astro 7, statique, servi par Caddy |
| Base de données | Postgres 17, Drizzle |
| Authentification | better-auth, auto-hébergée |
| Exécution | Docker Compose |
| Entrée HTTPS | Caddy, un fichier de configuration par site |
| Domaine (DNS), anti-robots | Cloudflare (Turnstile facultatif) |
| Certificat HTTPS | Caddy, auprès de Let's Encrypt |
| Code source | GitHub, dépôt privé par défaut |
| Déploiement | un fichier `deploy.config.json`, un script |

**Deux chemins seulement** : application (utilisateurs connectés) ou contenu
(site vitrine, blog). Un seul chemin par besoin, volontairement. Moins de choix, moins de façons de se
tromper — et un agent qui hésite moins.

## Ce que ça règle et qu'on ne trouve pas ailleurs

- Le build de TanStack Start ne produit pas de serveur qui écoute : lancé
  directement, il s'arrête sans message. `server.mjs` règle ça.
- Un conteneur Postgres nommé `db` sur un serveur partagé provoque des erreurs
  d'authentification intermittentes. Le déploiement refuse cette configuration.
- Le déploiement échoue bruyamment si la base est injoignable, au lieu de mettre
  en ligne un site qui renvoie des erreurs en silence.
- Un garde-fou anti-secrets qui ne crie pas sur les fichiers d'exemple — donc
  qu'on ne finit pas par désactiver. Il tourne **avant** la création du dépôt
  GitHub : une clé poussée reste dans l'historique et doit être révoquée.
- Le rechargement du serveur web est vérifié, pas supposé : un déploiement qui
  s'annonce réussi alors que rien n'écoute est une panne réelle, rencontrée.
- Le chemin contenu est cadré : plan du site et liens canoniques vérifiés au
  déploiement, pages supprimées réellement retirées, aucune base à surveiller.

## Contribuer

Les recettes sont les bienvenues : un cas d'usage, un fichier, dans `docs/recipes/`.
C'est additif, ça n'entre en conflit avec rien.

Merci d'éviter les modifications du socle (`scripts/`, `infra/`) sans en avoir
discuté d'abord — c'est ce qui doit rester simple et prévisible.

## Licence et support

MIT. **Fourni tel quel, sans garantie de support.** Les contributions sont
bienvenues, les demandes de dépannage individuel ne recevront pas forcément de
réponse.

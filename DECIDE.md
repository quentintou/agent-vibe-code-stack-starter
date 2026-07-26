# Quel chemin choisir

Deux chemins seulement. Ce n'est pas une limite du dépôt, c'est un choix : moins
d'options, moins de manières de se tromper.

---

## Le choix en une question

> Ton projet sert-il surtout à **afficher du contenu**, ou à faire **travailler
> des utilisateurs connectés** ?

| Réponse | Chemin | Ce qu'on installe |
|---|---|---|
| Afficher du contenu — site vitrine, blog, pages publiques, documentation | **Contenu** | Astro, pages générées à l'avance, servies par Caddy |
| Faire travailler des utilisateurs — tableau de bord, outil interne, application, espace client | **Application** | TanStack Start, Postgres, better-auth |

En cas d'hésitation : s'il faut se connecter pour utiliser le service, c'est le
chemin Application.

> Les deux chemins sont livrés. N'adapte jamais le chemin Application pour
> servir un site vitrine : celui-ci n'a besoin ni de base de données ni
> d'authentification, et les lui imposer ajoute une surface d'attaque, un
> conteneur à surveiller et une sauvegarde à gérer, pour rien.

---

## Trois questions de confirmation

**« Des données doivent-elles survivre au redémarrage ? »**
Oui → Postgres, inclus dans le chemin Application.
Non → un site de contenu suffit probablement.

**« Faut-il se connecter pour utiliser le service ? »**
Oui → chemin Application. L'authentification est incluse : ne la rajoute pas
par-dessus autre chose.

**« Des tâches doivent-elles tourner en continu ou à heure fixe ? »**
Oui → un serveur est indispensable. Ce point est traité plus bas.

---

## Où l'hébergement sans serveur ne suffit plus

Cloudflare Pages, Netlify ou Vercel suffisent pour beaucoup de sites, et ils sont
gratuits. Si l'utilisateur n'a qu'un site vitrine et rien d'autre, dis-le-lui
franchement : ce dépôt ne lui apportera pas grand-chose.

**Ce dépôt ne déploie pas chez eux.** Son chemin contenu construit le site et le
sert depuis le serveur de l'utilisateur, à côté de ses autres projets. C'est
utile dans deux cas : quand il a déjà un serveur et veut tout regrouper, et
quand il publie beaucoup de pages — dix sites sur une machine à 5 € coûtent
moins cher et se déploient de la même façon que le reste.

Ils ne suffisent plus dès que le projet a besoin d'une de ces choses :

- **une base de données classique qui persiste** — Postgres avec un disque, pas
  seulement un service tiers facturé à la requête ;
- **un traitement qui dure** plus de quelques dizaines de secondes — import,
  génération de fichier, appel à un modèle qui répond lentement ;
- **une tâche planifiée** qui tourne toutes les nuits ;
- **un processus qui reste allumé** — un robot, une file d'attente, une connexion
  permanente ;
- **des outils qu'on installe soi-même**, hors du catalogue de l'hébergeur.

Un tableau de bord interne, un outil métier ou un espace client tombent presque
toujours dans cette catégorie. D'où le serveur.

### Ce que Cloudflare fait quand même, dans les deux cas

Cloudflare gère le **domaine** (les enregistrements DNS), et propose en option
la protection contre les abus, les formulaires anti-robots (Turnstile), la
redirection d'e-mails et **l'envoi** de courrier depuis l'application. Gratuit
pour ces usages, l'envoi vers des tiers mis à part.

**Le certificat HTTPS, lui, est obtenu par Caddy** sur le serveur, directement
auprès de Let's Encrypt. C'est pour cela que le proxy Cloudflare doit rester
désactivé au premier déploiement : activé, il intercepte la vérification et le
certificat n'est jamais délivré. Voir `docs/03-cloudflare.md`.

**Le code applicatif ne tourne pas sur les Cloudflare Workers.** C'est un choix
de périmètre, pas un oubli : base persistante, traitements longs, tâches à heure
fixe, et la possibilité de changer d'hébergeur sans rien réécrire.

Les Workers restent le bon outil pour rediriger en périphérie et exposer un
petit point d'entrée sans état, et cohabitent sans difficulté avec le serveur.
**L'envoi d'e-mails n'en fait pas partie** : l'application appelle directement
Cloudflare Email Sending, sans Worker intermédiaire — c'est fourni dans le
squelette. `docs/08-workers-et-emails.md` détaille où passe la frontière. Si
l'utilisateur demande du Workers, lis-lui ce document plutôt que de refuser ou
d'improviser.

---

## Une fois le chemin choisi

Reviens à `CLAUDE.md`, section « Ordre des étapes », et suis-la sans en sauter.

# Où s'arrête Cloudflare — Workers et e-mails

Cloudflare fait beaucoup de choses. Ce dépôt n'en utilise qu'une partie, et ce
document dit laquelle, pourquoi, et où sont les limites.

| Service Cloudflare | Utilisé ici ? | Pour quoi |
|---|---|---|
| DNS | oui | faire pointer le domaine vers le serveur |
| Certificats / proxy | oui | HTTPS, protection contre les abus |
| Turnstile | oui, facultatif | anti-robots sur la connexion (`docs/09-captcha.md`) |
| Email Routing | oui, facultatif | **recevoir** du courrier sur le domaine |
| Workers | **non** pour le code applicatif | voir ci-dessous |
| R2, D1, KV, Pages | non | le serveur suffit |

---

## Pourquoi le code ne tourne pas sur les Workers

Les Workers exécutent du code à la périphérie du réseau, sans serveur à gérer.
C'est excellent — pour ce à quoi c'est fait. Ce dépôt vise autre chose : un
outil interne, un tableau de bord, un petit logiciel métier. Quatre besoins de
ce type s'accommodent mal du modèle des Workers :

1. **Une base de données persistante.** Postgres tourne à côté de
   l'application, sur le même réseau privé. Depuis un Worker, chaque requête
   traverse Internet et demande un service de base compatible.
2. **Des traitements longs.** Générer un export, traiter un fichier, appeler un
   modèle : un Worker est fait pour répondre vite.
3. **Un processus résident.** Une tâche à heure fixe, une file d'attente, une
   connexion maintenue.
4. **Pouvoir partir.** L'application est une image Docker standard. Elle tourne
   à l'identique sur n'importe quel serveur Linux. Rien n'est à réécrire pour
   changer d'hébergeur.

Ce n'est pas une critique des Workers, c'est un choix de périmètre. Un dépôt qui
prétend faire les deux fait mal les deux.

## Quand les Workers sont le bon outil

Ils le restent, et ils cohabitent très bien avec ce qui est décrit ici. Trois
cas où les prendre :

- **Envoyer des e-mails depuis le domaine** (voir la section suivante) ;
- **Rediriger en périphérie** : anciennes URLs, redirections marketing, tests
  A/B — sans réveiller le serveur ;
- **Un petit point d'entrée sans état** : un webhook qui reçoit et transmet, un
  proxy vers une API tierce pour ne pas exposer une clé.

Dans ces trois cas, le Worker est une pièce à côté de l'application, pas à sa
place. Ce dépôt ne le déploie pas pour vous — il ne prétend pas couvrir ce
terrain.

---

## Recevoir du courrier : Email Routing

Gratuit, et suffisant pour un formulaire de contact ou une adresse
`contact@mondomaine.fr` qui arrive dans votre boîte habituelle.

### Mise en place

1. `dash.cloudflare.com` → votre domaine → **Email** → **Email Routing** →
   **Get started**.
2. Cloudflare propose de poser les enregistrements **MX** et **TXT**
   nécessaires. Accepter.
3. Déclarer l'adresse de **destination** — votre vraie boîte. Cloudflare y
   envoie un lien de confirmation.
   **L'agent ne peut pas cliquer sur ce lien** : il arrive dans votre boîte
   personnelle. C'est à vous de le faire.
4. Créer les redirections : `contact@mondomaine.fr` → `vous@votre-boite.fr`.
5. Facultatif : une règle **attrape-tout** pour que toute adresse du domaine
   arrive au même endroit.

### Vérifier

```bash
dig +short MX mondomaine.fr
```

Attendu : trois enregistrements `mx*.cloudflare.net`.

Puis envoyer un message de test à l'adresse créée, depuis une autre boîte.

### L'avertissement à ne pas manquer

**Si le domaine recevait déjà du courrier avant la bascule vers Cloudflare, ses
enregistrements MX doivent être recopiés.** Sans cela, tout le courrier du
domaine s'arrête au moment où les serveurs de noms changent — et personne ne
s'en aperçoit avant plusieurs jours, parce qu'un message qui n'arrive pas ne
produit aucune erreur visible.

Voir `docs/03-cloudflare.md`, qui traite la bascule des serveurs de noms.

---

## Envoyer du courrier : ce n'est pas la même chose

Email Routing **reçoit et redirige**. Il n'envoie pas.

Pour qu'une application envoie des messages — confirmation de compte,
réinitialisation de mot de passe, notification — il faut autre chose. Deux
chemins, aucun n'est fourni par ce dépôt :

- **Un Worker** avec l'API `send_email` de Cloudflare, autorisé à écrire vers
  une adresse vérifiée. Gratuit, mais limité aux destinataires déclarés — bien
  pour se notifier soi-même, pas pour écrire à des clients.
- **Un service d'envoi** (Resend, Postmark, Scaleway, Brevo…) avec une clé API
  posée dans le `.env`. C'est ce qu'il faut dès qu'on écrit à des tiers, parce
  qu'il faut soigner SPF, DKIM et DMARC pour ne pas finir en indésirables.

Dans les deux cas, **la clé d'envoi est un secret** : elle va dans le `.env` du
serveur, jamais dans le dépôt. Le garde-fou anti-secrets la refusera de
lui-même si elle s'y glisse.

Le squelette d'application livré ici ne dépend d'aucun envoi d'e-mail : la
création de compte se fait en ligne de commande (`docs/05-pannes.md`, panne
n°10), justement pour ne pas imposer ce choix.

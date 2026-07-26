# Où s'arrête Cloudflare — Workers et e-mails

Cloudflare fait beaucoup de choses. Ce dépôt n'en utilise qu'une partie, et ce
document dit laquelle, pourquoi, et où sont les limites.

| Service Cloudflare | Utilisé ici ? | Pour quoi |
|---|---|---|
| DNS | oui | faire pointer le domaine vers le serveur |
| Certificats / proxy | oui | HTTPS, protection contre les abus |
| Turnstile | oui, facultatif | anti-robots sur la connexion (`docs/09-captcha.md`) |
| Email Routing | oui, facultatif | **recevoir** du courrier sur le domaine |
| Email Sending | oui, facultatif | **envoyer** du courrier depuis l'application |
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

## Envoyer du courrier

Email Routing **reçoit et redirige**. Il n'envoie pas. C'est un autre produit du
même service, **Email Sending**, et il est fourni dans ce dépôt.

Le squelette expose `src/lib/mail.ts` :

```ts
import { envoyerMail } from '#/lib/mail'

const resultat = await envoyerMail({
  to: 'quelquun@exemple.fr',
  subject: 'Votre demande a été enregistrée',
  text: 'Merci, nous revenons vers vous sous 24 h.',
})
```

Sans configuration, l'envoi est inactif : la fonction journalise le message et
retourne `{ ok: false }`. L'application démarre et fonctionne — la création de
compte se fait en ligne de commande, précisément pour ne dépendre d'aucun envoi.

### Pourquoi Cloudflare plutôt qu'un service d'envoi

Le domaine est déjà chez Cloudflare pour le DNS et le certificat. Onboarder le
domaine dans Email Sending pose seul **SPF, DKIM et DMARC** — les trois
enregistrements qu'on oublie et qui font finir en indésirables. Un compte de
moins, une facture de moins, une clé de moins à faire tourner.

Resend, Postmark ou Brevo restent de bons produits. Ils ne sont simplement plus
nécessaires pour envoyer depuis un serveur.

### Mise en place

1. **Onboarder le domaine.** Tableau de bord Cloudflare > **Compute** > **Email
   Service** > **Email Sending** > **Onboard Domain**. Choisir le domaine,
   relire les enregistrements proposés, valider. Cloudflare pose MX, SPF, DKIM
   et DMARC ; propagation de 5 à 15 minutes sur un domaine en DNS Cloudflare.
2. **Créer le jeton.** Mon profil > Jetons d'API, permission
   **`Email Sending: Edit`**. C'est un secret : il va dans le `.env` du serveur,
   jamais dans le dépôt — le garde-fou anti-secrets le refusera de lui-même.
3. **Renseigner le `.env`** : `CF_EMAIL_ACCOUNT_ID`, `CF_EMAIL_API_TOKEN`,
   `MAIL_FROM` (et `MAIL_FROM_NAME` si vous voulez un nom affiché).

Les trois premières vont **ensemble**. En renseigner une ou deux fait échouer le
démarrage, volontairement : une configuration à moitié faite ne se découvre
autrement que le jour du premier message, en production.

### Le prix, et ce qui est gratuit

| | |
|---|---|
| Vers les adresses de destination **vérifiées de votre compte** | gratuit, tous plans |
| Vers **n'importe quel destinataire** | plan Workers Paid |
| Inclus avec ce plan | 3 000 messages par mois |
| Au-delà | 0,35 $ par millier |
| Taille maximale d'un message | 5 Mio, pièces jointes comprises |

Autrement dit : se notifier soi-même — une alerte, un formulaire de contact qui
vous prévient — ne coûte rien. Écrire à vos utilisateurs demande le plan payant.

Le service est en **bêta** : la soumission SMTP authentifiée date de juin 2026.
Pour un outil interne c'est sans conséquence ; pour un envoi critique, prévoyez
de pouvoir en changer.

### Le vérifier, sur le serveur

Écrire du code d'envoi ne prouve pas qu'un message part. Le squelette fournit
l'outil qui le prouve :

```bash
docker compose exec -T app node tester-email.mjs vous@exemple.fr
```

Il envoie un vrai message et affiche la réponse brute de Cloudflare. Les causes
d'échec les plus fréquentes sont nommées dans la sortie — domaine non onboardé,
jeton sans la bonne permission, destinataire non vérifié sur un plan gratuit.

**« Accepté » n'est pas « distribué ».** Une réponse en succès ressemble à ça :

```json
{"success":true,"result":{"message_id":"<…@votredomaine.fr>",
 "delivered":[],"queued":[],"permanent_bounces":[]}}
```

Les trois listes peuvent être **vides** alors que le message part et arrive
très bien. Ne cherchez pas à en tirer un verdict : allez regarder la boîte du
destinataire, **et son dossier indésirables** — c'est le seul contrôle qui
prouve quelque chose.

Deux pièges rencontrés en écrivant ce document, l'un et l'autre invisibles à la
relecture :

- L'API répond parfois **HTTP 200 avec `success: false`**. Le module et l'outil
  lisent donc le corps, jamais le seul code de statut.
- Le schéma attend des **objets**, pas des chaînes. `from: "Nom <a@b.fr>"` et
  `to: "a@b.fr"` font répondre `400 invalid_request_schema`. La bonne forme est
  `from: { address, name }` et `to: [{ address }]`.

### Si vous préférez le SMTP

Le même service accepte le SMTP, utile pour brancher un outil existant qui ne
sait parler que ce protocole :

| | |
|---|---|
| Hôte | `smtp.mx.cloudflare.net` |
| Port | `465`, TLS implicite |
| Utilisateur | la chaîne littérale `api_token` |
| Mot de passe | le jeton d'API |

Ni STARTTLS sur 587, ni relais sur 25. Ce dépôt utilise l'API REST, qui se fait
avec `fetch` et n'ajoute donc aucune dépendance.

### Une note sur la délivrabilité

Un message accepté par Cloudflare, correctement signé, peut malgré tout être
filtré à l'arrivée — c'est fréquent avec un domaine neuf, et avec les
destinataires à filtrage sévère (hôpitaux, banques, administrations). Si le
message compte vraiment, prévoyez un second canal plutôt que de supposer qu'il
est arrivé.

**Soignez `MAIL_FROM_NAME`.** En validant ce document, trois messages sont
partis du même domaine à une minute d'intervalle, avec la même authentification.
Les deux dont le nom affiché était `Starter` sont arrivés en boîte de réception.
Le troisième, nommé `Starter — test d'envoi`, est arrivé **en indésirables** —
tiret cadratin et apostrophe dans le nom affiché.

Un seul cas ne fait pas une règle, et rien ne prouve que la ponctuation soit
la cause. Mais la conclusion pratique tient : un nom d'expéditeur court et sans
fantaisie typographique ne coûte rien, et **le contrôle d'arrivée doit inclure
le dossier indésirables** — sans quoi ce message-là aurait été compté comme
perdu.

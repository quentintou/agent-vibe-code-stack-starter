# 0. Créer un serveur

À lire seulement si l'utilisateur n'a pas encore de serveur. S'il en a un, passer
directement à `docs/02-vps.md`.

---

## Ce qu'un agent peut faire, et ce qu'il ne peut pas

C'est la première chose à dire à l'utilisateur, pour éviter dix minutes d'allers-retours.

**L'agent ne peut pas :** créer le compte chez l'hébergeur, saisir une carte
bancaire, passer une vérification d'identité, ni résoudre un CAPTCHA. Ce sont
des étapes délibérément réservées à un humain.

**L'agent peut, dès qu'il a un jeton d'API :** créer le serveur, choisir
l'image et la région, déposer la clé SSH, récupérer l'adresse IP, détruire la
machine, et recommencer autant de fois que nécessaire.

La bonne répartition est donc : **l'utilisateur ouvre le compte et fournit un
jeton d'API ; l'agent fait tout le reste.** Demandez-lui explicitement ce
jeton, ne tentez pas de contourner l'inscription.

---

## Le piège qui coûte une soirée

Chez plusieurs hébergeurs, un compte tout neuf doit passer une **vérification
d'identité avant de pouvoir créer sa première machine**. C'est documenté, mais
la plupart des gens le découvrent au mauvais moment.

C'est particulièrement fréquent chez Hetzner pour les comptes ouverts hors
d'Allemagne ou avec certains moyens de paiement, et le délai peut atteindre
plusieurs heures.

**Conséquence pratique :** si l'utilisateur n'a aucun compte, faites-lui ouvrir
le compte **en premier**, avant même de parler du projet. Pendant la
vérification, le reste peut avancer (domaine, code, base locale).

---

## Comparatif, sous l'angle du pilotage par agent

| | Hetzner Cloud | DigitalOcean | OVHcloud |
|---|---|---|---|
| Outil en ligne de commande | `hcloud` (officiel) | `doctl` (officiel) | API REST, CLI moins centrale |
| Authentification API | un jeton | un jeton | trois clés (application, secret, consumer) |
| Création d'une machine | quelques secondes | moins d'une minute | plus lente |
| Facturation | à l'heure, plafonnée au mois | à l'heure, affichée au mois | à l'heure, granularité à la minute |
| Ordre de prix, 2 vCPU / 4 Go | ~8 €/mois | ~24 $/mois | ~33 $/mois |
| Entrée de gamme | ~4 €/mois | ~4 $/mois | plus élevée |
| Vérification à l'ouverture | fréquente, parfois longue | carte bancaire, rapide | variable |
| Confort de la documentation | correct | le meilleur des trois | le plus dense |

**Recommandation par défaut : Hetzner**, pour le rapport prix/simplicité et
parce qu'un jeton unique suffit à tout piloter. **DigitalOcean** si
l'utilisateur veut la mise en route la plus lisse et accepte de payer trois
fois plus. **OVHcloud** si l'hébergement en France ou chez un acteur français
est une contrainte imposée — son authentification à trois clés est plus lourde
à faire manipuler par un agent.

Les tarifs bougent (Hetzner a augmenté ses prix en avril 2026). Vérifiez la
page publique de l'hébergeur avant d'annoncer un montant à l'utilisateur.

---

## Option A — Hetzner Cloud

**Ce que l'utilisateur fait** (une fois) : ouvrir un compte sur
<https://console.hetzner.com>, passer la vérification si elle est demandée,
créer un projet, puis générer un jeton API dans *Security → API tokens*, avec
les droits **Read & Write**. Il vous transmet ce jeton.

> Chez Hetzner, un jeton d'API est **rattaché à un projet** et ne voit que
> celui-ci. Et l'API Cloud ne permet pas de créer un projet : `/v1/projects`
> répond `404 api route not found` (vérifié). La création d'un projet passe
> obligatoirement par la console web.
>
> Conséquence : **demandez un jeton créé dans un projet dédié**, jamais celui
> d'un projet qui contient déjà des serveurs en production. Un jeton en écriture
> peut supprimer n'importe quelle machine de son projet.

**Ce que l'agent fait** :

```bash
# Installation du client officiel
brew install hcloud            # macOS
# ou : voir https://github.com/hetznercloud/cli

export HCLOUD_TOKEN='<jeton fourni par l utilisateur>'

# Déposer la clé SSH publique de l'utilisateur
hcloud ssh-key create --name <nom-de-votre-cle> --public-key-from-file ~/.ssh/id_ed25519.pub

# Créer le serveur (image Debian, région allemande, offre d'entrée)
hcloud server create --name mon-projet --image debian-12 \
  --type cx23 --location nbg1 --ssh-key <nom-de-votre-cle>

# Récupérer l'adresse IP
hcloud server ip mon-projet
```

Si l'utilisateur n'a pas de clé SSH :

```bash
ssh-keygen -t ed25519 -C "mon-projet" -f ~/.ssh/id_ed25519 -N ''
```

Détruire le serveur (utile après un test) : `hcloud server delete mon-projet`.

---

## Option B — DigitalOcean

**Ce que l'utilisateur fait** : ouvrir un compte sur
<https://cloud.digitalocean.com>, enregistrer un moyen de paiement, puis créer
un jeton dans *API → Generate New Token*, en lecture **et** écriture.

**Ce que l'agent fait** :

```bash
brew install doctl                       # macOS
doctl auth init                          # demande le jeton

doctl compute ssh-key import <nom-de-votre-cle> --public-key-file ~/.ssh/id_ed25519.pub

doctl compute droplet create mon-projet \
  --image debian-12-x64 --size s-1vcpu-2gb --region fra1 \
  --ssh-keys "$(doctl compute ssh-key list --format ID --no-header | head -1)"

doctl compute droplet get mon-projet --format PublicIPv4
```

Suppression : `doctl compute droplet delete mon-projet`.

---

## Option C — OVHcloud

**Ce que l'utilisateur fait** : ouvrir un compte sur <https://ovhcloud.com>,
créer un projet Public Cloud, puis générer un trio de clés d'API sur
<https://api.ovh.com/createToken/> — clé d'application, clé secrète et clé de
consommateur — avec les droits d'écriture sur `/cloud/*`.

L'API OVHcloud est complète, mais son authentification à trois clés et ses
identifiants de projet la rendent plus lourde à faire manipuler par un agent
que les deux options précédentes. À réserver aux cas où l'hébergement chez un
acteur français est une exigence.

Dans ce cas, le plus simple reste que l'utilisateur crée l'instance depuis
l'interface web (image Debian 12, la plus petite offre) et vous transmette
l'adresse IP et l'accès SSH. Le reste du déploiement est identique.

---

## Après la création, dans tous les cas

```bash
ssh root@<adresse-ip> 'echo ok'
```

Attendu : `ok`. Puis continuer avec `docs/02-vps.md`.

---

> **Ce document n'a pas encore été éprouvé de bout en bout par un agent partant
> réellement de zéro.** Les commandes proviennent de la documentation officielle
> de chaque hébergeur, pas d'une exécution vérifiée dans ce dépôt. Si l'une
> d'elles échoue, ne l'adaptez pas au jugé : signalez-le à l'utilisateur et
> ouvrez une issue.

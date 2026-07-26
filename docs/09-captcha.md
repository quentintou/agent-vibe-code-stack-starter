# Anti-robots sur la connexion — Cloudflare Turnstile

Facultatif. L'application fonctionne sans. À activer quand le formulaire de
connexion est exposé publiquement, c'est-à-dire dès que le domaine est connu.

Ce que ça protège : le **bourrage d'identifiants**, où un robot essaie des
milliers de couples e-mail / mot de passe volés ailleurs. Le mot de passe fort
d'un utilisateur ne le protège pas des tentatives sur les comptes des autres.

Ce que ça ne protège pas : rien d'autre. Ce n'est ni un pare-feu, ni une
limitation de débit, ni un remplacement de l'inscription fermée.

---

## 1. Créer les clés

Sur `dash.cloudflare.com` → **Turnstile** → **Add site**.

- **Domain** : le domaine du site, sans `https://`
- **Widget mode** : `Managed` (Cloudflare décide seul quand poser une question)

Cloudflare affiche alors deux clés :

| Clé | Où elle va | Est-ce un secret ? |
|---|---|---|
| **Site Key** | `VITE_TURNSTILE_SITE_KEY` | Non — elle est envoyée au navigateur |
| **Secret Key** | `TURNSTILE_SECRET_KEY` | **Oui** — jamais dans le code client |

L'agent ne peut pas créer ces clés : elles demandent un compte Cloudflare
connecté. C'est à l'utilisateur de les produire et de les transmettre.

## 2. Les poser

Dans le `.env` de production (jamais dans le dépôt) :

```
VITE_TURNSTILE_SITE_KEY=0x4AAAAAAA...
TURNSTILE_SECRET_KEY=0x4AAAAAAA...
```

Puis redéployer : `./scripts/deploy.sh`

**Les deux clés vont ensemble.** N'en définir qu'une seule ne sert à rien :
- clé publique seule → le widget s'affiche, le serveur ne vérifie rien ;
- clé secrète seule → le serveur exige un jeton que personne n'envoie, **plus
  aucune connexion ne passe**.

## 3. Vérifier

Sans jeton, l'API doit refuser :

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -X POST https://<domaine>/api/auth/sign-in/email \
  -H 'Content-Type: application/json' \
  -d '{"email":"vous@exemple.fr","password":"<votre mot de passe>"}'
```

- Turnstile **actif** → un code d'erreur, jamais 200. C'est le résultat attendu :
  une requête sans navigateur n'a pas de jeton.
- Turnstile **inactif** → 200. Les clés ne sont pas prises en compte : vérifier
  qu'elles sont bien dans le `.env` du serveur et que le déploiement a eu lieu.

Puis dans un navigateur : le widget doit apparaître au-dessus du bouton, et la
connexion doit fonctionner normalement.

## 4. Comment c'est câblé

Côté serveur, `src/lib/auth.ts` ajoute le greffon officiel de better-auth **si
et seulement si** la clé secrète existe :

```ts
const cleTurnstile = process.env.TURNSTILE_SECRET_KEY
const pluginsCaptcha = cleTurnstile
  ? [captcha({ provider: 'cloudflare-turnstile', secretKey: cleTurnstile })]
  : []
```

Côté navigateur, `src/lib/turnstile.tsx` applique la même règle avec la clé
publique : sans elle, le composant ne rend rien et le script Cloudflare n'est
même pas inclus dans le code envoyé.

Le jeton voyage dans l'en-tête `x-captcha-response`. better-auth le vérifie
auprès de Cloudflare avant de toucher à la base.

---

## Pannes

**« Plus personne ne peut se connecter après avoir ajouté les clés. »**
La clé secrète est définie mais pas la clé publique : le serveur exige un jeton
que le navigateur n'envoie pas. Poser les deux, ou retirer les deux.

**« La deuxième tentative échoue toujours. »**
Un jeton Turnstile ne sert **qu'une fois**. Le formulaire doit remettre le
widget à zéro après chaque envoi — c'est ce que fait `reinitCaptcha` dans la
page de connexion. Si vous écrivez votre propre formulaire, ne l'oubliez pas.

**« Le widget ne s'affiche pas. »**
Le domaine déclaré dans Turnstile ne correspond pas à celui du site. Cloudflare
refuse alors de rendre le widget, silencieusement. Vérifier dans la console du
navigateur.

**« Ça marche en local mais pas en ligne. »**
`VITE_TURNSTILE_SITE_KEY` est lue **au moment de la construction**, pas au
démarrage. Ajouter la clé au `.env` du serveur ne suffit pas : il faut
reconstruire, donc relancer `./scripts/deploy.sh`.

## Clés de test

Cloudflare fournit des clés qui réussissent ou échouent toujours, utiles pour
vérifier le câblage sans compte : voir la documentation Turnstile, section
*Testing*. `1x00000000000000000000AA` (site) passe toujours.

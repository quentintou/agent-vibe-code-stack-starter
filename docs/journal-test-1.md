# Journal du test à blanc n°1 — 2026-07-26

Premier déploiement de bout en bout sur une machine réellement vierge.

**Conditions.** Machine neuve à 5 € par mois (Debian 12, 4 Go), créée pour
l'occasion et détruite depuis. Domaine géré chez Cloudflare, DNS sans proxy
pour laisser Caddy obtenir son certificat. Aucune préparation manuelle.

**Résultat final.** Application en ligne en HTTPS, base migrée, compte créé,
connexion fonctionnelle, inscription publique fermée et vérifiée.

**Résultat honnête.** Sept défauts, dont **trois rendaient l'application
inutilisable alors que le déploiement s'annonçait réussi**. Aucun n'avait été
vu par la relecture, ni par l'audit adverse de deux modèles. Seule l'exécution
réelle les a révélés.

---

## Les défauts, par gravité

### 1. L'authentification n'était branchée sur aucune base

`betterAuth()` généré par l'add-on de la CLI TanStack **ne définit aucun
`database`**. better-auth bascule alors sur un stockage en mémoire : aucune
table n'est jamais créée, et les comptes disparaissent à chaque redémarrage.

Symptôme observé : l'application se déploie, répond en HTTPS, et toute tentative
de connexion renvoie `401` — sans message exploitable.

Correctif : `database: drizzleAdapter(db, { provider: 'pg' })`.

### 2. Aucune migration n'était générée ni appliquée

Le template n'avait pas de dossier `drizzle/`, et `deploy.sh` ne lançait aucune
migration. La base restait entièrement vide.

Correctif : génération du schéma d'authentification par la CLI better-auth,
réexport depuis `schema.ts` (sans quoi drizzle-kit ne le voit pas), génération
des migrations, embarquement de `drizzle/` et `migrate.mjs` dans l'image, et
application par `deploy.sh` **avant** le contrôle de santé.

### 3. Le contrôle de santé donnait une fausse assurance

`/api/health` exécutait `select 1`, qui **réussit sur une base sans le moindre
schéma**. Le déploiement affichait donc « réussi » sur une application
incapable de servir une seule requête réelle.

C'est le défaut le plus instructif du lot : un contrôle qui ne peut pas échouer
est pire qu'aucun contrôle, parce qu'il inspire confiance.

Correctif : la requête porte désormais sur une vraie table.

### 4. Le script d'installation bloquait sur une machine neuve

`bootstrap-vps.sh` refusait de continuer en trouvant une configuration Caddy
« existante ». Or le paquet Debian de Caddy installe un fichier d'exemple
contenant un bloc `:80 { }`. La protection anti-écrasement, ajoutée après
l'audit adverse, était trop large et bloquait le cas le plus courant.

Correctif : ne considérer comme configuration réelle qu'un bloc dont l'en-tête
contient un nom de domaine.

### 5. La création du premier compte était impossible

`package.json` déclarait `npm run create-user`, mais l'image de production ne
contient ni les sources ni les scripts — seulement le build. L'inscription
étant fermée par défaut, **aucun compte ne pouvait exister** : site en ligne,
personne ne peut entrer.

Correctif : un `scripts/create-user.sh` côté starter, qui ouvre l'inscription
quelques secondes, crée le compte, la referme et **vérifie** qu'elle l'est.

### 6. `set -e` tuait le script d'attente

`curl … | grep -q … && break` : quand la condition échoue — c'est-à-dire à
chaque tour tant que l'application redémarre — la liste échoue et `set -e`
interrompt le script. Il s'arrêtait silencieusement au premier tour.

Correctif : `if … then break; fi`.

### 7. Nom de service confondu avec nom de conteneur

`docker compose up <nom>` attend un nom de **service**, pas un `container_name`.
L'erreur `no such service` interrompait le script **après** l'ouverture de
l'inscription : le service restait ouvert aux inscriptions.

Le filet a fonctionné — le `trap` a refermé — mais l'incident montre que toute
étape ouvrant une brèche doit la refermer même en cas d'échec, et le vérifier.

---

## Ce que le test a confirmé

- `bootstrap-vps.sh` installe Docker 29.6.2 et Caddy 2.11.4 sur Debian 12 vierge
- Le fragment Caddy par site fonctionne, certificat Let's Encrypt obtenu
- Redirection HTTP → HTTPS en 308
- `deploy.sh` refuse bien de déployer sur configuration fautive
- L'inscription publique est fermée, et le reste après création de compte
- `cx23` et `debian-12` sont les bons identifiants Hetzner ; `brew install hcloud` fonctionne

## Ce que le test n'a PAS couvert

- **L'ouverture d'un compte chez un hébergeur**, avec sa vérification d'identité.
  Le jeton utilisé appartenait à un compte déjà vérifié. C'est précisément
  l'étape où un débutant bloque.
- **La bascule des serveurs de noms** vers Cloudflare : le domaine y était déjà.
- **Le chemin contenu (Astro)**, pas encore écrit.
- **Un agent partant réellement de l'URL du dépôt.** Ce test a été mené par un
  agent qui connaissait le dépôt pour l'avoir écrit. Le vrai test reste à faire.

## Enseignement principal

Sur sept défauts, **trois produisaient un déploiement qui s'annonçait réussi
tout en étant inutilisable**. Une relecture attentive et deux audits adverses
ne les avaient pas vus, parce qu'ils ne se manifestent qu'à l'exécution.

La leçon vaut au-delà de ce dépôt : ce qui n'a pas tourné n'est pas vérifié.

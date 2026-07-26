# Journal du test à blanc n°3 — 2026-07-26

Premier déploiement du **chemin contenu** (Astro statique), sur le serveur qui
héberge déjà l'application. Deux questions : le chemin contenu fonctionne-t-il,
et le chemin application a-t-il survécu à la bifurcation de `deploy.sh` ?

**Conditions.** Même serveur, second domaine, DNS sans proxy. Le projet est une
copie de `templates/content/`, comme le ferait un utilisateur, plus un
`deploy.config.json` de sept lignes en `kind: "content"`.

**Résultat.** Déploiement réussi du premier coup. Trois défauts trouvés ensuite,
dont un qui rendait le site inutilisable pour ce à quoi il sert.

---

## 1. Le site publiait un domaine d'exemple (grave pour un site de contenu)

Le déploiement s'est annoncé réussi, les cinq pages répondaient 200. Mais :

```xml
<loc>https://exemple.fr/</loc>
<link rel="canonical" href="https://exemple.fr/">
```

Le sitemap et les liens canoniques annonçaient le domaine d'exemple. Un moteur
de recherche ignore un tel sitemap, et le lien canonique attribue le contenu à
un autre site. **Un site de contenu qui n'est pas indexable ne remplit pas sa
fonction** — et rien n'échouait : la page répondait bien 200.

**Cause.** `astro.config.mjs` lit `PUBLIC_SITE_URL` avec une valeur de repli.
Sans `.env`, le repli s'appliquait.

**Correctif.** `deploy.sh` impose `PUBLIC_SITE_URL=https://<domaine>` au
conteneur de construction. Le domaine est dans la configuration de déploiement ;
le demander une seconde fois n'a pas de sens, et un site statique n'a aucune
raison d'annoncer un domaine autre que celui sur lequel il est servi.

Un contrôle refuse désormais de publier si `exemple.fr` subsiste dans le HTML ou
le XML produit.

## 2. Les pages supprimées restaient en ligne

`dist/` est exclu du rsync — c'est un produit de construction, pas une source.
Conséquence : le `dist/` de la construction **précédente** survivait sur le
serveur. Une page retirée du projet restait publiée indéfiniment.

Vérifié en conditions réelles : une page ajoutée puis supprimée passait de 200
à… 200. Après correctif (`rm -rf src/dist` avant construction) : 6 pages, puis
5 pages, et l'URL retirée répond 404.

## 3. Un `.env` retiré de la configuration restait actif sur le serveur

Si un projet déclarait un `secrets_file` puis cessait de le faire, le `.env`
déposé lors du déploiement précédent restait sur le serveur et continuait
d'être injecté à chaque construction. Des clés retirées de la configuration
restaient donc actives, sans aucun moyen de s'en apercevoir depuis la machine
de l'utilisateur.

`deploy.sh` supprime maintenant tout `.env` résiduel quand aucun secret n'est
déclaré.

---

## Ce que l'audit adverse a apporté avant l'exécution

Deux défauts trouvés par relecture adverse (Codex), avant tout déploiement :

**`configs:` et `secrets:` contournaient le contrôle de compose.** Le
contrôleur n'examinait que `volumes:`. Or ces deux blocs acceptent `file:` et
copient n'importe quel fichier de l'hôte dans le conteneur — clé SSH,
`/etc/shadow`. `env_file` et `build.context` posaient le même problème. Les
quatre sont désormais contrôlés, en distinguant un chemin relatif au projet
(légitime) d'un chemin absolu ou remontant.

**Caddy suit les liens symboliques.** Un lien déposé dans le site construit et
pointant hors du dossier serait servi publiquement. Le déploiement refuse
désormais de publier dans ce cas.

Note : le rapport final de Codex a été **bloqué par son propre filtre de
sécurité** au moment de la rédaction — un audit de sécurité ressemble, vu de
loin, à une préparation d'attaque. Les défauts ci-dessus proviennent de sa
phase d'analyse, qui elle est passée. Une seconde passe formulée en termes de
non-régression n'a pas été bloquée.

## Non-régression du chemin application

C'était le risque principal de ce lot. Après tous les correctifs, redéploiement
complet de l'application :

| Contrôle | Résultat |
|---|---|
| Contrôle du compose | `compose sûr` |
| Migrations | appliquées |
| `/api/health` | `{"ok":true}` |
| Connexion d'un compte existant | HTTP 200 |
| Site de contenu, en parallèle | toutes pages 200 |
| Fragments Caddy | 3, un par site, aucun conflit |

Deux sites de nature différente, un seul serveur, un seul script.

---

## Ce que ce test ajoute à la méthode

Les tests n°1 et n°2 avaient établi qu'un déploiement doit être vérifié depuis
l'extérieur, et qu'il faut partir d'une table rase. Celui-ci ajoute une nuance :

**« La page répond 200 » n'est pas le bon critère de succès pour tout type de
projet.** Pour une application, l'endpoint de santé interroge la base : c'est un
vrai signal. Pour un site de contenu, un 200 ne dit rien de ce qui compte —
l'indexabilité, la fraîcheur, l'absence de pages fantômes.

Le contrôle de santé doit porter sur ce qui définit la réussite du projet, pas
sur ce qui est le plus facile à mesurer.

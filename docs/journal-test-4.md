# Journal du test à blanc n°4 — 2026-07-26

Le seul test jamais fait : **suivre la documentation**, et rien d'autre.

Les trois premiers tests ont déployé le dépôt en s'appuyant sur la connaissance
du code. Celui-ci part d'un clone frais et n'exécute que les commandes écrites
dans les documents. Tout ce qui bloque est un défaut réel.

Ce test s'imposait : l'audit de cohérence, quelques heures plus tôt, avait
trouvé que `docs/04-deploiement.md` était **inexécutable** — il demandait de
copier `infra/` et `scripts/` depuis un dossier où ils n'existent pas. Le
document avait été corrigé en le relisant, pas en le lançant.

**Conditions.** `gh repo clone`, dossier vide, et surtout **un serveur déjà
occupé** — condition décisive, c'est elle qui a révélé le défaut n°1. Un
sous-domaine a été créé pour l'occasion, puis détruit avec le déploiement.

**Résultat.** Deux défauts, dont un bloquant. Les deux chemins passent après
correction.

---

## 1. La préparation du serveur refusait un serveur pourtant conforme

**Symptôme.**

```
ARRÊT : /etc/caddy/Caddyfile contient l'import ET d'autres directives.
  Fusionner à la main, puis relancer.
```

Le serveur remplissait pourtant toutes les conditions : la ligne d'import était
présente, les dossiers existaient, le réseau Docker aussi.

**Cause.** Le script exigeait que le fichier de configuration central contienne
**exactement** la ligne d'import, et rien d'autre. Le besoin réel est qu'il la
**contienne**. Toute machine hébergeant déjà quelque chose — c'est-à-dire tout
serveur au deuxième projet — était bloquée, avec une consigne impossible à
suivre : il n'y avait rien à fusionner.

**Portée.** Ce défaut fermait la porte à l'un des trois profils que le dépôt
prétend servir : « j'ai déjà un serveur et je veux structurer ».

**Correctif.** Trois cas explicites, et un message juste pour chacun :

| État du fichier | Comportement |
|---|---|
| absent | on écrit la ligne d'import |
| contient déjà l'import | **on ne touche à rien** |
| autre configuration, sans import | arrêt, avec la ligne exacte à ajouter |

Le message d'arrêt ne demande plus de découper la configuration existante : il
dit d'**ajouter une ligne**, ce qui ne met aucun site hors ligne.

Effet de bord constaté : deux sauvegardes inutiles s'étaient accumulées sur le
serveur, une par tentative.

## 2. Deux instructions en désaccord avec leurs propres commandes

- `docker-compose.yml` gardait un espace réservé `DB_PORT` en commentaire, que
  la documentation ne demandait pas de remplacer — il ne correspond plus à rien
  depuis que le port de la base n'est plus publié.
- Le chemin contenu affirmait que le dossier de références Astro était inutile
  dans le projet, mais la commande fournie le copiait quand même : 308 Ko
  embarqués sans raison. La commande le retire désormais.

---

## Ce que le test a validé

| Étape | Résultat |
|---|---|
| Prérequis (9 commandes) | toutes présentes et exécutées |
| Préparation du serveur | conforme après correctif, production intacte |
| Domaine, sans proxy | certificat obtenu par Caddy en direct |
| Mise en place, chemin application | les 5 commandes passent |
| Déploiement | base, migrations, mise en service, santé, fichiers statiques |
| Création de compte | compte créé, inscription publique confirmée fermée |
| Connexion | HTTP 200 |
| Mise en place, chemin contenu | les 6 commandes passent, 5 pages construites |

Le déploiement complet est passé **d'un trait**, sans intervention hors
documentation.

---

## Ce que ce test ajoute à la méthode

Les trois précédents avaient établi qu'il faut vérifier depuis l'extérieur,
partir d'une table rase, et que « la page répond » n'est pas un critère de
réussite. Celui-ci ajoute la règle la plus simple, et la plus facile à oublier :

**Écrire une procédure ne la vérifie pas. Il faut la suivre.**

Le document corrigé quelques heures plus tôt était devenu *plausible*. Il
restait faux sur un point que seule l'exécution pouvait révéler — et le défaut
bloquant trouvé ici ne se déclenche que sur un serveur qui héberge déjà quelque
chose, donc jamais dans un test parti de zéro.

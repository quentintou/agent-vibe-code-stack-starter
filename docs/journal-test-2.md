# Journal du test à blanc n°2 — 2026-07-26

Rejeu complet après les corrections de sécurité, sur **table rase**. Le premier
test avait laissé un serveur déjà configuré ; ce second test repart de zéro pour
éprouver le chemin qu'emprunte réellement un nouvel utilisateur.

**Conditions.** Même machine, mais destruction préalable des conteneurs, du
volume de données, du répertoire de déploiement et du fragment Caddy. Site
confirmé hors ligne avant de relancer (`Connection reset by peer`).

**Résultat.** Trois défauts trouvés, dont un grave que ni la relecture ni les
deux audits adverses n'avaient vu. Tous corrigés et revérifiés en ligne.

---

## Ce que le rejeu à froid a trouvé

### 1. Caddy n'était jamais rechargé — le site ne montait pas (grave)

**Symptôme.** `deploy.sh` affichait « Migrations appliquées », puis la
vérification de santé échouait. Sur le serveur, l'application répondait 200 en
local et le fragment Caddy était bien en place.

**Constat.** Fragment écrit à 12:56:07 ; dernier rechargement de Caddy à
12:55:52, quinze secondes plus tôt. Configuration chargée : `{}`. Aucun port 443
en écoute.

**Cause.** Le bloc distant est envoyé à `bash -s` par **l'entrée standard**.
`docker compose exec -T` transmet cette même entrée au conteneur, qui a donc
consommé tout le reste du script. Bash a atteint la fin du fichier et est sorti
avec le **code 0** : `caddy validate`, `systemctl reload caddy` et
`docker compose ps` n'ont jamais été exécutés, sans le moindre message.

Signe révélateur, visible dès le premier test si on l'avait cherché : le tableau
`NAME / STATUS` de `docker compose ps` n'apparaissait pas dans la sortie.

**Correctifs.** `< /dev/null` sur la commande fautive ; contrôle que Caddy écoute
réellement sur 443 après rechargement ; et un marqueur de fin de bloc distant,
dont l'absence fait échouer le déploiement. Documenté en panne n°11.

**Pourquoi les audits l'ont manqué.** Les deux audits lisaient le code à la
recherche de failles de sécurité. Ce défaut n'en est pas une : c'est une
interaction entre le transport du script et une commande qu'il contient. Seule
une exécution sur un serveur sans configuration Caddy préexistante le révèle —
au deuxième déploiement, Caddy tourne déjà avec la bonne configuration et le
défaut reste invisible.

### 2. Boucle ACME infinie sur le sous-domaine `www`

`deploy.sh` générait systématiquement un bloc `www.<domaine>`. Sans
enregistrement DNS correspondant, Let's Encrypt refuse le certificat, Caddy
réessaie toutes les vingt minutes et finit par basculer sur son autorité de
secours — ce qui consomme le quota du domaine.

Le bloc n'est désormais ajouté que si `www.<domaine>` résout réellement.
Documenté en panne n°12.

### 3. `create-user.sh` n'était pas exécutable dans le dépôt

Enregistré en `100644` alors que la documentation l'appelle
`./scripts/create-user.sh`. Un clone frais butait sur `permission denied`. Défaut
invisible tant qu'on travaille sur une copie dont on a soi-même corrigé les
droits — il n'est apparu qu'en recopiant les scripts depuis le dépôt.

Corrigé, et un contrôle vérifie maintenant que tout script de `scripts/`,
`tests/` et `.githooks/` est exécutable.

---

## Vérifié en ligne après correction

| Contrôle | Résultat |
|---|---|
| Accueil et santé | HTTP 200, `{"ok":true}` |
| Redirection HTTP → HTTPS | 308 |
| En-têtes de sécurité | `nosniff`, `strict-origin-when-cross-origin`, `Server` supprimé |
| Port de la base en écoute | 0 |
| Port applicatif exposé hors `127.0.0.1` | 0 |
| Base joignable depuis le réseau partagé | isolée |
| Alias DNS `db` sur le réseau partagé | absent |
| Mot de passe visible dans `ps` | 0 processus |
| `.env` sur le serveur | `600 root:root` |
| Fichier de secrets copié par rsync | absent |
| Inscription publique | HTTP 400 + message du hook |
| Création de compte puis connexion | HTTP 200, cookie de session posé |
| Énumération de comptes | fermée (401 identique dans les deux cas) |
| Erreurs ACME après correction | 0 |

---

## Ce que ce test change dans la méthode

Le premier test avait déjà montré que sept défauts survivaient aux deux audits
et ne tombaient qu'à l'exécution réelle. Celui-ci ajoute une nuance : **rejouer
sur un système déjà en état de marche ne prouve rien**. Les trois défauts
ci-dessus étaient tous masqués par un état résiduel — une configuration Caddy
déjà chargée, des droits de fichiers déjà corrigés à la main.

La règle qui en découle : un test de déploiement ne compte que s'il part d'une
table rase, et la table rase doit être **vérifiée** avant de commencer, pas
supposée.

Les deux séries de contournements découverts par les audits sont désormais des
tests versionnés (`tests/test-verifier-compose.py`, `tests/test-injections.sh`),
lancés avec le reste par `./tests/run-all.sh`.

#!/usr/bin/env bash
# Déploiement générique piloté par deploy.config.json, à lancer depuis la
# racine du projet à déployer (pas depuis le starter).
#
#   ./deploy.sh            déploie
#   ./deploy.sh --check    vérifie les accès sans rien déployer
#
# Le script échoue bruyamment et refuse d'agir en cas de doute : un déploiement
# interrompu vaut mieux qu'un site en ligne qui sert des erreurs en silence, et
# mieux encore qu'un répertoire effacé par une faute de frappe dans un fichier
# de configuration.
set -euo pipefail

CFG="${DEPLOY_CONFIG:-deploy.config.json}"
CHECK_ONLY=false
[ "${1:-}" = "--check" ] && CHECK_ONLY=true

if [ ! -f "$CFG" ]; then
  echo "ERREUR : $CFG introuvable."
  echo "Lancer ce script depuis la racine du projet, après avoir copié"
  echo "infra/deploy.config.example.json en deploy.config.json."
  exit 1
fi

# Lecture du JSON. Le chemin passe par argv, jamais par interpolation dans le
# source Python : une apostrophe dans le nom de fichier casserait le programme.
cfg() { # cfg <cle.pointee> [valeur par defaut si la cle est absente]
  python3 -c '
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
try:
    for key in sys.argv[2].split("."):
        data = data[key]
except (KeyError, TypeError, IndexError):
    if len(sys.argv) > 3:
        print(sys.argv[3]); sys.exit(0)
    sys.exit(f"ERREUR : cle « {sys.argv[2]} » absente de {sys.argv[1]}")
print(data)
' "$CFG" "$1" ${2+"$2"}
}

# Type de projet. « app » par defaut : les fichiers de configuration ecrits
# avant l'existence du chemin contenu ne declarent pas cette cle et doivent
# continuer de fonctionner sans modification.
KIND=$(cfg kind app)
case "$KIND" in
  app|content) ;;
  *) echo "ERREUR : kind « $KIND » inconnu dans $CFG."
     echo "  Valeurs acceptées : « app » (TanStack + Postgres) ou « content » (Astro statique)."
     exit 1 ;;
esac

PROJECT=$(cfg project)
VPS=$(cfg vps.host)
APP_DIR=$(cfg app.dir "/opt/apps/$PROJECT")
DOMAIN=$(cfg domain)
# `secrets_file` reste OBLIGATOIRE pour une application : sans lui il n'y a ni
# base ni secret d'authentification. Le rendre optionnel produisait un message
# d'erreur absurde — « fichier de secrets «  » introuvable » — au lieu de dire
# quelle cle manque.
if [ "$KIND" = app ]; then
  SECRETS=$(cfg secrets_file)
else
  SECRETS=$(cfg secrets_file "")
fi

# Champs propres au chemin application. Sur un site de contenu il n'y a ni
# image Docker, ni base, ni port applicatif : on leur donne des valeurs
# inertes qui passent la validation sans jamais servir.
if [ "$KIND" = app ]; then
  IMAGE=$(cfg app.image_name)
  DB_CONTAINER=$(cfg app.db_container)
  APP_PORT=$(cfg app.app_port)
  HEALTH=$(cfg health_url)
else
  IMAGE="sans-objet"; DB_CONTAINER="sans-objet"; APP_PORT="0"
  # Un site statique n'a pas d'endpoint de sante : on interroge sa page d'accueil.
  HEALTH=$(cfg health_url "https://$DOMAIN/")
fi

# --- Validation stricte des valeurs de configuration ------------------------
# Toutes ces valeurs finissent dans une commande distante ou dans un chemin de
# fichier. Sans liste blanche, un « ; » ou un « $(…) » dans le JSON s'exécute
# sur le serveur, et un « ../ » dans le nom de projet écrit hors du dossier
# prévu. On valide avant tout, plutôt que d'échapper après coup.
# La validation passe par Python et `re.fullmatch` : `grep -E "^motif$"` teste
# LIGNE PAR LIGNE, donc une valeur contenant un saut de ligne — « demo\n;id;# » —
# franchit le controle puis atteint le shell distant. Verifie.
valide() { # valide <nom> <valeur> <motif> <explication>
  if ! python3 -c '
import re, sys
sys.exit(0 if re.fullmatch(sys.argv[1], sys.argv[2], re.DOTALL) else 1)
' "$3" "$2"; then
    echo "ERREUR : $1 invalide dans $CFG : « $2 »"
    echo "  $4"
    exit 1
  fi
}

valide "project"          "$PROJECT"      '[a-z0-9][a-z0-9-]{0,38}'         "minuscules, chiffres et tirets uniquement"
if [ "$KIND" = app ]; then
  valide "app.image_name"   "$IMAGE"        '[a-z0-9][a-z0-9._-]{0,63}'     "minuscules, chiffres, . _ -"
  valide "app.db_container" "$DB_CONTAINER" '[a-z0-9][a-z0-9._-]{0,63}'     "minuscules, chiffres, . _ -"
  valide "app.app_port"     "$APP_PORT"     '[0-9]{2,5}'                    "un numéro de port"
fi
valide "domain"           "$DOMAIN"       '[a-z0-9][a-z0-9.-]{2,252}[a-z]'  "un nom de domaine, sans espace ni caractère spécial"
valide "vps.host"         "$VPS"          '[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+' "utilisateur@hôte"
valide "health_url"       "$HEALTH"       'https://[a-zA-Z0-9./_-]+'        "une URL https, jamais file:// ni http://"

# Le controle de sante doit interroger CE site : une URL tierce renvoyant
# {"ok":true} donnerait un succes sur un deploiement casse.
case "$HEALTH" in
  "https://$DOMAIN"/*) ;;
  *) echo "ERREUR : health_url doit commencer par https://$DOMAIN/ (trouvé « $HEALTH »)."
     exit 1 ;;
esac

# Le répertoire de déploiement est imposé, pas libre : c'est lui qui subit le
# rsync --delete. Une faute de frappe ne doit pas pouvoir viser /etc ou /home.
ATTENDU="/opt/apps/$PROJECT"
if [ "$APP_DIR" != "$ATTENDU" ]; then
  echo "ERREUR : app.dir doit valoir exactement « $ATTENDU » (trouvé « $APP_DIR »)."
  echo "  Ce répertoire est effacé et recréé à chaque déploiement : il ne peut"
  echo "  pas être choisi librement."
  exit 1
fi

echo "=== Déploiement de $PROJECT sur $DOMAIN ==="

# --- Vérifications préalables ----------------------------------------------
# Un site de contenu n'a pas forcement de secrets : il se construit et se sert
# sans base ni cle. Le fichier reste accepte s'il existe (variables PUBLIC_*).
if [ "$KIND" = app ] || [ -n "$SECRETS" ]; then
  if [ ! -f "$SECRETS" ]; then
    echo "ERREUR : fichier de secrets « $SECRETS » introuvable."
    echo "Copier .env.example en $SECRETS et le remplir. Ne jamais le committer."
    exit 1
  fi

  if grep -qE 'CHANGE_ME|changeme' "$SECRETS"; then
    echo "ERREUR : $SECRETS contient encore des valeurs CHANGE_ME."
    exit 1
  fi
fi

if [ "$KIND" = app ]; then
  if ! grep -qE '^DATABASE_URL=' "$SECRETS"; then
    echo "ERREUR : DATABASE_URL absente de $SECRETS."
    echo "  Elle doit être complète, mot de passe déjà encodé (docs/04-deploiement.md)."
    exit 1
  fi

  if grep -qE '^DATABASE_URL=.*@db:' "$SECRETS"; then
    echo "ERREUR : DATABASE_URL pointe l'alias « db »."
    echo "  Sur un serveur partagé, cet alias peut résoudre vers le Postgres d'un"
    echo "  AUTRE projet : erreurs d'authentification intermittentes."
    echo "  Utiliser « $DB_CONTAINER ». Voir docs/05-pannes.md."
    exit 1
  fi
fi

echo "-- Accès SSH..."
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$VPS" "echo ok" >/dev/null \
  || { echo "ERREUR : connexion SSH à $VPS impossible."; exit 1; }

echo "-- État du serveur..."
ssh "$VPS" bash -s <<'REMOTE' || { echo "ERREUR : serveur non préparé. Lancer scripts/bootstrap-vps.sh."; exit 1; }
set -e
command -v docker >/dev/null || { echo "docker absent"; exit 1; }
command -v caddy  >/dev/null || { echo "caddy absent"; exit 1; }
docker network inspect web >/dev/null 2>&1 || { echo "reseau 'web' absent"; exit 1; }
[ -d /etc/caddy/sites ] || { echo "/etc/caddy/sites absent"; exit 1; }
REMOTE

# Le répertoire cible doit être vide ou déjà géré par ce script. On refuse
# d'appliquer --delete à un dossier dont on ignore l'origine.
echo "-- Répertoire de déploiement..."
ssh "$VPS" "PROJECT=$(printf '%q' "$PROJECT") bash -s" <<'REMOTE'
set -euo pipefail
DIR="/opt/apps/$PROJECT"
if [ -e "$DIR" ] && [ ! -f "$DIR/.starter-managed" ]; then
  echo "ERREUR : $DIR existe mais n'a pas ete cree par ce script."
  echo "  Refus d'y appliquer rsync --delete. Le deplacer ou le supprimer"
  echo "  manuellement apres verification."
  exit 1
fi
mkdir -p "$DIR/src"
: > "$DIR/.starter-managed"
REMOTE

if $CHECK_ONLY; then
  echo "=== --check : tout est en place, rien n'a été déployé. ==="
  exit 0
fi

# --- Synchronisation --------------------------------------------------------
# Verrou par projet : deux deploiements simultanes melangeraient sources,
# secrets et migrations.
#
# `flock` pose dans une commande ssh distincte NE VERROUILLE RIEN : le verrou
# est relache a la fermeture de la connexion, donc avant meme le premier rsync.
# On utilise `mkdir`, qui est atomique et dont l'effet SURVIT a la connexion.
# Le verrou est retire par le piege de sortie, quel que soit le chemin de fin.
VERROU="/var/lock/starter-$PROJECT.lock.d"
if ! ssh "$VPS" "V=$(printf '%q' "$VERROU")
  if mkdir \"\$V\" 2>/dev/null; then date -u +%FT%TZ > \"\$V/depuis\"; exit 0; fi
  # Un verrou de plus d'une heure vient d'un deploiement interrompu : on le reprend.
  if [ -n \"\$(find \"\$V\" -maxdepth 0 -mmin +60 2>/dev/null)\" ]; then
    rm -rf \"\$V\" && mkdir \"\$V\" && date -u +%FT%TZ > \"\$V/depuis\" && exit 0
  fi
  exit 1"; then
  echo "ERREUR : un déploiement de « $PROJECT » est déjà en cours sur le serveur."
  echo "  Attendre sa fin, ou supprimer $VERROU s'il est resté bloqué."
  exit 1
fi
# Le verrou doit tomber même si le script échoue ou est interrompu.
trap 'ssh "$VPS" "rm -rf $(printf '"'"'%q'"'"' "$VERROU")" >/dev/null 2>&1 || true' EXIT

echo "-- Envoi des sources..."
# Le fichier de secrets est exclu par son nom reel : un `secrets_file` appele
# autrement que .env* serait sinon envoye en clair, puis copie dans les couches
# de l'image Docker par le `COPY . .` du Dockerfile.
EXCLUSION_SECRETS=()
[ -n "$SECRETS" ] && EXCLUSION_SECRETS=(--exclude "$(basename "$SECRETS")")
rsync -az --delete \
  --exclude node_modules --exclude .git --exclude dist --exclude .output \
  --exclude '.env' --exclude '.env.*' --exclude secrets \
  "${EXCLUSION_SECRETS[@]}" \
  ./ "$VPS:$APP_DIR/src/"

# Les secrets ne transitent pas par scp : le fichier existerait un instant en
# 0644, lisible par les autres comptes du serveur.
if [ -n "$SECRETS" ]; then
  # Le fichier a ete verifie plus haut. S'il a disparu depuis, on ARRETE.
  # Tomber dans la branche « aucun secret declare » effacerait le .env de
  # production et laisserait l'application redemarrer sans base de donnees.
  if [ ! -f "$SECRETS" ]; then
    echo "ERREUR : « $SECRETS » a disparu depuis la vérification."
    echo "  Le .env du serveur n'a pas été touché. Rien n'a été déployé."
    exit 1
  fi
  echo "-- Envoi des secrets..."
  # umask ne s'applique qu'a la creation : un .env preexistant en 0644 garderait
  # ses permissions. On ecrit dans un fichier temporaire puis on deplace.
  ssh "$VPS" "umask 077; T=\$(mktemp $(printf '%q' "$APP_DIR")/.env.XXXXXX) && \
              cat > \"\$T\" && chmod 600 \"\$T\" && \
              mv \"\$T\" $(printf '%q' "$APP_DIR/.env")" < "$SECRETS"
else
  # Aucun secret declare : on retire celui qui resterait d'un deploiement
  # precedent. Sans cela, un .env oublie sur le serveur continuerait d'etre
  # injecte a chaque construction — des cles retirees de la configuration
  # resteraient actives, invisibles depuis la machine de l'utilisateur.
  echo "-- Pas de fichier de secrets déclaré : suppression de tout .env résiduel."
  ssh "$VPS" "rm -f $(printf '%q' "$APP_DIR/.env")"
fi

# --- Fragment Caddy ---------------------------------------------------------
# Écriture atomique : on envoie sous .new, on valide, puis seulement on
# remplace. Un fragment invalide en place empêcherait tout rechargement de
# Caddy — y compris pour les autres sites du serveur.
echo "-- Configuration Caddy ($DOMAIN)..."
FRAGMENT=$(mktemp)
if [ "$KIND" = app ]; then
  cat > "$FRAGMENT" <<EOF
$DOMAIN {
	encode gzip zstd
	header {
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}
	reverse_proxy 127.0.0.1:$APP_PORT {
		header_up X-Real-IP {remote_host}
	}
}
EOF
else
  # Site statique : Caddy sert les fichiers directement, aucun processus ne
  # tourne. Le dossier « public » est produit par la construction et remplacé
  # d'un bloc à chaque déploiement — jamais modifié en place.
  cat > "$FRAGMENT" <<EOF
$DOMAIN {
	encode gzip zstd
	header {
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}
	root * $APP_DIR/public
	file_server

	handle_errors {
		rewrite * /404.html
		file_server
	}
}
EOF
fi

# La redirection « www » n'est ajoutee que si l'enregistrement DNS existe.
# Declarer un domaine qui ne resout pas met Caddy en echec ACME permanent :
# il redemande un certificat toutes les 20 minutes, echoue, et finit par etre
# bascule sur l'autorite de secours de Let's Encrypt. Constate le 2026-07-26.
if python3 -c '
import socket, sys
try:
    socket.getaddrinfo(sys.argv[1], None)
except OSError:
    sys.exit(1)
' "www.$DOMAIN" 2>/dev/null; then
  cat >> "$FRAGMENT" <<EOF

www.$DOMAIN {
	redir https://$DOMAIN{uri} permanent
}
EOF
  echo "   redirection www.$DOMAIN ajoutée (enregistrement DNS trouvé)."
else
  echo "   pas d'enregistrement DNS pour www.$DOMAIN : redirection non ajoutée."
  echo "   (créer le CNAME puis relancer si vous la souhaitez)"
fi
ssh "$VPS" "umask 022; cat > /etc/caddy/sites/$(printf '%q' "$PROJECT").caddy.new" < "$FRAGMENT"
rm -f "$FRAGMENT"

ssh "$VPS" "PROJECT=$(printf '%q' "$PROJECT") bash -s" <<'REMOTE'
set -euo pipefail
SITE="/etc/caddy/sites/$PROJECT.caddy"
# Validation du fichier complet, fragment candidat inclus, dans un dossier isolé.
TMPDIR_C=$(mktemp -d)
cp /etc/caddy/sites/*.caddy "$TMPDIR_C"/ 2>/dev/null || true
rm -f "$TMPDIR_C/$PROJECT.caddy"
cp "$SITE.new" "$TMPDIR_C/$PROJECT.caddy"
printf 'import %s/*.caddy\n' "$TMPDIR_C" > "$TMPDIR_C/Caddyfile"
if ! caddy validate --config "$TMPDIR_C/Caddyfile" --adapter caddyfile >/dev/null 2>&1; then
  rm -rf "$TMPDIR_C" "$SITE.new"
  echo "ERREUR : le fragment Caddy genere est invalide. Rien n'a ete modifie."
  exit 1
fi
rm -rf "$TMPDIR_C"
[ -f "$SITE" ] && cp "$SITE" "$SITE.bak"
mv "$SITE.new" "$SITE"
REMOTE

# --- Contrôle du fichier compose --------------------------------------------
# Le compose est exécuté par un daemon Docker root. Un fichier déclarant
# `volumes: /:/host`, `privileged: true` ou le socket Docker donne un accès
# complet au serveur. On refuse ces clauses avant de le lui confier.
# Analyse SEMANTIQUE du YAML, pas une recherche de motifs : « privileged : true »
# avec une espace, « user: root » au lieu de « user: 0 », ou la syntaxe longue
# d'un montage (type: bind / source: /) echappent a tout grep.
if [ "$KIND" = app ]; then
  echo "-- Contrôle du fichier compose..."
  ICI="$(cd "$(dirname "$0")" && pwd)"
  VERIFIEUR="$ICI/verifier-compose.py"
  if [ ! -f "$VERIFIEUR" ]; then
    echo "ERREUR : $VERIFIEUR introuvable."
    echo "  Copier le dossier scripts/ en entier, pas seulement deploy.sh."
    exit 1
  fi
  if ! python3 "$VERIFIEUR" docker-compose.yml; then
    echo
    echo "  Ces directives donneraient au conteneur un accès privilégié au serveur."
    echo "  Si l'une est réellement nécessaire, déployez à la main après revue."
    exit 1
  fi
fi

# --- Build et démarrage -----------------------------------------------------
echo "-- Build et démarrage sur le serveur..."
# La sortie est conservee pour verifier que le bloc distant s'est execute
# JUSQU'A LA FIN. Un script envoye par l'entree standard peut etre tronque en
# silence par toute commande qui lit cette meme entree ; bash sort alors avec
# le code 0 et les dernieres etapes sont simplement sautees.
SORTIE_DISTANTE=$(mktemp)
ssh "$VPS" "KIND=$(printf '%q' "$KIND") DOMAIN=$(printf '%q' "$DOMAIN") APP_DIR=$(printf '%q' "$APP_DIR") IMAGE=$(printf '%q' "$IMAGE") DB_CONTAINER=$(printf '%q' "$DB_CONTAINER") bash -s" <<'REMOTE' | tee "$SORTIE_DISTANTE" | sed '/__BLOC_DISTANT_TERMINE__/d'
set -euo pipefail

# Toutes les commandes ci-dessous qui lisent l'entree standard portent
# « < /dev/null ». Ce n'est PAS decoratif : ce script est envoye a `bash -s`
# par l'entree standard, et toute commande qui la lit avale le reste du script.
# Bash sort alors avec le code 0 et les etapes suivantes — dont le rechargement
# de Caddy — ne s'executent jamais, sans le moindre message.
# Constate en conditions reelles le 2026-07-26.

if [ "$KIND" = content ]; then
  # --- Site statique : on construit dans un conteneur jetable ---------------
  # Node n'est pas installe sur le serveur et n'a pas a l'etre : Docker y est
  # deja, et le serveur reste propre. Le conteneur disparait apres la
  # construction ; seul le dossier « public » en sort.
  echo "   construction du site (conteneur jetable)..."
  # `dist/` est exclu du rsync : le dossier produit par la construction
  # PRECEDENTE survit donc sur le serveur. Si la nouvelle construction produit
  # moins de pages — une page supprimee, une collection renommee — les
  # anciennes resteraient et seraient publiees. On repart d'un dossier vide.
  rm -rf "$APP_DIR/src/dist"
  ENV_ARGS=()
  [ -f "$APP_DIR/.env" ] && ENV_ARGS=(--env-file "$APP_DIR/.env")
  # PUBLIC_SITE_URL est IMPOSEE depuis le domaine de deploiement. Astro s'en
  # sert pour le sitemap et les liens canoniques : laisser la valeur par defaut
  # publie un site qui declare « https://exemple.fr » et devient invisible pour
  # les moteurs — sans que rien n'echoue. Constate le 2026-07-26.
  # Un site statique n'a aucune raison d'annoncer un domaine autre que celui
  # sur lequel il est servi, d'ou l'imposition plutot que la valeur par defaut.
  docker run --rm \
    --security-opt no-new-privileges:true \
    "${ENV_ARGS[@]}" \
    -e PUBLIC_SITE_URL="https://$DOMAIN" \
    -v "$APP_DIR/src:/build" -w /build \
    node:22-alpine sh -c 'npm ci --no-audit --no-fund && npm run build' < /dev/null

  [ -d "$APP_DIR/src/dist" ] || {
    echo "ERREUR : la construction n'a produit aucun dossier dist/."
    echo "  Verifier que « npm run build » ecrit bien dans dist/."
    exit 1
  }

  # Bascule d'un bloc : le site sert l'ancienne version jusqu'a la seconde ou
  # la nouvelle est complete. Ecrire dans « public » en place exposerait un
  # site a moitie copie pendant plusieurs secondes.
  rm -rf "$APP_DIR/public.new" "$APP_DIR/public.old"
  cp -a "$APP_DIR/src/dist" "$APP_DIR/public.new"

  # Caddy SUIT les liens symboliques. Un lien depose dans le site construit et
  # pointant hors du dossier — « fuite -> /etc/shadow » — serait servi
  # publiquement, sans la moindre alerte. Une construction Astro n'en produit
  # normalement aucun : s'il y en a un qui sort, on refuse de publier.
  LIENS=$(mktemp)
  find "$APP_DIR/public.new" -type l > "$LIENS" 2>/dev/null || true
  while IFS= read -r lien; do
    [ -n "$lien" ] || continue
    cible=$(readlink -f "$lien" 2>/dev/null || echo "")
    case "$cible" in
      "$APP_DIR/public.new"/*) ;;
      *)
        echo "ERREUR : lien symbolique sortant dans le site construit."
        echo "  $lien -> ${cible:-<cible introuvable>}"
        echo "  Caddy servirait ce fichier publiquement. Rien n'a ete publie."
        rm -f "$LIENS"
        exit 1 ;;
    esac
  done < "$LIENS"
  rm -f "$LIENS"
  # Caddy tourne sous son propre compte : sans ce chmod, il ne peut pas lire
  # des fichiers ecrits par le conteneur en root.
  chmod -R a+rX "$APP_DIR/public.new"
  [ -d "$APP_DIR/public" ] && mv "$APP_DIR/public" "$APP_DIR/public.old"
  mv "$APP_DIR/public.new" "$APP_DIR/public"
  rm -rf "$APP_DIR/public.old"
  # Un site qui annonce encore le domaine d'exemple dans ses liens canoniques
  # est en ligne mais invisible pour les moteurs. Le controle de sante ne le
  # verrait pas : la page repond 200.
  # On regarde les URL CANONIQUES et le plan du site, pas n'importe quelle
  # occurrence du texte : une page qui PARLE du domaine d'exemple — une
  # documentation, une page de pannes — est parfaitement legitime.
  if grep -rqsE '(rel="canonical"[^>]*exemple\.fr|<loc>[^<]*exemple\.fr)' \
       "$APP_DIR/public" --include='*.html' --include='*.xml'; then
    echo "ERREUR : les liens canoniques ou le plan du site pointent « exemple.fr »."
    echo "  Le site serait ignore par les moteurs, et son contenu attribue ailleurs."
    echo "  Verifier que astro.config lit bien PUBLIC_SITE_URL."
    exit 1
  fi
  echo "   $(find "$APP_DIR/public" -name '*.html' | wc -l | tr -d ' ') page(s) publiee(s), domaine https://$DOMAIN."

else
  # --- Application : image Docker, base, migrations -------------------------
  cd "$APP_DIR/src"
  docker build -t "$IMAGE" . < /dev/null
  cp docker-compose.yml "$APP_DIR/docker-compose.yml"
  cd "$APP_DIR"

  # ORDRE IMPORTANT : la base d'abord, les migrations ensuite, l'application en
  # dernier. Demarrer l'application avant de migrer la laisse servir du trafic
  # sur une base non migree — invisible au premier deploiement (personne ne
  # visite encore), mais bien reel a chaque REDEPLOIEMENT : Caddy route deja
  # vers ce port, et la nouvelle version repond pendant la migration.
  echo "   démarrage de la base ($DB_CONTAINER)..."
  docker compose up -d "$DB_CONTAINER"

  echo "   attente de la base..."
  PRETE=0
  for _ in $(seq 1 40); do
    if docker compose exec -T "$DB_CONTAINER" pg_isready >/dev/null 2>&1 < /dev/null; then
      PRETE=1; break
    fi
    sleep 1
  done
  if [ "$PRETE" != 1 ]; then
    echo "ERREUR : la base n'est pas prête après 40 secondes."
    docker compose logs --tail 30 "$DB_CONTAINER"
    exit 1
  fi

  # Migrations dans un conteneur JETABLE : l'application en service n'est pas
  # encore demarree, donc rien ne peut servir de trafic pendant cette etape.
  echo "   application des migrations..."
  if ! docker compose run --rm -T app node migrate.mjs < /dev/null; then
    echo "ERREUR : les migrations ont echoue. Rien n'a ete mis en service."
    docker compose logs --tail 30 "$DB_CONTAINER"
    exit 1
  fi

  echo "   mise en service de l'application..."
  docker compose up -d --remove-orphans
fi

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
systemctl reload caddy

# Caddy doit reellement ecouter. Un rechargement peut « reussir » sur une
# configuration vide — si aucun fragment n'est present, l'adaptation produit
# {} et Caddy ferme tous ses ports sans rien signaler.
if ! ss -lnt | grep -q ':443 '; then
  echo "ERREUR : Caddy ne repond sur aucun port 443 apres rechargement."
  echo "  Verifier /etc/caddy/sites/ et « caddy adapt --config /etc/caddy/Caddyfile »."
  exit 1
fi

if [ "$KIND" = app ]; then
  docker compose ps --format 'table {{.Name}}\t{{.Status}}'
else
  echo "   Caddy sert $APP_DIR/public"
fi
echo "__BLOC_DISTANT_TERMINE__"
REMOTE

# Si ce marqueur manque, le script distant a ete tronque : des etapes ont ete
# sautees sans erreur. Mieux vaut echouer ici que servir un site a moitie
# deploye. Voir le commentaire sur « < /dev/null » plus haut.
if ! grep -q '__BLOC_DISTANT_TERMINE__' "$SORTIE_DISTANTE"; then
  rm -f "$SORTIE_DISTANTE"
  echo
  echo "ERREUR : le bloc distant s'est interrompu avant la fin."
  echo "  Une commande y a probablement consomme l'entree standard, qui"
  echo "  transporte le script lui-meme. Ajouter « < /dev/null » a cette"
  echo "  commande. Voir docs/05-pannes.md, panne n°11."
  exit 1
fi
rm -f "$SORTIE_DISTANTE"

# --- Vérification de santé --------------------------------------------------
# Le seul critere qui compte : la reponse du site depuis l'exterieur. Un
# deploiement qui s'annonce reussi sans cette verification ne prouve rien.
echo "-- Vérification de santé : $HEALTH"
for _ in $(seq 1 20); do
  if [ "$KIND" = app ]; then
    # L'endpoint interroge la base : un simple 200 passerait sur une
    # application en ligne dont la base est vide ou injoignable.
    curl -fsS --max-time 5 "$HEALTH" 2>/dev/null | grep -q '"ok":true' && SAIN=1 || SAIN=0
  else
    # Site statique : aucune base a interroger, le code HTTP suffit.
    CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH" 2>/dev/null || echo 000)
    [ "$CODE" = 200 ] && SAIN=1 || SAIN=0
  fi
  if [ "$SAIN" = 1 ]; then
    # Un endpoint de sante qui repond ne prouve PAS que le site s'affiche.
    # Si les fichiers statiques ne sont pas servis, la page arrive en HTML nu :
    # sans style, sans JavaScript, illisible — et /api/health repond {"ok":true}
    # sans rien voir. Constate en production le 2026-07-26.
    # On prend donc une feuille de style referencee par la page d'accueil et on
    # verifie qu'elle se telecharge vraiment.
    # « grep -a » n'est pas decoratif : la reponse HTML contient un octet nul,
    # grep la prend alors pour un fichier binaire, n'affiche rien, et le
    # controle passerait a cote de la panne qu'il est cense detecter.
    ASSET=$(curl -fsS --max-time 10 "https://$DOMAIN/" 2>/dev/null \
            | grep -aoE '(href|src)="/[^"]+\.(css|js)"' | head -1 \
            | sed 's/.*="//; s/"$//')
    if [ -n "$ASSET" ]; then
      CODE_ASSET=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN$ASSET" 2>/dev/null || echo 000)
      if [ "$CODE_ASSET" != 200 ]; then
        echo
        echo "ÉCHEC : la page se charge mais ses fichiers statiques non."
        echo "  $ASSET répond $CODE_ASSET."
        echo "  Le site s'affichera sans style ni JavaScript."
        echo "  Vérifier que server.mjs sert bien dist/client/ (voir docs/05-pannes.md, panne n°13)."
        exit 1
      fi
      echo "   fichiers statiques servis (vérifié sur $ASSET)."
    fi
    echo
    echo "=== Déploiement réussi — https://$DOMAIN ==="
    exit 0
  fi
  sleep 3
done

echo
echo "ÉCHEC : $HEALTH ne répond pas OK après 60 secondes."
echo
echo "Diagnostic :"
if [ "$KIND" = app ]; then
  echo "  ssh $VPS 'cd $APP_DIR && docker compose logs --tail 50 app'"
  echo
  echo "L'application est peut-être en ligne mais sa base est injoignable."
  echo "Cause la plus fréquente : DATABASE_URL vise l'alias « db » au lieu de"
  echo "« $DB_CONTAINER ». Voir docs/05-pannes.md, panne n°1."
else
  echo "  ssh $VPS 'ls $APP_DIR/public | head'"
  echo "  ssh $VPS 'journalctl -u caddy -n 30 --no-pager'"
  echo
  echo "Causes fréquentes : la construction n'a rien écrit dans dist/, le DNS"
  echo "ne pointe pas encore vers le serveur, ou Caddy n'a pas obtenu son"
  echo "certificat. Voir docs/05-pannes.md."
fi
exit 1

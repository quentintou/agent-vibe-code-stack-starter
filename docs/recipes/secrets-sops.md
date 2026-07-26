# Recette (optionnelle) : chiffrer les secrets avec sops + age

**Cette recette ne fait pas partie du chemin par défaut.** Par défaut, les
secrets vivent dans un `.env.production` local, jamais commité, envoyé au serveur
par `scp` en `chmod 600`. C'est suffisant pour une personne seule, et ça
n'ajoute aucun outil.

## Quand l'adopter

- plusieurs personnes déploient le même projet ;
- vous déployez depuis plusieurs machines ;
- vous voulez conserver l'historique des changements de secrets.

En dehors de ces cas, elle ajoute un outil et un risque sans bénéfice.

## Avertissement

**Si vous perdez votre clé age, vous perdez vos secrets.** Définitivement.
Sauvegardez-la hors de la machine avant de commencer.

## Mise en place

```bash
brew install sops age

mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
grep 'public key' ~/.config/sops/age/keys.txt   # noter la clé publique
```

À la racine du projet, `.sops.yaml` :

```yaml
creation_rules:
  - path_regex: secrets/.*\.env$
    age: age1votreclepublique...
```

Chiffrer :

```bash
mkdir -p secrets
cp .env.production secrets/production.env
sops -e -i secrets/production.env    # le fichier chiffré est versionnable
rm .env.production
```

## Adapter le déploiement

Dans `deploy.sh`, remplacer l'envoi direct du fichier de secrets par un
déchiffrement local préalable :

```bash
TMP_ENV="$(mktemp)"
trap 'rm -f "$TMP_ENV"' EXIT
sops -d secrets/production.env > "$TMP_ENV"
scp $SSH_OPTS -q "$TMP_ENV" "$VPS:$APP_DIR/.env"
```

Le serveur ne détient aucune clé : le déchiffrement a lieu sur votre machine.

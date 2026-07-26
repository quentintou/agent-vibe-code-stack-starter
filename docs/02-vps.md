# 2. Préparer le serveur

Une seule commande, relançable sans risque :

```bash
./scripts/bootstrap-vps.sh root@203.0.113.10
```

Elle installe Docker et Caddy s'ils manquent, crée le réseau Docker `web`, le
dossier `/opt/apps`, et met en place un fichier Caddy central qui ne contient
qu'un `import /etc/caddy/sites/*.caddy`.

## Vérification

```bash
ssh root@203.0.113.10 'docker ps && caddy version'
```

Attendu : la liste des conteneurs (vide au départ), puis une version de Caddy.

## Si le serveur avait déjà une configuration Caddy

Le script la sauvegarde dans `/etc/caddy/Caddyfile.avant-starter.<horodatage>` et prévient.
Les sites qu'elle contenait doivent être découpés à la main, un fichier par site,
dans `/etc/caddy/sites/`. **Ne pas remettre l'ancienne configuration en place** :
c'est ce découpage qui permet à plusieurs projets de cohabiter sans s'écraser.

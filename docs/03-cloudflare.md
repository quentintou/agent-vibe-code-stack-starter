# 3. Faire pointer le domaine

## Ce que Cloudflare fait ici

Le domaine, le certificat HTTPS, la protection contre les abus, les formulaires
anti-robots (Turnstile) et la redirection d'e-mails. Gratuit pour ces usages.

**Le code ne tourne pas chez Cloudflare.** L'application tourne sur le serveur,
Cloudflare est devant. Pour ce que les Workers font quand même bien — l'envoi
d'e-mails depuis le domaine notamment — et pour la mise en place d'Email
Routing, voir `docs/08-workers-et-emails.md`.

## Si le domaine n'est pas encore géré par Cloudflare

C'est le cas le plus fréquent : le domaine a été acheté chez OVH, Gandi, Namecheap
ou Google, et ses serveurs de noms y pointent encore.

**L'agent ne peut pas faire cette bascule à la place de l'utilisateur** : elle se
fait dans l'interface du registrar, avec son mot de passe. Guidez-le :

1. Sur <https://dash.cloudflare.com> → *Add a site* → saisir le domaine, offre
   gratuite. Cloudflare importe les enregistrements DNS existants.
2. **Vérifier cet import avant d'aller plus loin.** S'il manque un enregistrement
   MX, les e-mails du domaine s'arrêteront à la bascule. C'est l'erreur qui fait
   le plus de dégâts, et elle est silencieuse.
3. Cloudflare affiche deux serveurs de noms. Les saisir chez le registrar, à la
   place des existants.
4. La propagation prend de quelques minutes à 24 heures. Cloudflare envoie un
   e-mail quand le domaine est actif.

**Pendant ce temps, ne déployez pas** : le certificat HTTPS ne pourra pas être
émis et vous conclurez à tort à une panne. Profitez-en pour préparer le code et
la base locale (`docs/06-developper-en-local.md`).

Vérifier l'état :

```bash
dig +short NS example.com
```

Attendu une fois la bascule faite : deux serveurs de noms en `.ns.cloudflare.com`.

**Alternative si l'utilisateur ne veut pas changer de registrar :** un
enregistrement A pointant directement vers l'IP du serveur suffit. Caddy obtient
alors lui-même le certificat. On perd le proxy Cloudflare (protection, cache),
mais le site fonctionne. Dans ce cas, ignorer le réglage SSL ci-dessous.

---

## Les trois réglages

1. **Un enregistrement DNS de type A**
   - Nom : `@` (ou le sous-domaine voulu)
   - Contenu : l'adresse IP du serveur
   - Proxy : **désactivé** (nuage gris) pour le premier déploiement

2. **Un second enregistrement A pour `www`**, même IP, proxy également
   désactivé. Cet enregistrement est facultatif : sans lui, `deploy.sh`
   n'ajoute simplement pas la redirection `www`.

> **Pourquoi désactivé au départ.** Caddy obtient son certificat en prouvant à
> Let's Encrypt qu'il contrôle le domaine. Avec le proxy actif, la requête de
> vérification s'arrête chez Cloudflare et n'atteint jamais le serveur : le
> certificat n'est jamais délivré, et le site reste inaccessible sans qu'aucun
> message ne l'explique.
>
> Une fois le site en ligne et le certificat obtenu, activer le proxy est un
> choix légitime (cache, protection contre les abus). Faites-le **après** un
> déploiement réussi, jamais avant.

3. **Mode SSL/TLS : Full (strict)**
   Onglet SSL/TLS → Overview → « Full (strict) ».

   Le mode « Flexible » fait boucler la connexion entre Cloudflare et Caddy et
   provoque une erreur de redirection. C'est une cause de panne fréquente.

## Vérification

```bash
dig +short example.com
```

Attendu : une adresse IP. Avec le proxy activé, ce sera une IP Cloudflare et non
celle du serveur — c'est normal.

La propagation prend de quelques secondes à quelques minutes. Attendre avant de
conclure à une panne.

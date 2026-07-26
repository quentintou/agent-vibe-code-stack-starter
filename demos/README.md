# Les deux démonstrations en ligne

Ce dossier contient le code des deux sites publiés, et **ne fait pas partie du
socle**. Rien ici n'est nécessaire pour utiliser le dépôt : c'est un exemple de
ce que les deux chemins produisent une fois remplis.

| Démonstration | Chemin | Adresse |
|---|---|---|
| Vitrine du projet | contenu | <https://contenu.app-run.pro> |
| Tableau de bord d'équipe | application | <https://stack.app-run.pro> |

Les deux tournent **sur le même serveur**, déployées par le même
`scripts/deploy.sh`. C'est le champ `kind` de `deploy.config.json` qui lui
indique le chemin à suivre ; le reste de la configuration (domaine, nom du
projet, ports) est propre à chaque site.

---

## `vitrine/` — le chemin contenu

Projet Astro complet, à copier tel quel. C'est `templates/content/` dont on a
remplacé les pages : trois pages, une mise en page, aucune base de données.

```bash
cp -R demos/vitrine mon-site && cd mon-site
npm install && npm run dev
```

## `tableau-de-bord/` — le chemin application

**Seuls les fichiers qui diffèrent** de `templates/app/`. Le reste du squelette
est inchangé, donc inutile à dupliquer.

| Fichier | Ce qu'il apporte |
|---|---|
| `src/db/schema.ts` | la table `notes` |
| `drizzle/0001_notes.sql` | la migration correspondante |
| `src/serveur/notes.ts` | trois fonctions serveur : lister, ajouter, supprimer |
| `src/routes/index.tsx` | connexion, puis le tableau de bord |
| `src/components/VisiteGuidee.tsx` | la visite guidée décrite plus bas |
| `src/components/Header.tsx`, `Footer.tsx` | remplacent ceux du squelette |

Pour reproduire :

```bash
cp -R templates/app mon-outil
cp -R demos/tableau-de-bord/* mon-outil/
cd mon-outil && npm install && npm run build
```

### Le point à retenir de `notes.ts`

Chaque fonction serveur vérifie la session **avant** sa première requête SQL :

```ts
async function exigeSession() {
  const session = await auth.api.getSession({ headers: getRequest().headers })
  if (!session?.user) throw new Error('Connexion requise.')
  return session.user
}
```

Masquer un formulaire ne protège rien — la fonction serveur reste appelable
directement. **L'affichage n'est pas un contrôle d'accès.** La visite guidée
le démontre en appelant `listerNotes()` sans session, sous les yeux du visiteur.

Second point : les validateurs ne se fient pas aux annotations TypeScript, qui
disparaissent à la compilation. Ce qui arrive dans un validateur vient du
réseau et peut être un nombre, un tableau ou `null`.

## La visite guidée

Sur la page de connexion, quatre boutons envoient chacun une **vraie requête**
au serveur depuis le navigateur du visiteur, et affichent la réponse obtenue :

1. l'inscription publique est fermée — création de compte tentée, refusée ;
2. les fonctions serveur exigent une session — appel sans session, refusé ;
3. l'application voit sa base — `/api/health` interroge une vraie table ;
4. les fichiers du navigateur sont servis — la feuille de style se télécharge.

Rien n'est simulé. Si une garantie tombe, la visite guidée l'affiche en rouge :
c'est le seul format honnête pour une démonstration.

Les quatre correspondent à des pannes réellement rencontrées — la quatrième
notamment, où le site s'affichait sans style pendant que le contrôle de santé
répondait `{"ok":true}`. Voir `docs/journal-test-3.md`.

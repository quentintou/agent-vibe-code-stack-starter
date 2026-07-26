// Tables d'authentification generees par la CLI better-auth.
// Les reexporter ici est indispensable : sans cela drizzle-kit ne les
// voit pas et ne genere aucune migration pour elles.
export * from './auth-schema.ts'

import { index, pgTable, serial, text, timestamp } from 'drizzle-orm/pg-core'

// Table d'exemple livree avec le squelette. Conservee : la supprimer en meme
// temps qu'on ajoute « notes » rend le diff ambigu, et drizzle-kit demande
// alors en interactif s'il s'agit d'un renommage — ce qui bloque tout script.
export const todos = pgTable('todos', {
  id: serial().primaryKey(),
  title: text().notNull(),
  createdAt: timestamp('created_at').defaultNow(),
})

// Tableau de bord d'equipe : des liens et des notes partages entre les
// personnes qui ont un compte. Volontairement minuscule — l'interet est de
// montrer la chaine complete : connexion, ecriture en base, lecture, suppression.
export const notes = pgTable(
  'notes',
  {
    id: serial().primaryKey(),
    titre: text().notNull(),
    url: text(),
    contenu: text(),
    // On stocke le nom au moment de l'ecriture plutot qu'une cle etrangere :
    // une note doit survivre a la suppression de son auteur.
    auteur: text().notNull(),
    creeLe: timestamp('cree_le').defaultNow().notNull(),
  },
  (t) => [index('notes_cree_le_idx').on(t.creeLe)],
)

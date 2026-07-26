// Tables d'authentification generees par la CLI better-auth.
// Les reexporter ici est indispensable : sans cela drizzle-kit ne les
// voit pas et ne genere aucune migration pour elles.
export * from './auth-schema.ts'

import { pgTable, serial, text, timestamp } from 'drizzle-orm/pg-core'

export const todos = pgTable('todos', {
  id: serial().primaryKey(),
  title: text().notNull(),
  createdAt: timestamp('created_at').defaultNow(),
})

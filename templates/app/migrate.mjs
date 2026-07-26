// Applique les migrations Drizzle. Lancé par scripts/deploy.sh avant que
// l'application ne serve du trafic.
//
// Sans cette étape, la base reste VIDE : l'application démarre, répond, et
// échoue à la première requête réelle. Constaté en production le 2026-07-26 —
// le déploiement s'annonçait réussi sur une base sans aucune table.
import { drizzle } from 'drizzle-orm/node-postgres'
import { migrate } from 'drizzle-orm/node-postgres/migrator'

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL manquante.')
  process.exit(1)
}

const db = drizzle(process.env.DATABASE_URL)
await migrate(db, { migrationsFolder: './drizzle' })
console.log('Migrations appliquées.')
process.exit(0)

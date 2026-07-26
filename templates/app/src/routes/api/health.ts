import { createFileRoute } from '@tanstack/react-router'
import { sql } from 'drizzle-orm'
import { db } from '#/db'

// Endpoint de santé consommé par scripts/deploy.sh après chaque déploiement.
//
// Il interroge réellement la base : un serveur qui répond alors que sa base est
// injoignable sert des erreurs 500 en silence. Mieux vaut échouer bruyamment
// pendant le déploiement que découvrir la panne via un utilisateur.
export const Route = createFileRoute('/api/health')({
  server: {
    handlers: {
      GET: async () => {
        try {
          // Interroger une vraie table : `select 1` reussit meme sur une base
          // sans aucun schema, ce qui donne une fausse assurance et laisse
          // passer un deploiement dont les migrations n'ont pas tourne.
          await db.execute(sql`select 1 from "user" limit 1`)
          return Response.json({ ok: true })
        } catch (error) {
          // Le detail part dans les journaux du conteneur, PAS dans la reponse.
          // Un message PostgreSQL brut publie sur une URL ouverte revele le nom
          // d'hote de la base, l'utilisateur SQL, les tables manquantes et les
          // conventions de deploiement. Pour diagnostiquer :
          //   docker compose logs --tail 50 app
          console.error(
            '[health] base injoignable ou migrations non appliquees :',
            error instanceof Error ? error.message : String(error),
          )
          return Response.json({ ok: false }, { status: 503 })
        }
      },
    },
  },
})

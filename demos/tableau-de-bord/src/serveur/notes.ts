import { createServerFn } from '@tanstack/react-start'
import { getRequest } from '@tanstack/react-start/server'
import { desc, eq } from 'drizzle-orm'
import { db } from '#/db'
import { notes } from '#/db/schema'
import { auth } from '#/lib/auth'

/**
 * Toute fonction ci-dessous verifie la session AVANT de toucher a la base.
 *
 * Ne pas le faire est l'erreur classique : l'interface cache le formulaire aux
 * visiteurs non connectes, mais la fonction serveur reste appelable directement.
 * L'affichage n'est pas un controle d'acces.
 */
async function exigeSession() {
  const session = await auth.api.getSession({ headers: getRequest().headers })
  if (!session?.user) {
    throw new Error('Connexion requise.')
  }
  return session.user
}

export const listerNotes = createServerFn({ method: 'GET' }).handler(async () => {
  await exigeSession()
  return db.select().from(notes).orderBy(desc(notes.creeLe)).limit(50)
})

export const ajouterNote = createServerFn({ method: 'POST' })
  .validator((donnees: { titre: string; url: string; contenu: string }) => {
    // Le type ci-dessus est une annotation TypeScript : elle disparait a la
    // compilation. Ce qui arrive ici vient du reseau et peut etre n'importe
    // quoi — un nombre, un tableau, null. Sans ce controle, `.trim()` leve une
    // TypeError et l'utilisateur recoit un message technique au lieu d'un refus.
    const texte = (v: unknown) => (typeof v === 'string' ? v : '')

    const titre = texte(donnees?.titre).trim()
    if (titre.length < 2) throw new Error('Le titre est trop court.')
    if (titre.length > 120) throw new Error('Le titre est trop long (120 caractères maximum).')

    const url = texte(donnees?.url).trim()
    // La colonne PostgreSQL est un `text` : elle accepte des mega-octets. Sans
    // borne ici, une seule note peut gonfler la base et alourdir toutes les
    // lectures suivantes. 2 048 caracteres couvrent largement une vraie URL.
    if (url.length > 2048) throw new Error("L'adresse est trop longue.")
    if (url && !/^https?:\/\/\S+$/.test(url)) {
      throw new Error("L'adresse doit commencer par http:// ou https://")
    }

    const contenu = texte(donnees?.contenu).trim()
    if (contenu.length > 2000) throw new Error('La note est trop longue (2000 caractères maximum).')

    return { titre, url, contenu }
  })
  .handler(async ({ data }) => {
    const utilisateur = await exigeSession()
    await db.insert(notes).values({
      titre: data.titre,
      url: data.url || null,
      contenu: data.contenu || null,
      auteur: utilisateur.name || utilisateur.email,
    })
    return { ok: true }
  })

export const supprimerNote = createServerFn({ method: 'POST' })
  .validator((donnees: { id: number }) => {
    // Meme remarque : `id` arrive du reseau. On exige un entier positif, pas
    // seulement « quelque chose qui ressemble a un nombre ».
    const id = donnees?.id
    // Borne haute : la colonne est un `serial`, donc un entier 32 bits. Une
    // valeur au-dela fait remonter une erreur PostgreSQL brute jusqu'au client.
    if (typeof id !== 'number' || !Number.isSafeInteger(id) || id < 1 || id > 2147483647) {
      throw new Error('Identifiant invalide.')
    }
    return { id }
  })
  .handler(async ({ data }) => {
    await exigeSession()
    await db.delete(notes).where(eq(notes.id, data.id))
    return { ok: true }
  })

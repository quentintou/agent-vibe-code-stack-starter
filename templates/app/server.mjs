// Entrée serveur pour l'auto-hébergement (Docker, VPS).
//
// Deux responsabilités, et les DEUX sont nécessaires :
//
// 1. `vite build` produit dist/server/server.js, qui exporte un handler `fetch`
//    (standard WinterCG) et NON un serveur qui écoute un port. Lancer ce
//    fichier directement avec node se termine sans message d'erreur.
//
// 2. Ce handler ne sert PAS les fichiers du client. Ils sont dans
//    dist/client/, et personne ne les sert si on ne le fait pas ici : la page
//    s'affiche alors sans style ni JavaScript, en Times New Roman, pendant que
//    `/api/health` répond {"ok":true} — le contrôle de santé ne voit rien.
//    Constaté en production le 2026-07-26.
//
// La documentation TanStack le dit : « static assets must be served from the
// client directory while all other requests are forwarded to the server
// entry's fetch handler ».
import { createReadStream, statSync } from 'node:fs'
import { extname, join, resolve, sep } from 'node:path'
import { Readable } from 'node:stream'
import { serve } from 'srvx'
import handler from './dist/server/server.js'

const port = Number(process.env.PORT ?? 3000)
const RACINE = resolve('./dist/client')

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.map': 'application/json; charset=utf-8',
}

/**
 * Retourne le fichier statique correspondant au chemin demandé, ou null.
 *
 * Le chemin est résolu PUIS vérifié comme appartenant à dist/client : sans ce
 * contrôle, « /../../../etc/passwd » sortirait du dossier et servirait
 * n'importe quel fichier du conteneur.
 */
function fichierStatique(pathname) {
  let decode
  try {
    decode = decodeURIComponent(pathname)
  } catch {
    return null // séquence %XX invalide
  }
  if (decode.includes('\0')) return null

  const chemin = resolve(join(RACINE, decode))
  if (chemin !== RACINE && !chemin.startsWith(RACINE + sep)) return null

  try {
    const info = statSync(chemin)
    if (!info.isFile()) return null
    return { chemin, taille: info.size, mtime: info.mtimeMs }
  } catch {
    return null
  }
}

serve({
  port,
  hostname: '0.0.0.0',
  async fetch(request) {
    if (request.method === 'GET' || request.method === 'HEAD') {
      const { pathname } = new URL(request.url)
      const fichier = fichierStatique(pathname)
      if (fichier) {
        const ext = extname(fichier.chemin).toLowerCase()
        // Les noms sous /assets/ contiennent une empreinte du contenu : un
        // changement produit un nouveau nom, on peut donc mettre en cache
        // sans limite. Le reste (favicon, robots.txt) garde un cache court.
        const immuable = pathname.startsWith('/assets/')
        const corps =
          request.method === 'HEAD'
            ? null
            : Readable.toWeb(createReadStream(fichier.chemin))
        return new Response(corps, {
          headers: {
            'content-type': TYPES[ext] ?? 'application/octet-stream',
            'content-length': String(fichier.taille),
            'cache-control': immuable
              ? 'public, max-age=31536000, immutable'
              : 'public, max-age=3600',
            'last-modified': new Date(fichier.mtime).toUTCString(),
          },
        })
      }
    }
    return handler.fetch(request)
  },
})

console.log(`Serveur démarré sur http://0.0.0.0:${port}`)
console.log(`Fichiers statiques servis depuis ${RACINE}`)

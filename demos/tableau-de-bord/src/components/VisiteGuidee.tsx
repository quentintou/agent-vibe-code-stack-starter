import { useState } from 'react'
import { listerNotes } from '#/serveur/notes'

/**
 * Visite guidee : chaque etape EXECUTE reellement la garantie annoncee et
 * affiche la reponse obtenue. Rien n'est simule — les requetes partent du
 * navigateur du visiteur vers ce serveur, maintenant.
 *
 * C'est le seul format honnete pour une demonstration : montrer plutot
 * qu'affirmer, et laisser voir le resultat brut, y compris s'il deplait.
 */

interface Resultat {
  ok: boolean
  resume: string
  detail: string
}

interface Etape {
  cle: string
  titre: string
  question: string
  attendu: string
  executer: () => Promise<Resultat>
}

const adresseAleatoire = () =>
  `visiteur-${Math.random().toString(36).slice(2, 10)}@exemple.invalid`

const ETAPES: Array<Etape> = [
  {
    cle: 'inscription',
    titre: "L'inscription publique est fermée",
    question:
      "Sur un outil interne, laisser l'inscription ouverte permet à n'importe qui de se créer un compte. Essayons d'en créer un.",
    attendu: 'La requête doit être refusée, avant même que la base soit consultée.',
    async executer() {
      const email = adresseAleatoire()
      const r = await fetch('/api/auth/sign-up/email', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email, name: 'Visiteur', password: 'motdepasse12345' }),
      })
      const corps = await r.text()
      let message = corps
      try {
        message = JSON.parse(corps).message ?? corps
      } catch {}
      return {
        ok: !r.ok,
        resume: `HTTP ${r.status}`,
        detail: `POST /api/auth/sign-up/email\nadresse tirée au hasard : ${email}\n\n→ ${message}`,
      }
    },
  },
  {
    cle: 'session',
    titre: 'Les fonctions serveur vérifient la session',
    question:
      "Masquer un formulaire ne protège rien : la fonction serveur reste appelable. Appelons celle qui liste les notes, sans être connecté.",
    attendu: "L'appel doit être refusé avant toute lecture en base.",
    async executer() {
      try {
        const donnees = await listerNotes()
        return {
          ok: false,
          resume: 'Données renvoyées',
          detail:
            `La fonction a répondu sans session — ce serait une faille.\n` +
            `${Array.isArray(donnees) ? donnees.length : 0} entrée(s) exposée(s).`,
        }
      } catch (e) {
        return {
          ok: true,
          resume: 'Refusé',
          detail: `listerNotes() appelée sans session\n\n→ ${(e as Error).message}`,
        }
      }
    },
  },
  {
    cle: 'sante',
    titre: "L'application voit réellement sa base",
    question:
      "Beaucoup de déploiements s'annoncent réussis alors que la base est injoignable. Le contrôle de santé interroge une vraie table.",
    attendu: '{"ok":true} — et une erreur si la base ne répond pas.',
    async executer() {
      const r = await fetch('/api/health')
      const corps = await r.text()
      return {
        ok: r.ok && corps.includes('"ok":true'),
        resume: `HTTP ${r.status}`,
        detail: `GET /api/health\n\n→ ${corps.trim()}`,
      }
    },
  },
  {
    cle: 'statique',
    titre: 'Les fichiers du navigateur sont servis',
    question:
      "Une panne réelle de ce dépôt : la page répondait 200 mais toutes ses feuilles de style renvoyaient 404. Le site s'affichait en Times New Roman.",
    attendu: 'La feuille de style de cette page doit se télécharger.',
    async executer() {
      const lien = document.querySelector<HTMLLinkElement>('link[rel="stylesheet"]')
      const href = lien?.getAttribute('href') ?? '/assets/introuvable.css'
      const r = await fetch(href)
      const taille = (await r.blob()).size
      return {
        ok: r.ok && taille > 0,
        resume: `HTTP ${r.status}`,
        detail: `GET ${href}\n\n→ ${new Intl.NumberFormat('fr-FR').format(taille)} octets, type ${r.headers.get('content-type') ?? '—'}`,
      }
    },
  },
]

export function VisiteGuidee() {
  const [ouverte, setOuverte] = useState<string | null>(null)
  const [resultats, setResultats] = useState<Record<string, Resultat | 'encours'>>({})

  const lancer = async (etape: Etape) => {
    setOuverte(etape.cle)
    setResultats((r) => ({ ...r, [etape.cle]: 'encours' }))
    try {
      const res = await etape.executer()
      setResultats((r) => ({ ...r, [etape.cle]: res }))
    } catch (e) {
      setResultats((r) => ({
        ...r,
        [etape.cle]: { ok: false, resume: 'Erreur', detail: (e as Error).message },
      }))
    }
  }

  return (
    <section className="mt-10">
      <h2 className="text-lg font-semibold tracking-tight">Vérifiez vous-même</h2>
      <p className="mt-1.5 text-sm text-neutral-600">
        Quatre garanties du dépôt. Chaque bouton envoie une vraie requête à ce serveur,
        depuis votre navigateur, et affiche la réponse obtenue — sans mise en scène.
      </p>

      <ol className="mt-5 grid gap-3">
        {ETAPES.map((etape, i) => {
          const res = resultats[etape.cle]
          const estOuverte = ouverte === etape.cle
          return (
            <li key={etape.cle} className="overflow-hidden rounded-xl border border-neutral-200 bg-white">
              <div className="flex flex-wrap items-center gap-3 px-4 py-3">
                <span className="font-mono text-xs text-neutral-400">{String(i + 1).padStart(2, '0')}</span>
                <span className="flex-1 text-sm font-medium">{etape.titre}</span>
                {res && res !== 'encours' && (
                  <span
                    className={`rounded px-2 py-0.5 text-xs font-medium ${
                      res.ok ? 'bg-emerald-50 text-emerald-700' : 'bg-red-50 text-red-700'
                    }`}
                  >
                    {res.ok ? 'conforme' : 'inattendu'} · {res.resume}
                  </span>
                )}
                <button
                  onClick={() => (estOuverte ? setOuverte(null) : lancer(etape))}
                  className="rounded-md border border-neutral-300 px-3 py-1.5 text-xs font-medium hover:border-neutral-500"
                >
                  {res === 'encours' ? '…' : estOuverte ? 'Replier' : res ? 'Rejouer' : 'Essayer'}
                </button>
              </div>

              {estOuverte && (
                <div className="border-t border-neutral-100 bg-neutral-50/70 px-4 py-4 text-sm">
                  <p className="text-neutral-600">{etape.question}</p>
                  <p className="mt-2 text-xs text-neutral-500">
                    <span className="font-medium text-neutral-700">Attendu :</span> {etape.attendu}
                  </p>
                  {res && res !== 'encours' && (
                    <pre className="mt-3 overflow-x-auto rounded-lg bg-neutral-900 px-4 py-3 font-mono text-xs leading-relaxed whitespace-pre-wrap text-neutral-100">
{res.detail}
                    </pre>
                  )}
                  {res === 'encours' && <p className="mt-3 text-xs text-neutral-500">Requête en cours…</p>}
                </div>
              )}
            </li>
          )
        })}
      </ol>
    </section>
  )
}

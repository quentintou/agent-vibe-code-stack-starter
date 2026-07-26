import { createFileRoute } from '@tanstack/react-router'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useRef, useState } from 'react'
import { authClient } from '#/lib/auth-client'
import { Turnstile, enteteCaptcha } from '#/lib/turnstile'
import { VisiteGuidee } from '#/components/VisiteGuidee'
import { ajouterNote, listerNotes, supprimerNote } from '#/serveur/notes'

export const Route = createFileRoute('/')({ component: Accueil })

const dateFr = new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short' })

function Accueil() {
  const { data: session, isPending } = authClient.useSession()

  // Pendant la resolution de session — donc aussi au rendu serveur — on affiche
  // la page de connexion, pas un indicateur de chargement. Sinon le HTML servi
  // ne contient RIEN : ni le formulaire, ni la visite guidee. Un visiteur sans
  // JavaScript, un moteur de recherche ou un simple `curl` ne voient qu'un
  // rond qui tourne, et la demonstration ne demontre plus rien.
  if (isPending) return <Connexion enAttente />

  return session?.user ? <TableauDeBord nom={session.user.name || session.user.email} /> : <Connexion />
}

/* ------------------------------------------------------------------ */

function Connexion({ enAttente = false }: { enAttente?: boolean }) {
  const [email, setEmail] = useState('')
  const [motDePasse, setMotDePasse] = useState('')
  const [erreur, setErreur] = useState('')
  const [enCours, setEnCours] = useState(false)
  const [jeton, setJeton] = useState('')
  const reinit = useRef<(() => void) | null>(null)

  const envoyer = async (e: React.FormEvent) => {
    e.preventDefault()
    setErreur('')
    setEnCours(true)
    try {
      const r = await authClient.signIn.email({
        email,
        password: motDePasse,
        fetchOptions: { headers: enteteCaptcha(jeton) },
      })
      if (r.error) setErreur(r.error.message || 'Connexion refusée.')
    } catch {
      setErreur('Une erreur inattendue est survenue.')
    } finally {
      setEnCours(false)
      // Un jeton anti-robots ne sert qu'une fois.
      reinit.current?.()
    }
  }

  return (
    <main className="page-wrap px-4 py-12">
      <div className="mx-auto w-full max-w-xl">
        <div className="mb-8">
          <p className="text-xs font-medium tracking-widest text-emerald-700 uppercase">Démonstration</p>
          <h1 className="mt-2 text-2xl font-bold tracking-tight">Tableau de bord d'équipe</h1>
          <p className="mt-2 text-sm text-neutral-600">
            Un outil interne minuscule : des liens et des notes partagés entre les personnes
            qui ont un compte. Connexion obligatoire, inscription publique fermée.
          </p>
        </div>

        <form onSubmit={envoyer} className="mx-auto grid max-w-sm gap-4 rounded-xl border border-neutral-200 bg-white p-6">
          <div className="grid gap-1.5">
            <label htmlFor="email" className="text-sm font-medium">Adresse e-mail</label>
            <input
              id="email" type="email" autoComplete="username" required
              value={email} onChange={(e) => setEmail(e.target.value)}
              className="rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-900"
            />
          </div>
          <div className="grid gap-1.5">
            <label htmlFor="mdp" className="text-sm font-medium">Mot de passe</label>
            <input
              id="mdp" type="password" autoComplete="current-password" required minLength={8}
              value={motDePasse} onChange={(e) => setMotDePasse(e.target.value)}
              className="rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-900"
            />
          </div>

          <Turnstile onJeton={setJeton} reinitRef={reinit} />

          {erreur && (
            <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{erreur}</p>
          )}

          <button
            type="submit" disabled={enCours}
            className="rounded-md bg-neutral-900 px-4 py-2.5 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
          >
            {enCours ? 'Connexion…' : 'Se connecter'}
          </button>
        </form>

        <p className="mt-5 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-900">
          <strong>Compte de démonstration</strong> — les identifiants sont fournis avec le lien.
          Pas besoin de compte pour la visite guidée ci-dessous.
        </p>

        <VisiteGuidee />

        <p className="mt-8 text-center text-sm text-neutral-500">
          <a href="https://contenu.app-run.pro" className="underline underline-offset-4 hover:text-neutral-900">
            Le principe du dépôt
          </a>
          {' · '}
          <a href="https://github.com/quentintou/agent-vibe-code-stack-starter" className="underline underline-offset-4 hover:text-neutral-900">
            Le code source
          </a>
        </p>
      </div>
    </main>
  )
}

/* ------------------------------------------------------------------ */

function TableauDeBord({ nom }: { nom: string }) {
  const qc = useQueryClient()
  const [titre, setTitre] = useState('')
  const [url, setUrl] = useState('')
  const [contenu, setContenu] = useState('')
  const [erreur, setErreur] = useState('')

  const { data: liste = [], isPending } = useQuery({
    queryKey: ['notes'],
    queryFn: () => listerNotes(),
  })

  const ajout = useMutation({
    mutationFn: (d: { titre: string; url: string; contenu: string }) => ajouterNote({ data: d }),
    onSuccess: () => {
      setTitre(''); setUrl(''); setContenu(''); setErreur('')
      qc.invalidateQueries({ queryKey: ['notes'] })
    },
    onError: (e: Error) => setErreur(e.message),
  })

  const suppression = useMutation({
    mutationFn: (id: number) => supprimerNote({ data: { id } }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['notes'] }),
  })

  return (
    <main className="page-wrap px-4 py-10">
      <header className="flex flex-wrap items-end justify-between gap-4 border-b border-neutral-200 pb-6">
        <div>
          <p className="text-xs font-medium tracking-widest text-emerald-700 uppercase">Démonstration</p>
          <h1 className="mt-1.5 text-2xl font-bold tracking-tight">Tableau de bord d'équipe</h1>
          <p className="mt-1 text-sm text-neutral-600">Connecté en tant que {nom}.</p>
        </div>
        <button
          onClick={() => authClient.signOut().then(() => window.location.reload())}
          className="rounded-md border border-neutral-300 px-3.5 py-2 text-sm hover:border-neutral-400"
        >
          Se déconnecter
        </button>
      </header>

      <div className="mt-8 grid gap-8 lg:grid-cols-[22rem_1fr]">
        <form
          onSubmit={(e) => { e.preventDefault(); ajout.mutate({ titre, url, contenu }) }}
          className="grid h-fit gap-4 rounded-xl border border-neutral-200 bg-white p-5"
        >
          <h2 className="font-semibold">Ajouter</h2>
          <div className="grid gap-1.5">
            <label htmlFor="t" className="text-sm font-medium">Titre</label>
            <input
              id="t" required value={titre} onChange={(e) => setTitre(e.target.value)} maxLength={120}
              className="rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-900"
            />
          </div>
          <div className="grid gap-1.5">
            <label htmlFor="u" className="text-sm font-medium">
              Lien <span className="font-normal text-neutral-400">(facultatif)</span>
            </label>
            <input
              id="u" type="url" placeholder="https://…" value={url} onChange={(e) => setUrl(e.target.value)}
              className="rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-900"
            />
          </div>
          <div className="grid gap-1.5">
            <label htmlFor="c" className="text-sm font-medium">
              Note <span className="font-normal text-neutral-400">(facultatif)</span>
            </label>
            <textarea
              id="c" rows={3} maxLength={2000} value={contenu} onChange={(e) => setContenu(e.target.value)}
              className="rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-900"
            />
          </div>
          {erreur && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{erreur}</p>}
          <button
            type="submit" disabled={ajout.isPending}
            className="rounded-md bg-neutral-900 px-4 py-2.5 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
          >
            {ajout.isPending ? 'Enregistrement…' : 'Enregistrer'}
          </button>
          <p className="text-xs text-neutral-500">
            Écrit dans Postgres par une fonction serveur qui vérifie la session avant
            d'insérer. Masquer le formulaire ne suffirait pas : l'affichage n'est pas
            un contrôle d'accès.
          </p>
        </form>

        <section>
          <h2 className="font-semibold">
            Partagé par l'équipe{' '}
            <span className="font-normal text-neutral-400">({liste.length})</span>
          </h2>

          {isPending ? (
            <p className="mt-6 text-sm text-neutral-500">Chargement…</p>
          ) : liste.length === 0 ? (
            <p className="mt-6 rounded-lg border border-dashed border-neutral-300 px-5 py-8 text-center text-sm text-neutral-500">
              Rien pour l'instant. Ajoutez la première entrée.
            </p>
          ) : (
            <ul className="mt-5 grid gap-3">
              {liste.map((n: any) => (
                <li key={n.id} className="rounded-xl border border-neutral-200 bg-white p-4">
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0">
                      <h3 className="font-medium">
                        {n.url ? (
                          <a href={n.url} target="_blank" rel="noopener noreferrer"
                             className="underline decoration-neutral-300 underline-offset-4 hover:decoration-neutral-900">
                            {n.titre}
                          </a>
                        ) : n.titre}
                      </h3>
                      {n.contenu && <p className="mt-1.5 text-sm whitespace-pre-wrap text-neutral-600">{n.contenu}</p>}
                      <p className="mt-2 text-xs text-neutral-400">
                        {n.auteur} — {dateFr.format(new Date(n.creeLe))}
                      </p>
                    </div>
                    <button
                      onClick={() => suppression.mutate(n.id)}
                      aria-label={`Supprimer « ${n.titre} »`}
                      className="shrink-0 rounded-md border border-neutral-200 px-2.5 py-1 text-xs text-neutral-500 hover:border-red-300 hover:text-red-600"
                    >
                      Supprimer
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </main>
  )
}

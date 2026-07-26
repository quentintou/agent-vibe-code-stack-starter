import { useEffect, useRef } from 'react'

// Widget anti-robots Cloudflare Turnstile.
//
// Tout ici est CONDITIONNEL : sans VITE_TURNSTILE_SITE_KEY, le composant ne
// rend rien et l'en-tete n'est pas envoye. C'est delibere — l'application doit
// pouvoir etre deployee et utilisee avant que l'utilisateur ait cree ses cles
// Cloudflare. Cote serveur, `auth.ts` applique la meme regle avec la cle
// secrete : les deux moities s'activent ensemble ou pas du tout.

const CLE_PUBLIQUE = import.meta.env.VITE_TURNSTILE_SITE_KEY as string | undefined

const URL_SCRIPT =
  'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'

declare global {
  interface Window {
    turnstile?: {
      render: (element: HTMLElement, options: Record<string, unknown>) => string
      reset: (widgetId: string) => void
      remove: (widgetId: string) => void
    }
  }
}

export function captchaActif(): boolean {
  return Boolean(CLE_PUBLIQUE)
}

/**
 * En-tete a joindre aux appels d'authentification. Vide si Turnstile est
 * inactif : better-auth n'exige alors aucun jeton.
 */
export function enteteCaptcha(jeton: string): Record<string, string> {
  return CLE_PUBLIQUE && jeton ? { 'x-captcha-response': jeton } : {}
}

let chargement: Promise<void> | null = null

function chargerScript(): Promise<void> {
  // Une seule injection, meme si plusieurs formulaires montent le widget.
  if (chargement) return chargement
  chargement = new Promise((resoudre, rejeter) => {
    if (window.turnstile) return resoudre()
    const script = document.createElement('script')
    script.src = URL_SCRIPT
    script.async = true
    script.defer = true
    script.onload = () => resoudre()
    script.onerror = () => rejeter(new Error('Turnstile injoignable'))
    document.head.appendChild(script)
  })
  return chargement
}

interface Props {
  /** Appele avec le jeton, ou avec une chaine vide quand il devient invalide. */
  onJeton: (jeton: string) => void
  /** Rempli avec une fonction de remise a zero du widget. */
  reinitRef?: React.MutableRefObject<(() => void) | null>
}

export function Turnstile({ onJeton, reinitRef }: Props) {
  const conteneur = useRef<HTMLDivElement>(null)
  // Le rappel passe par une reference : le mettre dans les dependances de
  // l'effet reconstruirait le widget a chaque rendu du formulaire.
  const rappel = useRef(onJeton)
  rappel.current = onJeton

  useEffect(() => {
    if (!CLE_PUBLIQUE || !conteneur.current) return
    let annule = false
    let widgetId: string | undefined

    chargerScript()
      .then(() => {
        if (annule || !conteneur.current || !window.turnstile) return
        widgetId = window.turnstile.render(conteneur.current, {
          sitekey: CLE_PUBLIQUE,
          callback: (jeton: string) => rappel.current(jeton),
          // Un jeton Turnstile est a USAGE UNIQUE et expire. Sans ces deux
          // rappels, une seconde tentative de connexion renverrait un jeton
          // deja consomme et serait refusee sans explication.
          'expired-callback': () => rappel.current(''),
          'error-callback': () => rappel.current(''),
        })
        if (reinitRef) {
          reinitRef.current = () => {
            if (widgetId && window.turnstile) {
              window.turnstile.reset(widgetId)
              rappel.current('')
            }
          }
        }
      })
      .catch(() => {
        // Cloudflare injoignable : on ne bloque pas l'utilisateur cote client.
        // C'est le serveur qui tranche, et lui refusera faute de jeton.
        rappel.current('')
      })

    return () => {
      annule = true
      if (reinitRef) reinitRef.current = null
      if (widgetId && window.turnstile) window.turnstile.remove(widgetId)
    }
  }, [reinitRef])

  if (!CLE_PUBLIQUE) return null
  return <div ref={conteneur} />
}

import { betterAuth } from 'better-auth'
import { APIError, createAuthMiddleware } from 'better-auth/api'
import { drizzleAdapter } from 'better-auth/adapters/drizzle'
import { captcha } from 'better-auth/plugins'
import { tanstackStartCookies } from 'better-auth/tanstack-start'
import { db } from '#/db'

// Turnstile n'est actif QUE si les cles sont fournies. Sans cette condition,
// le plugin refuserait toute connexion faute de jeton : le squelette serait
// inutilisable tant que l'utilisateur n'a pas ouvert un compte Cloudflare.
const cleTurnstile = process.env.TURNSTILE_SECRET_KEY
const cleTurnstilePublique = process.env.VITE_TURNSTILE_SITE_KEY

// Les deux cles vont ENSEMBLE, et on le verifie au demarrage plutot que de
// l'affirmer en commentaire :
//  - secrete seule  -> le navigateur n'envoie aucun jeton, PLUS AUCUNE
//                      connexion ne passe, et le message d'erreur ne dit pas
//                      pourquoi ;
//  - publique seule -> le widget s'affiche et rassure, mais le serveur ne
//                      verifie rien du tout.
// Les deux cas se decouvrent en production. On echoue au demarrage.
if (Boolean(cleTurnstile) !== Boolean(cleTurnstilePublique)) {
  throw new Error(
    'Turnstile est a moitie configure : ' +
      (cleTurnstile
        ? 'TURNSTILE_SECRET_KEY est definie mais VITE_TURNSTILE_SITE_KEY manque — plus aucune connexion ne passerait.'
        : 'VITE_TURNSTILE_SITE_KEY est definie mais TURNSTILE_SECRET_KEY manque — le widget rassurerait sans rien verifier.') +
      ' Definir les deux, ou aucune. Voir docs/09-captcha.md.',
  )
}

const pluginsCaptcha = cleTurnstile
  ? [captcha({ provider: 'cloudflare-turnstile', secretKey: cleTurnstile })]
  : []

// L'inscription publique est FERMÉE par défaut.
//
// Sans cela, n'importe qui trouvant l'adresse d'un outil interne peut s'y créer
// un compte. Pour un tableau de bord d'entreprise, c'est une porte ouverte —
// et sans doute le défaut le plus dangereux qu'un starter puisse livrer.
//
// Créer un compte : `./create-user.sh email@exemple.fr "Nom"`
// (le mot de passe est demandé, jamais passé en argument)
// Ouvrir l'inscription (site public, service en libre accès) : mettre
// ALLOW_PUBLIC_SIGNUP=true dans l'environnement. Décision consciente.
const publicSignupAllowed = process.env.ALLOW_PUBLIC_SIGNUP === 'true'

export const auth = betterAuth({
  // Sans cette ligne, better-auth utilise un stockage EN MÉMOIRE : les comptes
  // disparaissent à chaque redémarrage et aucune table n'est créée. L'add-on
  // better-auth de la CLI TanStack ne la génère pas — constaté en production
  // le 2026-07-26, l'application se déployait sans qu'aucune connexion ne
  // soit possible.
  database: drizzleAdapter(db, { provider: 'pg' }),
  emailAndPassword: {
    enabled: true,
  },
  hooks: {
    // Refus AVANT tout accès à la base. Un contrôle placé plus loin (sur la
    // création en base) laisse better-auth chercher l'e-mail d'abord : une
    // adresse déjà inscrite renvoie alors un code différent d'une adresse
    // inconnue, ce qui permet d'énumérer les comptes existants.
    before: createAuthMiddleware(async (ctx) => {
      if (ctx.path !== '/sign-up/email') return
      if (!publicSignupAllowed) {
        throw new APIError('BAD_REQUEST', {
          message:
            "L'inscription est fermée. Un compte doit être créé par un administrateur.",
        })
      }
    }),
  },
  advanced: {
    ipAddress: {
      // L'application est derrière Caddy : sans cette indication, better-auth
      // ne distingue pas les clients et applique sa limitation de débit à un
      // seau unique, partagé par tout le monde. Le bourrage d'identifiants
      // depuis une seule adresse passe alors sous le radar.
      ipAddressHeaders: ['x-forwarded-for', 'x-real-ip'],
    },
  },
  // Le captcha vient EN PREMIER : il doit rejeter la requete avant que le
  // reste de la chaine ne touche a la base.
  plugins: [...pluginsCaptcha, tanstackStartCookies()],
})

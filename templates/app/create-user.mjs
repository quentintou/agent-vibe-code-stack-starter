// Crée un compte utilisateur, l'inscription publique étant fermée.
//
// Exécuté dans un conteneur JETABLE (`docker compose run --rm`), avec
// ALLOW_PUBLIC_SIGNUP=true limité à ce conteneur. Le service en ligne n'est
// jamais modifié : il continue de refuser toute inscription pendant l'opération.
//
// L'e-mail et le nom arrivent par variables d'environnement, le mot de passe par
// l'entrée standard — jamais en argument de ligne de commande, où il serait
// visible dans `ps` et conservé dans l'historique du shell.
import handler from './dist/server/server.js'

const email = process.env.NEW_USER_EMAIL
const name = process.env.NEW_USER_NAME

if (!email || !name) {
  console.error('NEW_USER_EMAIL et NEW_USER_NAME sont requis.')
  process.exit(1)
}

const password = await new Promise((resolve) => {
  let data = ''
  process.stdin.setEncoding('utf8')
  process.stdin.on('data', (chunk) => (data += chunk))
  process.stdin.on('end', () => resolve(data.trim()))
})

if (password.length < 8) {
  console.error('Le mot de passe doit faire au moins 8 caractères.')
  process.exit(1)
}

// On appelle le handler de l'application directement, en mémoire : aucune
// requête ne transite par le réseau, donc rien n'est exposé publiquement.
const response = await handler.fetch(
  new Request('http://interne/api/auth/sign-up/email', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      // Sans en-tête d'adresse, better-auth émet un avertissement sur sa
      // limitation de débit — inquiétant pour rien, puisque cet appel est
      // local et n'a pas d'origine réseau. 127.0.0.1 dit la vérité : la
      // requête vient de la machine elle-même.
      'x-forwarded-for': '127.0.0.1',
    },
    body: JSON.stringify({ email, name, password }),
  }),
)

const corps = await response.text()

if (response.ok) {
  // Message technique sur la sortie d'erreur : la confirmation destinée à
  // l'utilisateur est affichée par create-user.sh, qui pilote l'opération.
  // Sans cette séparation, « Compte créé » s'affiche deux fois.
  console.error(`[create-user] inscription acceptée pour ${email}`)
  process.exit(0)
}

console.error(`Échec (HTTP ${response.status}) : ${corps.slice(0, 300)}`)
process.exit(1)

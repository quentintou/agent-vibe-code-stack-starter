// Envoie un VRAI message et affiche la réponse brute de Cloudflare.
//
// Sert à prouver que l'envoi marche, plutôt qu'à l'espérer. Un formulaire qui
// répond « merci » pendant que rien ne part est exactement le genre de panne
// que ce dépôt cherche à rendre impossible : voir docs/05-pannes.md.
//
// Usage, depuis le dossier du projet :
//   docker compose exec -T app node tester-email.mjs vous@exemple.fr
//
// Sur un plan gratuit, le destinataire doit être une adresse de destination
// VÉRIFIÉE de votre compte Cloudflare. Écrire à n'importe qui demande le plan
// Workers Paid. Voir docs/08-workers-et-emails.md.

// Doit rester identique à celui de src/lib/mail.ts — tests/test-mail.sh le vérifie.
const URL_ENVOI = 'https://api.cloudflare.com/client/v4/accounts/{account_id}/email/sending/send'

const destinataire = process.argv[2]

if (!destinataire || !destinataire.includes('@')) {
  console.error('Usage : node tester-email.mjs destinataire@exemple.fr')
  process.exit(1)
}

const compte = process.env.CF_EMAIL_ACCOUNT_ID
const jeton = process.env.CF_EMAIL_API_TOKEN
const expediteur = process.env.MAIL_FROM
const nomExpediteur = process.env.MAIL_FROM_NAME

const manquantes = [
  ['CF_EMAIL_ACCOUNT_ID', compte],
  ['CF_EMAIL_API_TOKEN', jeton],
  ['MAIL_FROM', expediteur],
]
  .filter(([, v]) => !v || v.trim() === '')
  .map(([n]) => n)

if (manquantes.length > 0) {
  console.error('Variables manquantes dans le .env du serveur :', manquantes.join(', '))
  console.error('Voir docs/08-workers-et-emails.md.')
  process.exit(1)
}

// Le schéma attend des OBJETS, pas des chaînes. Écrire `from: "Nom <a@b.fr>"`
// et `to: "a@b.fr"` fait répondre 400 « invalid_request_schema ».
const from = nomExpediteur
  ? { address: expediteur, name: nomExpediteur }
  : { address: expediteur }
const horodatage = new Date().toISOString()

console.log(`Envoi de « ${expediteur} » vers « ${destinataire} »…`)

const reponse = await fetch(URL_ENVOI.replace('{account_id}', compte), {
  method: 'POST',
  headers: {
    authorization: `Bearer ${jeton}`,
    'content-type': 'application/json',
  },
  body: JSON.stringify({
    from,
    to: [{ address: destinataire }],
    subject: `Test d'envoi — ${horodatage}`,
    text:
      "Ce message prouve que l'envoi de courrier fonctionne sur ce serveur.\n\n" +
      `Envoyé le ${horodatage}.\n`,
  }),
})

const corps = await reponse.text()

console.log(`\nHTTP ${reponse.status}`)
console.log(corps)

// Ne PAS se fier au seul code de statut : l'API v4 répond parfois 200 avec
// « success: false ». Annoncer un envoi réussi sur cette base serait exactement
// la panne que cet outil est censé rendre impossible.
let succes = reponse.ok
try {
  succes = succes && JSON.parse(corps).success !== false
} catch {
  /* corps illisible : on s'en tient au statut */
}

if (!succes) {
  console.error(
    "\nÉchec. Causes fréquentes : le domaine de MAIL_FROM n'est pas onboardé " +
      "dans Email Sending, le jeton n'a pas la permission « Email Sending: Edit », " +
      "ou le destinataire n'est pas une adresse vérifiée alors que le compte est " +
      'sur un plan gratuit.',
  )
  process.exit(1)
}

console.log(
  "\nAccepté par Cloudflare. Regardez la boîte du destinataire : « accepté » " +
    "n'est pas « distribué », et seule l'arrivée du message le prouve.",
)

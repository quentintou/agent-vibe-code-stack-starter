// Envoi de courrier via Cloudflare Email Sending.
//
// Pourquoi Cloudflare et pas un service d'envoi tiers : le domaine est déjà
// chez Cloudflare pour le DNS et le certificat. Onboarder le domaine dans
// Email Sending pose SPF, DKIM et DMARC tout seul — les trois enregistrements
// qu'on oublie et qui font finir en indésirables. Un compte de moins, une
// facture de moins, une clé de moins à faire tourner.
//
// Le service est en BÊTA (soumission ouverte en juin 2026). Envoyer vers les
// adresses de destination vérifiées de votre propre compte est gratuit sur
// tous les plans ; écrire à des destinataires quelconques demande le plan
// Workers Paid. Voir docs/08-workers-et-emails.md.
//
// L'alternative SMTP (smtp.mx.cloudflare.net:465) est documentée mais pas
// utilisée ici : l'API REST se fait avec `fetch`, donc sans dépendance.

// Doit rester identique à celui de tester-email.mjs — tests/test-mail.sh le vérifie.
const URL_ENVOI = 'https://api.cloudflare.com/client/v4/accounts/{account_id}/email/sending/send'

export interface Message {
  to: string
  subject: string
  text: string
  html?: string
}

export type Resultat = { ok: true } | { ok: false; raison: string }

const compte = process.env.CF_EMAIL_ACCOUNT_ID
const jeton = process.env.CF_EMAIL_API_TOKEN
const expediteur = process.env.MAIL_FROM
const nomExpediteur = process.env.MAIL_FROM_NAME

// Les trois valeurs vont ENSEMBLE, et on le vérifie au démarrage plutôt que de
// l'affirmer en commentaire. Même raisonnement que pour Turnstile dans auth.ts :
// une configuration à moitié remplie ne se découvre autrement qu'en production,
// le jour où le premier message aurait dû partir.
const renseignees = [compte, jeton, expediteur].filter(
  (v) => v !== undefined && v.trim() !== '',
).length

if (renseignees > 0 && renseignees < 3) {
  throw new Error(
    "Configuration d'envoi de courrier incomplète : CF_EMAIL_ACCOUNT_ID, " +
      'CF_EMAIL_API_TOKEN et MAIL_FROM vont ensemble. Renseignez les trois, ' +
      'ou aucune des trois. Voir docs/08-workers-et-emails.md.',
  )
}

/** L'envoi est-il configuré ? Faux = le squelette tourne sans, c'est prévu. */
export const envoiConfigure = renseignees === 3

/**
 * Envoie un message. Ne lève JAMAIS d'exception, et retourne toujours un
 * résultat que l'appelant est libre d'ignorer.
 *
 * Le « ne jamais lever » n'est pas de la complaisance : sur un parcours
 * d'authentification, une exception qui remonte transforme l'envoi en oracle
 * d'énumération — l'adresse inconnue répond 200, l'adresse connue dont l'envoi
 * échoue répond 500, et on lit la liste des comptes dans les codes de retour.
 *
 * En contrepartie, tout échec est journalisé côté serveur : rien ne disparaît
 * en silence.
 */
export async function envoyerMail(message: Message): Promise<Resultat> {
  if (!envoiConfigure) {
    // Pas une erreur : le squelette est utilisable sans envoi de courrier.
    console.info('[mail] non configuré — message non envoyé :', message.subject)
    return { ok: false, raison: 'envoi non configuré' }
  }

  // Le schéma attend des OBJETS, pas des chaînes. Écrire `from: "Nom <a@b.fr>"`
  // et `to: "a@b.fr"` — la forme que suggère la documentation abrégée — fait
  // répondre 400 « invalid_request_schema ». Vérifié contre l'API le 2026-07-26.
  const from = nomExpediteur
    ? { address: expediteur as string, name: nomExpediteur }
    : { address: expediteur as string }

  try {
    const reponse = await fetch(URL_ENVOI.replace('{account_id}', compte as string), {
      method: 'POST',
      headers: {
        authorization: `Bearer ${jeton as string}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: [{ address: message.to }],
        subject: message.subject,
        text: message.text,
        ...(message.html === undefined ? {} : { html: message.html }),
      }),
    })

    // Le corps porte la vraie cause (domaine non onboardé, jeton sans la
    // permission « Email Sending: Edit », destinataire non vérifié sur un plan
    // gratuit). On le journalise tronqué : il peut être long, et il ne doit
    // jamais partir vers le navigateur.
    const corps = await reponse.text().catch(() => '')

    // Ne PAS se contenter du code de statut : l'API v4 de Cloudflare répond
    // parfois 200 avec `success: false` dans le corps. Un déploiement qui
    // regarde le seul statut annonce un envoi réussi qui n'a pas eu lieu —
    // c'est la panne que ce dépôt passe son temps à traquer.
    let succes = reponse.ok
    if (succes && corps !== '') {
      try {
        succes = (JSON.parse(corps) as { success?: boolean }).success !== false
      } catch {
        // Corps illisible sur un 2xx : on ne transforme pas ça en échec, mais
        // on le laisse dans les journaux.
        console.error('[mail] réponse Cloudflare illisible :', corps.slice(0, 300))
      }
    }

    if (!succes) {
      console.error('[mail] refus Cloudflare', reponse.status, corps.slice(0, 300))
      return { ok: false, raison: `Cloudflare a répondu ${reponse.status}` }
    }

    return { ok: true }
  } catch (err) {
    console.error("[mail] échec réseau à l'envoi :", err)
    return { ok: false, raison: 'échec réseau' }
  }
}

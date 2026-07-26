// @ts-check
import { defineConfig, envField } from 'astro/config'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'

// L'adresse du site sert au sitemap et aux URLs absolues. Elle DOIT être
// remplacée par le domaine réel avant la mise en ligne : un sitemap qui
// annonce « exemple.fr » est ignoré par les moteurs de recherche.
const SITE = process.env.PUBLIC_SITE_URL ?? 'https://exemple.fr'

export default defineConfig({
  site: SITE,

  // Toutes les variables sont `optional`. C'est délibéré : le site doit se
  // construire sans aucun fichier .env, sinon l'agent ne peut rien vérifier
  // avant d'avoir obtenu des clés que l'utilisateur n'a peut-être pas encore.
  env: {
    schema: {
      PUBLIC_SITE_URL: envField.string({ context: 'client', access: 'public', optional: true }),
      PUBLIC_PLAUSIBLE_DOMAIN: envField.string({ context: 'client', access: 'public', optional: true }),
    },
  },

  integrations: [sitemap()],

  vite: {
    plugins: [tailwindcss()],
  },
})

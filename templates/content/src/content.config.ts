import { defineCollection } from 'astro:content'
// `z` vient de `astro/zod` et non de `astro:content` : ce dernier chemin est
// déprécié depuis Astro 6 et déclenche un avertissement TypeScript.
import { z } from 'astro/zod'
import { glob } from 'astro/loaders'

// Les articles vivent dans src/content/blog/*.md. Le schéma est volontairement
// court : chaque champ ajouté ici devient un champ obligatoire à remplir dans
// CHAQUE article. N'ajoute un champ que lorsqu'une page s'en sert réellement.
const blog = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/blog' }),
  schema: z.object({
    title: z.string().min(1),
    description: z.string().min(1),
    publishedAt: z.date(),
    updatedAt: z.date().optional(),
    // Un article daté dans le futur n'est pas publié : voir getArticlesPublies().
    draft: z.boolean().default(false),
  }),
})

export const collections = { blog }

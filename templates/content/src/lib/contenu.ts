import { getCollection } from 'astro:content'

// Un article est publié s'il n'est pas un brouillon ET si sa date est passée.
// Sans ce filtre, un article daté de la semaine prochaine apparaît en ligne dès
// la construction — la panne la plus courante d'un blog statique.
//
// En développement, tout est affiché : sinon on ne peut pas relire un article
// avant sa date de publication.
export async function getArticlesPublies() {
  const maintenant = new Date()
  const articles = await getCollection('blog', ({ data }) => {
    if (import.meta.env.DEV) return true
    return !data.draft && data.publishedAt <= maintenant
  })
  return articles.sort(
    (a, b) => b.data.publishedAt.valueOf() - a.data.publishedAt.valueOf(),
  )
}

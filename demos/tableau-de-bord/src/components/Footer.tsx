export default function Footer() {
  return (
    <footer className="mt-16 border-t border-[var(--line)] px-4 py-8">
      <div className="page-wrap text-sm text-[var(--sea-ink-soft)]">
        <p className="font-medium">
          Cette application a été déployée par le dépôt qu'elle démontre.
        </p>
        <p className="mt-1.5 max-w-2xl">
          TanStack Start, Postgres et better-auth dans des conteneurs, sur un serveur à
          5 € par mois, derrière Caddy — construit à distance par un script, sur le même
          serveur que le site de contenu.
        </p>
        <p className="mt-4">
          <a href="https://github.com/quentintou/agent-vibe-code-stack-starter" className="underline underline-offset-4">
            agent-vibe-code-stack-starter
          </a>
          {' — licence MIT.'}
        </p>
      </div>
    </footer>
  )
}

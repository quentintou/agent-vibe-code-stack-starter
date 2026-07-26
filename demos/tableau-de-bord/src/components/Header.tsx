import { Link } from '@tanstack/react-router'
import ThemeToggle from './ThemeToggle'

export default function Header() {
  return (
    <header className="sticky top-0 z-50 border-b border-[var(--line)] bg-[var(--header-bg)] px-4 backdrop-blur-lg">
      <nav className="page-wrap flex flex-wrap items-center justify-between gap-x-4 gap-y-2 py-3 sm:py-4">
        <Link to="/" className="flex items-center gap-2.5 text-sm font-semibold no-underline">
          <span className="inline-block h-2.5 w-2.5 rounded-full bg-emerald-600" />
          Tableau de bord d'équipe
          <span className="rounded bg-[rgba(79,184,178,0.16)] px-1.5 py-0.5 text-[0.65rem] font-medium tracking-wide uppercase">
            démo
          </span>
        </Link>

        <div className="flex items-center gap-4 text-sm">
          <a href="https://contenu.app-run.pro" className="no-underline hover:underline">
            Le principe
          </a>
          <a
            href="https://github.com/quentintou/agent-vibe-code-stack-starter"
            target="_blank"
            rel="noopener noreferrer"
            className="no-underline hover:underline"
          >
            Le dépôt
          </a>
          <ThemeToggle />
        </div>
      </nav>
    </header>
  )
}

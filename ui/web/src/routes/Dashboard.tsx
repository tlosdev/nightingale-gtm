import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';

export default function Dashboard() {
  // /api/health is near-static (just verifies signals dir presence). Cache it
  // long so tab-switching doesn't spam the disk for nothing.
  const health = useQuery({
    queryKey: ['health'],
    queryFn: api.health,
    staleTime: 5 * 60 * 1000,
    refetchOnWindowFocus: false,
  });
  const pending = useQuery({ queryKey: ['pending'], queryFn: api.pending });
  const brief = useQuery({ queryKey: ['brief', 'today'], queryFn: api.briefToday });
  const mcp = useQuery({ queryKey: ['diagnostics', 'mcp'], queryFn: api.diagnosticsMcp });

  const noSignalsTree = health.data && !health.data.signals_dir_found;

  return (
    <div className="p-6 space-y-6 max-w-5xl">
      <header>
        <h1 className="text-2xl font-semibold">Dashboard</h1>
        <p className="text-sm text-gray-500 mt-1">
          Single-pane view of the GTM chain. All data comes from{' '}
          <code className="text-xs">{health.data?.signals_dir ?? '~/Desktop/nightingale-signals/'}</code>.
        </p>
      </header>

      {noSignalsTree && (
        <EmptyStateBanner />
      )}

      <section className="grid grid-cols-3 gap-3">
        <StatCard
          label="Pending HubSpot approvals"
          value={pending.data?.counts.total ?? 0}
          href="/pending"
          accent={(pending.data?.counts.total ?? 0) > 0}
        />
        <StatCard
          label="MCP connectors"
          value={mcp.data ? `${mcp.data.mcp_status.filter((m) => m.authorized).length}/${mcp.data.mcp_status.length} OK` : '—'}
          href="/diagnostics"
          accent={mcp.data ? mcp.data.mcp_status.some((m) => !m.authorized) : false}
        />
        <StatCard
          label="Today's brief"
          value={brief.data?.found ? 'Ready' : 'Not yet'}
          href="/brief"
        />
      </section>

      <section>
        <div className="flex items-baseline justify-between mb-3">
          <h2 className="text-lg font-medium">Today's brief</h2>
          <Link to="/brief" className="text-sm text-accent-600 hover:underline dark:text-accent-500">
            Full view →
          </Link>
        </div>
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
          {brief.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
          {brief.data?.found && brief.data.raw_markdown && (
            <MarkdownRenderer markdown={brief.data.raw_markdown} />
          )}
          {brief.data && !brief.data.found && (
            <p className="text-sm text-gray-500">{brief.data.message}</p>
          )}
        </div>
      </section>
    </div>
  );
}

function StatCard({ label, value, href, accent }: { label: string; value: string | number; href: string; accent?: boolean }) {
  return (
    <Link
      to={href}
      className={`block rounded-lg border p-4 transition-colors ${
        accent
          ? 'border-amber-500/40 bg-amber-500/5 hover:bg-amber-500/10'
          : 'border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800'
      }`}
    >
      <div className="text-xs uppercase tracking-wide text-gray-500">{label}</div>
      <div className="mt-1 text-2xl font-semibold">{value}</div>
    </Link>
  );
}

function EmptyStateBanner() {
  return (
    <div className="rounded-lg border border-accent-500/30 bg-accent-500/5 p-4">
      <h2 className="font-semibold mb-2">Welcome — first-run setup</h2>
      <p className="text-sm text-gray-600 dark:text-gray-400 mb-3">
        No agent output found on this machine yet. Follow the punch list in the repo README, then come back here.
      </p>
      <ol className="text-sm list-decimal list-inside space-y-1 text-gray-700 dark:text-gray-300">
        <li>Verify Node 18+, Git, Claude Code on PATH.</li>
        <li><code>Set-ExecutionPolicy RemoteSigned -Scope CurrentUser</code> (one-time).</li>
        <li>Authorize the MCP connectors in Claude Code (Settings → Connectors).</li>
        <li>Run <code>.\scripts\install-schedule.ps1</code>.</li>
        <li>(Optional) <code>.\scripts\setup-secrets.ps1</code> for intro-finder + daily-brief Layer-B.</li>
        <li>Use the Agents view to trigger the first sweeps manually.</li>
      </ol>
    </div>
  );
}

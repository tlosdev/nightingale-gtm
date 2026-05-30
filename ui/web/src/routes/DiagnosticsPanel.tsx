import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';

export default function DiagnosticsPanel() {
  const mcp = useQuery({ queryKey: ['diagnostics', 'mcp'], queryFn: api.diagnosticsMcp });
  const tasks = useQuery({ queryKey: ['diagnostics', 'tasks'], queryFn: api.diagnosticsTasks });
  const secrets = useQuery({ queryKey: ['diagnostics', 'secrets'], queryFn: api.diagnosticsSecrets });

  return (
    <div className="p-6 max-w-5xl space-y-6">
      <header>
        <h1 className="text-2xl font-semibold">Diagnostics</h1>
      </header>

      <section>
        <h2 className="text-lg font-medium mb-2">MCP connectors</h2>
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-gray-800 text-xs uppercase">
              <tr>
                <th className="px-3 py-2 text-left">Connector</th>
                <th className="px-3 py-2 text-left">Status</th>
                <th className="px-3 py-2 text-left">Last notice</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200 dark:divide-gray-800">
              {mcp.data?.mcp_status.map((m) => (
                <tr key={m.connector}>
                  <td className="px-3 py-2">{m.connector}</td>
                  <td className="px-3 py-2">
                    {m.authorized ? (
                      <span className="text-green-700 dark:text-green-400">✓ no recent notice</span>
                    ) : (
                      <span className="text-amber-700 dark:text-amber-400">⚠ unauthorized</span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-xs text-gray-500">
                    {m.last_notice_at ? `${m.last_notice_at} (${m.last_notice_path})` : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-2 text-xs text-gray-500">
          Detection is heuristic: an unauthorized connector is one that emitted a NOT_AUTHORIZED notice in the last
          7 days. Older notices may be stale (you may have already fixed the issue).
        </p>
      </section>

      <section>
        <h2 className="text-lg font-medium mb-2">Scheduled tasks</h2>
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 overflow-hidden">
          {tasks.error && <p className="p-3 text-sm text-amber-700 dark:text-amber-400">Could not read scheduled tasks (PowerShell unavailable?).</p>}
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-gray-800 text-xs uppercase">
              <tr>
                <th className="px-3 py-2 text-left">Task</th>
                <th className="px-3 py-2 text-left">State</th>
                <th className="px-3 py-2 text-left">Last run</th>
                <th className="px-3 py-2 text-left">Next run</th>
                <th className="px-3 py-2 text-left">Last result</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200 dark:divide-gray-800">
              {tasks.data?.tasks.map((t) => (
                <tr key={t.name}>
                  <td className="px-3 py-2 font-mono text-xs">{t.name}</td>
                  <td className="px-3 py-2">{t.state}</td>
                  <td className="px-3 py-2 text-xs text-gray-500">{t.last_run_time ? new Date(t.last_run_time).toLocaleString() : '—'}</td>
                  <td className="px-3 py-2 text-xs text-gray-500">{t.next_run_time ? new Date(t.next_run_time).toLocaleString() : '—'}</td>
                  <td className="px-3 py-2 text-xs text-gray-500">{t.last_task_result === 0 ? '✓ 0' : (t.last_task_result?.toString() ?? '—')}</td>
                </tr>
              ))}
              {tasks.data && tasks.data.tasks.length === 0 && (
                <tr><td colSpan={5} className="px-3 py-4 text-sm text-gray-500 text-center">No Nightingale-* tasks registered. Run <code>.\scripts\install-schedule.ps1</code>.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 className="text-lg font-medium mb-2">Secrets file</h2>
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
          {secrets.data && !secrets.data.exists && (
            <p className="text-sm text-gray-500">No secrets file at <code>~/.nightingale/secrets.json</code>. Intro-finder + daily-brief Layer-B disabled. Run <code>.\scripts\setup-secrets.ps1</code> to populate.</p>
          )}
          {secrets.data?.exists && (
            <dl className="text-sm grid grid-cols-2 gap-x-4 gap-y-1">
              <dt className="text-gray-500">Schema version</dt>
              <dd>{secrets.data.schema_version ?? '—'}</dd>
              <dt className="text-gray-500">Updated</dt>
              <dd>{secrets.data.updated_at ?? '—'}</dd>
              <Field label="apify_api_token" present={secrets.data.has_apify_api_token} />
              <Field label="apify_actor_id" present={secrets.data.has_apify_actor_id} />
              <Field label="apify_validation_url" present={secrets.data.has_apify_validation_url} />
              <Field label="linkedin_li_at" present={secrets.data.has_linkedin_li_at} />
              <Field label="apify_company_roster_actor_id (optional)" present={secrets.data.has_apify_company_roster_actor_id} />
            </dl>
          )}
          <p className="mt-3 text-xs text-gray-500">
            This panel shows presence-of-fields only — actual token / cookie values are never sent to this UI.
          </p>
        </div>
      </section>
    </div>
  );
}

function Field({ label, present }: { label: string; present: boolean }) {
  return (
    <>
      <dt className="text-gray-500 font-mono text-xs">{label}</dt>
      <dd>{present ? <span className="text-green-700 dark:text-green-400">✓ set</span> : <span className="text-gray-500">—</span>}</dd>
    </>
  );
}

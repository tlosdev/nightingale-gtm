import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api, RunRecord, RunStatus } from '../lib/api';

const STATUS_STYLE: Record<RunStatus, string> = {
  running: 'text-blue-700 dark:text-blue-300',
  ok: 'text-green-700 dark:text-green-400',
  error: 'text-red-700 dark:text-red-400',
  timeout: 'text-amber-700 dark:text-amber-400',
};

const STATUS_ICON: Record<RunStatus, string> = {
  running: '●',
  ok: '✓',
  error: '✗',
  timeout: '⏱',
};

export default function Logs() {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Poll the run list while anything is running so freshly-started runs and
  // status transitions appear without a manual refresh.
  const runs = useQuery({
    queryKey: ['runs'],
    queryFn: api.runs,
    refetchInterval: (q) => (q.state.data?.runs.some((r) => r.status === 'running') ? 2000 : 10000),
  });
  const tasks = useQuery({ queryKey: ['diagnostics', 'tasks'], queryFn: api.diagnosticsTasks });

  const runList = runs.data?.runs ?? [];
  const activeId = selectedId ?? runList[0]?.id ?? null;

  return (
    <div className="p-6 max-w-6xl">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold">Logs</h1>
        <p className="text-sm text-gray-500 mt-1">
          Manual runs (Run-now, Apply/Reject) and their live output, plus scheduled-task last results.
        </p>
      </header>

      <div className="grid grid-cols-[20rem_1fr] gap-6">
        <aside className="space-y-1">
          <h2 className="text-xs uppercase tracking-wide text-gray-500 mb-1">Recent runs</h2>
          {runs.isLoading && <p className="text-xs text-gray-500">Loading…</p>}
          {!runs.isLoading && runList.length === 0 && (
            <p className="text-xs text-gray-500">No runs yet. Start one from the Agents tab.</p>
          )}
          {runList.map((r) => (
            <RunListItem key={r.id} run={r} active={r.id === activeId} onClick={() => setSelectedId(r.id)} />
          ))}
        </aside>

        <div className="space-y-6">
          {activeId ? (
            <RunDetailPane id={activeId} />
          ) : (
            <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6 text-sm text-gray-500">
              Select a run to view its output.
            </div>
          )}

          {/* Scheduled tasks */}
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
        </div>
      </div>
    </div>
  );
}

function RunListItem({ run, active, onClick }: { run: RunRecord; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`w-full text-left px-3 py-2 rounded transition-colors ${
        active ? 'bg-accent-500/10' : 'hover:bg-gray-100 dark:hover:bg-gray-800'
      }`}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-sm font-medium truncate">{run.label}</span>
        <span className={`text-xs ${STATUS_STYLE[run.status]}`}>{STATUS_ICON[run.status]} {run.status}</span>
      </div>
      <div className="text-xs text-gray-500">
        {new Date(run.started_at).toLocaleString()}
        {run.duration_ms != null && ` · ${(run.duration_ms / 1000).toFixed(1)}s`}
      </div>
    </button>
  );
}

function RunDetailPane({ id }: { id: string }) {
  const detail = useQuery({
    queryKey: ['run', id],
    queryFn: () => api.runDetail(id),
    // Live-tail while running; stop polling once settled.
    refetchInterval: (q) => (q.state.data?.run.status === 'running' ? 1500 : false),
  });

  const run = detail.data?.run;
  return (
    <section className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
      {detail.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
      {detail.error && <p className="text-sm text-red-500">Run not found.</p>}
      {run && (
        <>
          <div className="flex items-center justify-between mb-2">
            <div className="min-w-0">
              <h2 className="font-semibold truncate">{run.label}</h2>
              <code className="text-xs text-gray-500">{run.phrase}</code>
            </div>
            <span className={`text-sm font-medium shrink-0 ${STATUS_STYLE[run.status]}`}>
              {STATUS_ICON[run.status]} {run.status}
              {run.exit_code != null && run.status !== 'running' && ` (exit ${run.exit_code})`}
            </span>
          </div>
          <pre className="mt-2 p-3 bg-gray-50 dark:bg-gray-950 text-xs overflow-x-auto rounded border border-gray-200 dark:border-gray-800 max-h-[28rem] whitespace-pre-wrap">
            {detail.data?.log_tail || '(no output captured yet)'}
          </pre>
        </>
      )}
    </section>
  );
}

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, AgentSummary } from '../lib/api';

export default function AgentsControlPanel() {
  const qc = useQueryClient();
  const agents = useQuery({ queryKey: ['agents'], queryFn: api.agents });

  return (
    <div className="p-6 max-w-5xl">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold">Agents</h1>
        <p className="text-sm text-gray-500 mt-1">
          Trigger an agent on demand. Each "Run now" invokes the same{' '}
          <code className="text-xs">claude -p &quot;...&quot;</code> phrase the scheduled task would.
          Scheduled tasks continue firing on their own cadence regardless.
        </p>
      </header>
      {agents.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
      {agents.data && (
        <div className="space-y-3">
          {agents.data.agents.map((agent) => (
            <AgentCard key={agent.name} agent={agent} onRun={() => qc.invalidateQueries({ queryKey: ['agents'] })} />
          ))}
        </div>
      )}
    </div>
  );
}

function AgentCard({ agent, onRun }: { agent: AgentSummary; onRun: () => void }) {
  const [result, setResult] = useState<{ ok: boolean; stdout: string; stderr: string } | null>(null);
  const runMutation = useMutation({
    mutationFn: () => api.agentRun(agent.name),
    onSuccess: (r) => {
      setResult({ ok: r.ok, stdout: r.stdout, stderr: r.stderr });
      onRun();
    },
  });

  return (
    <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <h2 className="font-semibold">{agent.name}</h2>
          <p className="text-xs text-gray-500 mt-1">
            Trigger: <code>{agent.trigger_phrase}</code>
          </p>
          <dl className="mt-2 text-xs grid grid-cols-2 gap-x-4 gap-y-1 text-gray-600 dark:text-gray-400">
            {agent.scheduled_task_name && (
              <>
                <dt className="text-gray-500">Scheduled task</dt>
                <dd>{agent.scheduled_task_state ?? 'not registered'}</dd>
                <dt className="text-gray-500">Last run</dt>
                <dd>{agent.last_run_time ? new Date(agent.last_run_time).toLocaleString() : 'never'}</dd>
                <dt className="text-gray-500">Next run</dt>
                <dd>{agent.next_run_time ? new Date(agent.next_run_time).toLocaleString() : '—'}</dd>
              </>
            )}
            {!agent.scheduled_task_name && (
              <>
                <dt className="text-gray-500">Scheduled</dt>
                <dd>on-demand only</dd>
              </>
            )}
            <dt className="text-gray-500">Last output</dt>
            <dd>{agent.last_output_generated_at ? new Date(agent.last_output_generated_at).toLocaleString() : 'none'}</dd>
          </dl>
        </div>
        <button
          type="button"
          disabled={runMutation.isPending}
          onClick={() => runMutation.mutate()}
          className="shrink-0 px-3 py-1.5 text-sm font-medium rounded bg-accent-600 hover:bg-accent-700 text-white disabled:opacity-50"
        >
          {runMutation.isPending ? 'Running…' : 'Run now'}
        </button>
      </div>
      {result && (
        <div className={`mt-3 p-2 text-xs rounded border ${
          result.ok
            ? 'border-green-500/30 bg-green-500/5 text-green-800 dark:text-green-300'
            : 'border-red-500/30 bg-red-500/5 text-red-800 dark:text-red-300'
        }`}>
          <p className="font-medium">{result.ok ? '✓ Success' : '✗ Failed'}</p>
          {result.stdout && <pre className="mt-1 overflow-x-auto max-h-40">{result.stdout.slice(-1500)}</pre>}
          {result.stderr && <pre className="mt-1 overflow-x-auto max-h-32 text-red-700 dark:text-red-400">{result.stderr.slice(-800)}</pre>}
        </div>
      )}
    </article>
  );
}

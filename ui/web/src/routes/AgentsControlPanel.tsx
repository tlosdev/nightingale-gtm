import { Link } from 'react-router-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, AgentSummary } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';
import { useContainerMode, CONTAINER_DISABLED_HINT } from '../lib/useRunMode';

export default function AgentsControlPanel() {
  const agents = useQuery({ queryKey: ['agents'], queryFn: api.agents });

  return (
    <div className="p-6 max-w-5xl">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold">Agents</h1>
        <p className="text-sm text-gray-500 mt-1">
          Trigger an agent on demand. "Run now" starts a background run and returns immediately — watch it stream in
          the <Link to="/logs" className="text-accent-600 dark:text-accent-500 hover:underline">Logs</Link> tab.
          Scheduled tasks keep firing on their own cadence regardless.
        </p>
      </header>
      {agents.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
      {agents.data && (
        <div className="space-y-3">
          {agents.data.agents.map((agent) => (
            <AgentCard key={agent.name} agent={agent} />
          ))}
        </div>
      )}
    </div>
  );
}

function AgentCard({ agent }: { agent: AgentSummary }) {
  const qc = useQueryClient();
  const containerMode = useContainerMode();
  const [started, setStarted] = useState<{ run_id: string } | null>(null);
  const [showOutput, setShowOutput] = useState(false);

  const runMutation = useMutation({
    mutationFn: () => api.agentRun(agent.name),
    onSuccess: (r) => {
      setStarted({ run_id: r.run_id });
      // A new run now exists — refresh the Logs list so it shows up there too.
      qc.invalidateQueries({ queryKey: ['runs'] });
    },
  });

  const output = useQuery({
    queryKey: ['agent-output', agent.name],
    queryFn: () => api.agentOutput(agent.name),
    enabled: showOutput,
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
        <div className="flex flex-col gap-1 shrink-0">
          <button
            type="button"
            disabled={runMutation.isPending || containerMode}
            title={containerMode ? CONTAINER_DISABLED_HINT : undefined}
            onClick={() => runMutation.mutate()}
            className="px-3 py-1.5 text-sm font-medium rounded bg-accent-600 hover:bg-accent-700 text-white disabled:opacity-50"
          >
            {runMutation.isPending ? 'Starting…' : 'Run now'}
          </button>
          <button
            type="button"
            onClick={() => setShowOutput((v) => !v)}
            className="px-3 py-1.5 text-sm rounded border border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800"
          >
            {showOutput ? 'Hide output' : 'View output'}
          </button>
        </div>
      </div>

      {started && (
        <div className="mt-3 p-2 text-xs rounded border border-blue-500/30 bg-blue-500/5 text-blue-800 dark:text-blue-300">
          Run started (<code>{started.run_id}</code>).{' '}
          <Link to="/logs" className="underline">Open Logs →</Link>
        </div>
      )}
      {runMutation.error && (
        <div className="mt-3 p-2 text-xs rounded border border-red-500/30 bg-red-500/5 text-red-800 dark:text-red-300">
          Failed to start: {(runMutation.error as Error).message}
        </div>
      )}

      {showOutput && (
        <div className="mt-3 p-3 rounded border border-gray-200 dark:border-gray-800 bg-gray-50 dark:bg-gray-950">
          {output.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
          {output.data && !output.data.found && <p className="text-sm text-gray-500">{output.data.message ?? 'No output yet.'}</p>}
          {output.data?.found && output.data.raw_markdown && <MarkdownRenderer markdown={output.data.raw_markdown} />}
        </div>
      )}
    </article>
  );
}

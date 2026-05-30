import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, PendingItem } from '../lib/api';

export default function PendingQueueView() {
  const qc = useQueryClient();
  const pending = useQuery({ queryKey: ['pending'], queryFn: api.pending });
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [filter, setFilter] = useState<string>('');
  const [actionResult, setActionResult] = useState<{ phrase: string; ok: boolean; stdout: string; stderr: string } | null>(null);

  const applyMutation = useMutation({
    mutationFn: ({ ids, run_date }: { ids: number[] | 'all'; run_date: string }) => api.pendingApply(ids, run_date),
    onSuccess: (result) => {
      setActionResult({ phrase: result.phrase, ok: result.ok, stdout: result.stdout, stderr: result.stderr });
      qc.invalidateQueries({ queryKey: ['pending'] });
      setSelected(new Set());
    },
  });

  const rejectMutation = useMutation({
    mutationFn: ({ ids, run_date }: { ids: number[] | 'all'; run_date: string }) => api.pendingReject(ids, run_date),
    onSuccess: (result) => {
      setActionResult({ phrase: result.phrase, ok: result.ok, stdout: result.stdout, stderr: result.stderr });
      qc.invalidateQueries({ queryKey: ['pending'] });
      setSelected(new Set());
    },
  });

  const items = pending.data?.pending ?? [];
  const filtered = filter
    ? items.filter((i) =>
        [i.action_type, i.rationale, i.target_object.label ?? '', i.target_object.id ?? '']
          .join(' ')
          .toLowerCase()
          .includes(filter.toLowerCase()),
      )
    : items;

  const groupedByDate = filtered.reduce<Record<string, PendingItem[]>>((acc, item) => {
    (acc[item.run_date] ??= []).push(item);
    return acc;
  }, {});

  const handleAction = (verb: 'apply' | 'reject', ids: PendingItem[]) => {
    // Group selected by run_date — one mutation per date since the trigger phrase requires a single date.
    const byDate = ids.reduce<Record<string, number[]>>((acc, it) => {
      const seq = parseInt(it.pending_id.split('-').pop() ?? '', 10);
      if (!isNaN(seq)) (acc[it.run_date] ??= []).push(seq);
      return acc;
    }, {});
    for (const [run_date, numericIds] of Object.entries(byDate)) {
      if (verb === 'apply') applyMutation.mutate({ ids: numericIds, run_date });
      else rejectMutation.mutate({ ids: numericIds, run_date });
    }
  };

  const selectedItems = items.filter((i) => selected.has(i.pending_id));

  return (
    <div className="p-6 max-w-6xl">
      <header className="mb-4 flex items-baseline justify-between">
        <h1 className="text-2xl font-semibold">Pending Approvals</h1>
        <span className="text-xs text-gray-500">{filtered.length} of {items.length} items</span>
      </header>

      <div className="mb-4 flex items-center gap-3">
        <input
          type="text"
          placeholder="Filter by action / target / rationale…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          className="flex-1 px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-700 rounded bg-white dark:bg-gray-900"
        />
        {selectedItems.length > 0 && (
          <>
            <button
              type="button"
              disabled={applyMutation.isPending}
              onClick={() => handleAction('apply', selectedItems)}
              className="px-3 py-1.5 text-sm font-medium rounded bg-accent-600 hover:bg-accent-700 text-white disabled:opacity-50"
            >
              Apply {selectedItems.length}
            </button>
            <button
              type="button"
              disabled={rejectMutation.isPending}
              onClick={() => handleAction('reject', selectedItems)}
              className="px-3 py-1.5 text-sm font-medium rounded border border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-50"
            >
              Reject {selectedItems.length}
            </button>
          </>
        )}
      </div>

      {actionResult && (
        <div className={`mb-4 p-3 rounded border text-sm ${
          actionResult.ok
            ? 'border-green-500/30 bg-green-500/5 text-green-800 dark:text-green-300'
            : 'border-red-500/30 bg-red-500/5 text-red-800 dark:text-red-300'
        }`}>
          <p className="font-medium mb-1">{actionResult.ok ? '✓' : '✗'} <code>{actionResult.phrase}</code></p>
          {actionResult.stdout && <pre className="text-xs overflow-x-auto mt-2">{actionResult.stdout.slice(-2000)}</pre>}
          {actionResult.stderr && <pre className="text-xs overflow-x-auto mt-2 text-red-700 dark:text-red-400">{actionResult.stderr.slice(-1000)}</pre>}
          <button onClick={() => setActionResult(null)} className="mt-2 text-xs underline">dismiss</button>
        </div>
      )}

      {pending.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
      {!pending.isLoading && items.length === 0 && (
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 p-6 bg-white dark:bg-gray-900 text-center text-sm text-gray-500">
          No pending HubSpot updates. The nightly hubspot-manager run will populate this list.
        </div>
      )}

      {Object.entries(groupedByDate).sort(([a], [b]) => b.localeCompare(a)).map(([date, dayItems]) => (
        <section key={date} className="mb-6">
          <h2 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">{date}  <span className="font-normal text-gray-500">({dayItems.length})</span></h2>
          <div className="space-y-2">
            {dayItems.map((item) => (
              <PendingRow
                key={item.pending_id}
                item={item}
                selected={selected.has(item.pending_id)}
                onToggle={() => {
                  const next = new Set(selected);
                  if (next.has(item.pending_id)) next.delete(item.pending_id);
                  else next.add(item.pending_id);
                  setSelected(next);
                }}
                onApply={() => handleAction('apply', [item])}
                onReject={() => handleAction('reject', [item])}
                isPending={applyMutation.isPending || rejectMutation.isPending}
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function PendingRow({
  item,
  selected,
  onToggle,
  onApply,
  onReject,
  isPending,
}: {
  item: PendingItem;
  selected: boolean;
  onToggle: () => void;
  onApply: () => void;
  onReject: () => void;
  isPending: boolean;
}) {
  const [showSource, setShowSource] = useState(false);
  return (
    <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-3 text-sm">
      <div className="flex items-start gap-3">
        <input type="checkbox" checked={selected} onChange={onToggle} className="mt-1" />
        <div className="flex-1 min-w-0">
          <div className="flex items-baseline gap-2 flex-wrap">
            <code className="text-xs text-gray-500">#{item.pending_id}</code>
            <span className="text-xs font-medium px-1.5 py-0.5 rounded bg-gray-100 dark:bg-gray-800">{item.action_type}</span>
            <span className="font-medium">
              {item.target_object.label ?? item.target_object.id ?? item.target_object.id_or_email ?? item.target_object.type}
            </span>
          </div>
          <p className="mt-1 text-gray-700 dark:text-gray-300">{item.rationale}</p>
          <p className="mt-1 text-xs text-gray-500">{item.queue_reason}</p>
          {item.source_quotes.length > 0 && (
            <details className="mt-2">
              <summary className="text-xs text-gray-500 cursor-pointer hover:text-gray-700 dark:hover:text-gray-300">
                {item.source_quotes.length} source quote{item.source_quotes.length !== 1 ? 's' : ''}
              </summary>
              <ul className="mt-1 text-xs space-y-1 list-disc list-inside text-gray-600 dark:text-gray-400">
                {item.source_quotes.map((q, idx) => (
                  <li key={idx}>"{q}"</li>
                ))}
              </ul>
            </details>
          )}
          {showSource && (
            <pre className="mt-2 p-2 bg-gray-50 dark:bg-gray-950 text-xs overflow-x-auto rounded border border-gray-200 dark:border-gray-800">
              {JSON.stringify(item.payload, null, 2)}
            </pre>
          )}
        </div>
        <div className="flex flex-col gap-1 shrink-0">
          <button
            type="button"
            disabled={isPending}
            onClick={onApply}
            className="px-2 py-1 text-xs font-medium rounded bg-accent-600 hover:bg-accent-700 text-white disabled:opacity-50"
          >
            Apply
          </button>
          <button
            type="button"
            disabled={isPending}
            onClick={onReject}
            className="px-2 py-1 text-xs font-medium rounded border border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-50"
          >
            Reject
          </button>
          <button
            type="button"
            onClick={() => setShowSource(!showSource)}
            className="px-2 py-1 text-xs text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
          >
            {showSource ? 'Hide' : 'JSON'}
          </button>
        </div>
      </div>
    </article>
  );
}

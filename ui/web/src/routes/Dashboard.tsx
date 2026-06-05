import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, ApprovalItem, ApprovalCategory } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';

// Settle delay before invalidating: the claude subprocess writes
// approval-history.jsonl as it exits, but Windows filesystem buffering can race
// the cache-keying mtime read. 500ms is above flush latency, below perceptible.
const SETTLE_MS = 500;

const CATEGORY_LABELS: Record<ApprovalCategory, string> = {
  hubspot: 'HubSpot',
  'pitch-deck': 'Pitch Deck',
  newsletter: 'Newsletter',
};

const CATEGORY_CHIP: Record<ApprovalCategory, string> = {
  hubspot: 'bg-blue-500/15 text-blue-700 dark:text-blue-300',
  'pitch-deck': 'bg-purple-500/15 text-purple-700 dark:text-purple-300',
  newsletter: 'bg-teal-500/15 text-teal-700 dark:text-teal-300',
};

function seqOf(item: ApprovalItem): number {
  return parseInt(item.pending_id.split('-').pop() ?? '', 10);
}

// Route one item's decision to the correct existing per-queue endpoint by
// category. HubSpot uses /api/pending; pitch-deck + newsletter use /api/queues.
function decide(verb: 'apply' | 'reject', item: ApprovalItem): Promise<unknown> {
  const seq = seqOf(item);
  if (item.category === 'hubspot') {
    const ids = Number.isNaN(seq) ? ('all' as const) : [seq];
    return verb === 'apply' ? api.pendingApply(ids, item.run_date) : api.pendingReject(ids, item.run_date);
  }
  if (item.category === 'pitch-deck') {
    const ids = Number.isNaN(seq) ? ('all' as const) : [seq];
    return verb === 'apply'
      ? api.queueApply('pitch-deck', item.run_date, ids)
      : api.queueReject('pitch-deck', item.run_date, ids);
  }
  // newsletter — single-item queue, no id list.
  return verb === 'apply'
    ? api.queueApply('newsletter', item.run_date)
    : api.queueReject('newsletter', item.run_date);
}

export default function Dashboard() {
  const qc = useQueryClient();
  const approvals = useQuery({ queryKey: ['approvals'], queryFn: api.approvals });
  const resurfacer = useQuery({ queryKey: ['resurfacer', 'latest'], queryFn: api.resurfacerLatest });
  const brief = useQuery({ queryKey: ['brief', 'today'], queryFn: api.briefToday });

  const [categoryFilter, setCategoryFilter] = useState<ApprovalCategory | 'all'>('all');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: ({ verb, item }: { verb: 'apply' | 'reject'; item: ApprovalItem }) => decide(verb, item),
    onMutate: ({ item }) => {
      setBusyId(item.pending_id);
      setActionError(null);
    },
    onSuccess: async () => {
      await new Promise((r) => setTimeout(r, SETTLE_MS));
      qc.invalidateQueries({ queryKey: ['approvals'] });
    },
    onError: (err) => {
      setActionError((err as Error).message);
    },
    onSettled: () => setBusyId(null),
  });

  const items = approvals.data?.approvals ?? [];
  const counts = approvals.data?.counts.by_category ?? {};
  const filtered = categoryFilter === 'all' ? items : items.filter((i) => i.category === categoryFilter);

  return (
    <div className="p-6 space-y-8 max-w-5xl">
      <header>
        <h1 className="text-2xl font-semibold">Dashboard</h1>
        <p className="text-sm text-gray-500 mt-1">
          Everything awaiting your decision, plus today's re-surfaced contacts and brief.
        </p>
      </header>

      {/* ===== Pending Approvals ===== */}
      <section>
        <div className="flex items-baseline justify-between mb-3">
          <h2 className="text-lg font-medium">
            Pending approvals{' '}
            <span className="text-sm font-normal text-gray-500">({items.length})</span>
          </h2>
          <div className="flex gap-1">
            <FilterChip label="All" active={categoryFilter === 'all'} onClick={() => setCategoryFilter('all')} count={items.length} />
            {(Object.keys(CATEGORY_LABELS) as ApprovalCategory[]).map((c) => (
              <FilterChip
                key={c}
                label={CATEGORY_LABELS[c]}
                active={categoryFilter === c}
                onClick={() => setCategoryFilter(c)}
                count={counts[c] ?? 0}
              />
            ))}
          </div>
        </div>

        {actionError && (
          <div className="mb-3 p-3 rounded border border-red-500/30 bg-red-500/5 text-sm text-red-800 dark:text-red-300">
            <p className="font-medium">Action failed</p>
            <p className="text-xs mt-1">{actionError}</p>
            <button onClick={() => setActionError(null)} className="mt-2 text-xs underline">dismiss</button>
          </div>
        )}

        {approvals.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
        {!approvals.isLoading && filtered.length === 0 && (
          <div className="rounded-lg border border-gray-200 dark:border-gray-800 p-6 bg-white dark:bg-gray-900 text-center text-sm text-gray-500">
            Nothing awaiting approval. Scheduled agent runs will populate this list.
          </div>
        )}

        <div className="space-y-2">
          {filtered.map((item) => (
            <ApprovalRow
              key={`${item.category}:${item.pending_id}`}
              item={item}
              busy={busyId === item.pending_id || mutation.isPending}
              onApply={() => mutation.mutate({ verb: 'apply', item })}
              onReject={() => mutation.mutate({ verb: 'reject', item })}
            />
          ))}
        </div>
      </section>

      {/* ===== Re-surfaced contacts ===== */}
      <section>
        <div className="flex items-baseline justify-between mb-3">
          <h2 className="text-lg font-medium">Re-surfaced contacts</h2>
          {resurfacer.data?.found && resurfacer.data.date && (
            <span className="text-xs text-gray-500">{resurfacer.data.date}</span>
          )}
        </div>
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
          {resurfacer.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
          {resurfacer.data && !resurfacer.data.found && (
            <p className="text-sm text-gray-500">{resurfacer.data.message ?? 'No re-surfacer output yet.'}</p>
          )}
          {resurfacer.data?.found && resurfacer.data.raw_markdown && (
            <MarkdownRenderer markdown={resurfacer.data.raw_markdown} />
          )}
        </div>
      </section>

      {/* ===== Today's brief ===== */}
      <section>
        <div className="flex items-baseline justify-between mb-3">
          <h2 className="text-lg font-medium">Today's brief</h2>
          {brief.data?.found && brief.data.generated_at && (
            <span className="text-xs text-gray-500">Generated {new Date(brief.data.generated_at).toLocaleString()}</span>
          )}
        </div>
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
          {brief.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
          {brief.data && !brief.data.found && <p className="text-sm text-gray-500">{brief.data.message}</p>}
          {brief.data?.found && brief.data.raw_markdown && <MarkdownRenderer markdown={brief.data.raw_markdown} />}
        </div>
      </section>
    </div>
  );
}

function FilterChip({ label, active, onClick, count }: { label: string; active: boolean; onClick: () => void; count: number }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`px-2.5 py-1 text-xs rounded border transition-colors ${
        active
          ? 'bg-accent-600 text-white border-accent-600'
          : 'border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800'
      }`}
    >
      {label} <span className={active ? 'opacity-80' : 'text-gray-500'}>{count}</span>
    </button>
  );
}

function ApprovalRow({
  item,
  busy,
  onApply,
  onReject,
}: {
  item: ApprovalItem;
  busy: boolean;
  onApply: () => void;
  onReject: () => void;
}) {
  const [showDetail, setShowDetail] = useState(false);
  const subject = typeof item.payload.subject === 'string' ? item.payload.subject : null;
  const before = typeof item.payload.before === 'string' ? item.payload.before : null;
  const after = typeof item.payload.after === 'string' ? item.payload.after : null;
  const title =
    subject ??
    item.target_object.label ??
    item.target_object.id ??
    item.target_object.id_or_email ??
    item.target_object.type;

  return (
    <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-3 text-sm">
      <div className="flex items-start gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-baseline gap-2 flex-wrap">
            <span className={`text-xs font-medium px-1.5 py-0.5 rounded ${CATEGORY_CHIP[item.category]}`}>
              {CATEGORY_LABELS[item.category]}
            </span>
            <code className="text-xs text-gray-500">#{item.pending_id}</code>
            <span className="text-xs font-medium px-1.5 py-0.5 rounded bg-gray-100 dark:bg-gray-800">{item.action_type}</span>
            <span className="font-medium">{title}</span>
          </div>
          {item.rationale && <p className="mt-1 text-gray-700 dark:text-gray-300">{item.rationale}</p>}
          {item.queue_reason && <p className="mt-1 text-xs text-gray-500">{item.queue_reason}</p>}

          {(before !== null || after !== null) && (
            <div className="mt-2 grid grid-cols-1 md:grid-cols-2 gap-2">
              <div>
                <p className="text-xs font-semibold text-red-700 dark:text-red-400 mb-1">Before</p>
                <pre className="p-2 bg-red-500/5 border border-red-500/20 text-xs overflow-x-auto rounded whitespace-pre-wrap">{before ?? '—'}</pre>
              </div>
              <div>
                <p className="text-xs font-semibold text-green-700 dark:text-green-400 mb-1">After</p>
                <pre className="p-2 bg-green-500/5 border border-green-500/20 text-xs overflow-x-auto rounded whitespace-pre-wrap">{after ?? '—'}</pre>
              </div>
            </div>
          )}

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

          {showDetail && (
            <pre className="mt-2 p-2 bg-gray-50 dark:bg-gray-950 text-xs overflow-x-auto rounded border border-gray-200 dark:border-gray-800">
              {JSON.stringify(item.payload, null, 2)}
            </pre>
          )}
        </div>
        <div className="flex flex-col gap-1 shrink-0">
          <button
            type="button"
            disabled={busy}
            onClick={onApply}
            className="px-2 py-1 text-xs font-medium rounded bg-accent-600 hover:bg-accent-700 text-white disabled:opacity-50"
          >
            {item.category === 'newsletter' ? 'Approve' : 'Apply'}
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={onReject}
            className="px-2 py-1 text-xs font-medium rounded border border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-50"
          >
            Reject
          </button>
          <button
            type="button"
            onClick={() => setShowDetail(!showDetail)}
            className="px-2 py-1 text-xs text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
          >
            {showDetail ? 'Hide' : 'JSON'}
          </button>
        </div>
      </div>
    </article>
  );
}

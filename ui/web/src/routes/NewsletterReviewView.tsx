import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, PendingItem } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';

interface Recipient { name?: string; email?: string; firm?: string; source?: string }

// Investor Newsletter review + approval. Single-item queue: the biweekly
// investor-newsletter compose run writes one pending item (subject + body +
// recipient roster). "Approve & create Gmail draft" invokes the agent's
// decision mode, which creates ONE unsent Gmail draft with all recipients in
// BCC. Nothing is ever sent from here.
export default function NewsletterReviewView() {
  const qc = useQueryClient();
  const queryKey = ['queue', 'newsletter'];
  const pending = useQuery({ queryKey, queryFn: () => api.queue('newsletter') });
  const [actionResult, setActionResult] = useState<{ phrase: string; ok: boolean; stdout: string; stderr: string } | null>(null);

  const SETTLE_MS = 500;

  const approveMutation = useMutation({
    mutationFn: (run_date: string) => api.queueApply('newsletter', run_date),
    onSuccess: async (result) => {
      setActionResult({ phrase: result.phrase, ok: result.ok, stdout: result.stdout, stderr: result.stderr });
      await new Promise((r) => setTimeout(r, SETTLE_MS));
      qc.invalidateQueries({ queryKey });
    },
  });

  const rejectMutation = useMutation({
    mutationFn: (run_date: string) => api.queueReject('newsletter', run_date),
    onSuccess: async (result) => {
      setActionResult({ phrase: result.phrase, ok: result.ok, stdout: result.stdout, stderr: result.stderr });
      await new Promise((r) => setTimeout(r, SETTLE_MS));
      qc.invalidateQueries({ queryKey });
    },
  });

  const items = pending.data?.pending ?? [];
  const isPending = approveMutation.isPending || rejectMutation.isPending;

  return (
    <div className="p-6 max-w-4xl">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold">Investor Newsletter</h1>
        <p className="text-xs text-gray-500 mt-1">
          Approving creates one <strong>unsent</strong> Gmail draft with every recipient in <strong>BCC</strong>. Review it in Gmail and send manually — nothing is sent from here.
        </p>
      </header>

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
          No newsletter awaiting approval. The biweekly investor-newsletter run composes the next update.
        </div>
      )}

      {items.map((item) => (
        <NewsletterCard
          key={item.pending_id}
          item={item}
          isPending={isPending}
          onApprove={() => approveMutation.mutate(item.run_date)}
          onReject={() => rejectMutation.mutate(item.run_date)}
        />
      ))}
    </div>
  );
}

function NewsletterCard({
  item,
  isPending,
  onApprove,
  onReject,
}: {
  item: PendingItem;
  isPending: boolean;
  onApprove: () => void;
  onReject: () => void;
}) {
  const subject = typeof item.payload.subject === 'string' ? item.payload.subject : '(no subject)';
  const body = typeof item.payload.body_markdown === 'string' ? item.payload.body_markdown : '';
  const recipients = Array.isArray(item.payload.recipients) ? (item.payload.recipients as Recipient[]) : [];
  const flags = Array.isArray(item.payload.sensitive_flags) ? (item.payload.sensitive_flags as string[]) : [];

  return (
    <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4 mb-4">
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="min-w-0">
          <code className="text-xs text-gray-500">#{item.pending_id} · {item.run_date}</code>
          <h2 className="text-lg font-semibold mt-1">{subject}</h2>
        </div>
        <div className="flex flex-col gap-1 shrink-0">
          <button
            type="button"
            disabled={isPending}
            onClick={onApprove}
            className="px-3 py-1.5 text-sm font-medium rounded bg-accent-600 hover:bg-accent-700 text-white disabled:opacity-50"
          >
            Approve &amp; create Gmail draft
          </button>
          <button
            type="button"
            disabled={isPending}
            onClick={onReject}
            className="px-3 py-1.5 text-sm font-medium rounded border border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-50"
          >
            Reject
          </button>
        </div>
      </div>

      {flags.length > 0 && (
        <div className="mb-3 p-2 rounded border border-amber-500/30 bg-amber-500/5 text-xs text-amber-800 dark:text-amber-300">
          <p className="font-medium mb-1">⚠ {flags.length} item{flags.length !== 1 ? 's' : ''} flagged for review before sending:</p>
          <ul className="list-disc list-inside space-y-0.5">
            {flags.map((f, i) => <li key={i}>{f}</li>)}
          </ul>
        </div>
      )}

      <details className="mb-3" open>
        <summary className="text-sm font-semibold cursor-pointer mb-2">Newsletter body</summary>
        <div className="mt-2 p-3 rounded border border-gray-200 dark:border-gray-800 bg-gray-50 dark:bg-gray-950">
          <MarkdownRenderer markdown={body} />
        </div>
      </details>

      <details>
        <summary className="text-sm font-semibold cursor-pointer">
          Recipients ({recipients.length}) — all delivered via BCC
        </summary>
        <div className="mt-2 overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="text-left text-gray-500 border-b border-gray-200 dark:border-gray-800">
                <th className="py-1 pr-3">Name</th>
                <th className="py-1 pr-3">Email</th>
                <th className="py-1 pr-3">Firm</th>
                <th className="py-1">Source</th>
              </tr>
            </thead>
            <tbody>
              {recipients.map((r, i) => (
                <tr key={i} className="border-b border-gray-100 dark:border-gray-900">
                  <td className="py-1 pr-3">{r.name ?? '—'}</td>
                  <td className="py-1 pr-3 font-mono">{r.email ?? '—'}</td>
                  <td className="py-1 pr-3">{r.firm ?? '—'}</td>
                  <td className="py-1">{r.source ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </article>
  );
}

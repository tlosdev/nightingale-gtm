import { Router } from 'express';
import { z } from 'zod';
import { loadAllUndecidedPending, summarizePending, type UndecidedPendingItem } from '../lib/pending.js';
import { runClaude } from '../lib/claude.js';

/**
 * Cross-check the requested numeric pending IDs against the live undecided
 * set. Returns the list of unknown IDs (empty if all are valid). For 'all',
 * always returns empty — the agent itself handles the "no items today" case.
 */
function findUnknownIds(
  requestedIds: number[] | 'all',
  runDate: string,
  undecided: UndecidedPendingItem[],
): number[] {
  if (requestedIds === 'all') return [];
  // pending_id format is `{date}-{N-zero-padded}` per hubspot-manager Step 5.
  // The frontend sends the numeric suffix only; reconstruct + match.
  const knownNumericIds = new Set<number>();
  for (const item of undecided) {
    if (item.run_date !== runDate) continue;
    const seq = parseInt(item.pending_id.split('-').pop() ?? '', 10);
    if (!Number.isNaN(seq)) knownNumericIds.add(seq);
  }
  return requestedIds.filter((id) => !knownNumericIds.has(id));
}

export const pendingRouter = Router();

pendingRouter.get('/', (_req, res) => {
  const items = loadAllUndecidedPending();
  const counts = summarizePending(items);
  res.json({ pending: items, counts });
});

// Zod schemas — request body shape enforcement. pending_ids are numeric
// suffixes (the {N} part of pending_id {date}-{N}); the server builds the
// full comma-separated string for the trigger phrase. run_date matches ISO
// only — no other formats accepted.
const ActionRequestSchema = z.object({
  pending_ids: z.union([
    z.array(z.number().int().min(0).max(99999)).min(1).max(100),
    z.literal('all'),
  ]),
  run_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

type ActionRequest = z.infer<typeof ActionRequestSchema>;

function dedupeIds(ids: number[] | 'all'): number[] | 'all' {
  if (ids === 'all') return 'all';
  return Array.from(new Set(ids)).sort((a, b) => a - b);
}

function buildPhrase(verb: 'apply' | 'reject', body: ActionRequest): string {
  const ids = body.pending_ids === 'all'
    ? 'all'
    : (body.pending_ids as number[]).join(',');
  return `${verb} hubspot updates ${ids} from ${body.run_date}`;
}

// Apply timeout is generous — a full hubspot-manager batch with many items
// can take 10+ minutes including per-attendee Apify polling. Reject is fast
// (no Apify involved).
const APPLY_TIMEOUT_MS = 15 * 60 * 1000;
const REJECT_TIMEOUT_MS = 60 * 1000;

pendingRouter.post('/apply', async (req, res) => {
  const parse = ActionRequestSchema.safeParse(req.body);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_request', details: parse.error.flatten() });
    return;
  }
  const data: ActionRequest = { ...parse.data, pending_ids: dedupeIds(parse.data.pending_ids) };
  // Cross-check IDs against the live undecided set. Stale or typo'd IDs are
  // rejected with 409 + a useful list so the operator can investigate.
  const unknownIds = findUnknownIds(data.pending_ids, data.run_date, loadAllUndecidedPending());
  if (unknownIds.length > 0) {
    res.status(409).json({
      error: 'unknown_pending_ids',
      unknown_ids: unknownIds,
      run_date: data.run_date,
      message: 'These pending IDs do not exist in the current undecided queue for that date. They may have been already decided or never existed.',
    });
    return;
  }
  const phrase = buildPhrase('apply', data);
  try {
    const result = await runClaude(phrase, { timeoutMs: APPLY_TIMEOUT_MS });
    res.json({
      phrase,
      ok: result.exitCode === 0,
      exit_code: result.exitCode,
      duration_ms: result.durationMs,
      stdout: result.stdout,
      stderr: result.stderr,
    });
  } catch (err) {
    res.status(500).json({ error: 'claude_invocation_failed', detail: (err as Error).message });
  }
});

pendingRouter.post('/reject', async (req, res) => {
  const parse = ActionRequestSchema.safeParse(req.body);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_request', details: parse.error.flatten() });
    return;
  }
  const data: ActionRequest = { ...parse.data, pending_ids: dedupeIds(parse.data.pending_ids) };
  const unknownIds = findUnknownIds(data.pending_ids, data.run_date, loadAllUndecidedPending());
  if (unknownIds.length > 0) {
    res.status(409).json({
      error: 'unknown_pending_ids',
      unknown_ids: unknownIds,
      run_date: data.run_date,
      message: 'These pending IDs do not exist in the current undecided queue for that date. They may have been already decided or never existed.',
    });
    return;
  }
  const phrase = buildPhrase('reject', data);
  try {
    const result = await runClaude(phrase, { timeoutMs: REJECT_TIMEOUT_MS });
    res.json({
      phrase,
      ok: result.exitCode === 0,
      exit_code: result.exitCode,
      duration_ms: result.durationMs,
      stdout: result.stdout,
      stderr: result.stderr,
    });
  } catch (err) {
    res.status(500).json({ error: 'claude_invocation_failed', detail: (err as Error).message });
  }
});

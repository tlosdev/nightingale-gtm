import { Router } from 'express';
import { z } from 'zod';
import { loadUndecidedForQueue, summarizePending, type UndecidedPendingItem } from '../lib/pending.js';
import { QUEUES, isQueueName, type QueueConfig } from '../lib/queues.js';
import { runClaude } from '../lib/claude.js';
import { canSpawnHostProcess, CONTAINER_ACTION_MESSAGE } from '../lib/runtime.js';

/**
 * Generic approval-queue router. Serves any queue registered in QUEUES:
 *   GET    /api/queues/:queue          → undecided items + counts
 *   POST   /api/queues/:queue/apply    → approve verb (apply | approve)
 *   POST   /api/queues/:queue/reject   → reject verb
 *
 * This is the parameterized generalization of routes/pending.ts (which stays
 * mounted at /api/pending for HubSpot back-compat). All the security
 * properties are preserved: numeric IDs are validated by Zod, cross-checked
 * against the live undecided set, the trigger phrase is CONSTRUCTED
 * server-side, and runClaude() re-validates it against the allowlist before
 * spawning.
 */
export const queuesRouter = Router();

function findUnknownIds(
  requestedIds: number[] | 'all',
  runDate: string,
  undecided: UndecidedPendingItem[],
): number[] {
  if (requestedIds === 'all') return [];
  const knownNumericIds = new Set<number>();
  for (const item of undecided) {
    if (item.run_date !== runDate) continue;
    const seq = parseInt(item.pending_id.split('-').pop() ?? '', 10);
    if (!Number.isNaN(seq)) knownNumericIds.add(seq);
  }
  return requestedIds.filter((id) => !knownNumericIds.has(id));
}

// `pending_ids` are optional for idStyle:'none' queues (single-item
// newsletter). When present they are numeric suffixes; the server builds the
// comma-separated list. run_date is ISO-only.
const ActionRequestSchema = z.object({
  pending_ids: z
    .union([
      z.array(z.number().int().min(0).max(99999)).min(1).max(100),
      z.literal('all'),
    ])
    .optional(),
  run_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

type ActionRequest = z.infer<typeof ActionRequestSchema>;

function dedupeIds(ids: number[] | 'all'): number[] | 'all' {
  if (ids === 'all') return 'all';
  return Array.from(new Set(ids)).sort((a, b) => a - b);
}

function buildPhrase(cfg: QueueConfig, which: 'apply' | 'reject', body: ActionRequest): string {
  const verb = which === 'apply' ? cfg.verbs[0] : cfg.verbs[1];
  if (cfg.idStyle === 'none') {
    return `${verb} ${cfg.noun} from ${body.run_date}`;
  }
  const ids =
    !body.pending_ids || body.pending_ids === 'all'
      ? 'all'
      : (body.pending_ids as number[]).join(',');
  return `${verb} ${cfg.noun} ${ids} from ${body.run_date}`;
}

// Generous apply timeout (an agent decision-mode pass can read/write several
// Desktop files; newsletter approve also creates a Gmail draft). Reject is fast.
const APPLY_TIMEOUT_MS = 10 * 60 * 1000;
const REJECT_TIMEOUT_MS = 60 * 1000;

queuesRouter.get('/:queue', (req, res) => {
  const queue = String(req.params.queue);
  if (!isQueueName(queue)) {
    res.status(404).json({ error: 'unknown_queue', queue });
    return;
  }
  const items = loadUndecidedForQueue(QUEUES[queue].subdir);
  const counts = summarizePending(items);
  res.json({ queue, pending: items, counts });
});

function handleAction(which: 'apply' | 'reject', timeoutMs: number) {
  return async (req: import('express').Request, res: import('express').Response) => {
    if (!canSpawnHostProcess()) {
      res.status(503).json({ error: 'container_mode', message: CONTAINER_ACTION_MESSAGE });
      return;
    }
    const queue = String(req.params.queue);
    if (!isQueueName(queue)) {
      res.status(404).json({ error: 'unknown_queue', queue });
      return;
    }
    const cfg = QUEUES[queue];
    const parse = ActionRequestSchema.safeParse(req.body);
    if (!parse.success) {
      res.status(400).json({ error: 'invalid_request', details: parse.error.flatten() });
      return;
    }
    const data: ActionRequest = {
      ...parse.data,
      pending_ids: parse.data.pending_ids ? dedupeIds(parse.data.pending_ids) : undefined,
    };

    // For id-list queues, cross-check requested IDs against the live undecided
    // set. idStyle:'none' queues skip this (the agent resolves the single item).
    if (cfg.idStyle === 'list' && data.pending_ids) {
      const unknownIds = findUnknownIds(
        data.pending_ids,
        data.run_date,
        loadUndecidedForQueue(cfg.subdir),
      );
      if (unknownIds.length > 0) {
        res.status(409).json({
          error: 'unknown_pending_ids',
          unknown_ids: unknownIds,
          run_date: data.run_date,
          message:
            'These pending IDs do not exist in the current undecided queue for that date. They may have been already decided or never existed.',
        });
        return;
      }
    }

    const phrase = buildPhrase(cfg, which, data);
    try {
      const result = await runClaude(phrase, { timeoutMs });
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
  };
}

queuesRouter.post('/:queue/apply', handleAction('apply', APPLY_TIMEOUT_MS));
queuesRouter.post('/:queue/reject', handleAction('reject', REJECT_TIMEOUT_MS));

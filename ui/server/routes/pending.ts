import { Router } from 'express';
import { z } from 'zod';
import { loadAllUndecidedPending, summarizePending } from '../lib/pending.js';
import { runClaude } from '../lib/claude.js';

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

function buildPhrase(verb: 'apply' | 'reject', body: ActionRequest): string {
  const ids = body.pending_ids === 'all'
    ? 'all'
    : (body.pending_ids as number[]).join(',');
  return `${verb} hubspot updates ${ids} from ${body.run_date}`;
}

pendingRouter.post('/apply', async (req, res) => {
  const parse = ActionRequestSchema.safeParse(req.body);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_request', details: parse.error.flatten() });
    return;
  }
  const phrase = buildPhrase('apply', parse.data);
  try {
    const result = await runClaude(phrase, { timeoutMs: 5 * 60 * 1000 });
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
  const phrase = buildPhrase('reject', parse.data);
  try {
    const result = await runClaude(phrase, { timeoutMs: 60 * 1000 });
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

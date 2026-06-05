import { Router } from 'express';
import { listRuns, getRun } from '../lib/runs.js';

/**
 * Run history + live status for the Logs tab.
 *   GET /api/runs        → recent runs (newest first)
 *   GET /api/runs/:id    → one run's record + a tail of its streamed log
 *
 * Read-only. Runs are started elsewhere (agents.ts Run-now, apply/reject).
 * The client polls /api/runs/:id via React Query while status === 'running'.
 */
export const runsRouter = Router();

runsRouter.get('/', (_req, res) => {
  res.json({ runs: listRuns() });
});

runsRouter.get('/:id', (req, res) => {
  const id = String(req.params.id);
  // Run ids are `${epochMillis}-${8 hex}`. Reject anything else so a stray id
  // can never be used to probe the filesystem via the record/log path builders.
  if (!/^\d{10,}-[0-9a-f]{8}$/.test(id)) {
    res.status(400).json({ error: 'invalid_run_id' });
    return;
  }
  const found = getRun(id);
  if (!found) {
    res.status(404).json({ error: 'unknown_run', id });
    return;
  }
  res.json(found);
});

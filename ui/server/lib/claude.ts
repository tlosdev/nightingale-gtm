// Thin compatibility wrapper around the background-run model in runs.ts.
//
// HISTORY: this module used to own the `claude -p` spawn directly with a hand-
// rolled allowlist env. That allowlist stripped a variable the CLI needs and
// caused `runClaude` to hang forever (the child blocked on closed stdin during
// onboarding/auth and never exited or errored). The hardened spawn — full env
// inherit minus known secrets, resolved exe, Windows tree-kill, guaranteed
// settle — now lives in runs.ts (the single spawn chokepoint).
//
// runClaude() is kept as a synchronous-style awaitable so the apply/reject
// callers in routes/pending.ts and routes/queues.ts are UNCHANGED: they await
// the result exactly as before. They no longer hang because the underlying
// spawn always settles.
import { startRun } from './runs.js';

export interface ClaudeRunResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  durationMs: number;
}

export interface ClaudeRunOptions {
  /** Max wall-clock duration before the subprocess tree is killed. Default: 5 minutes. */
  timeoutMs?: number;
  /** Coarse classification for the run registry (default 'task'). */
  kind?: string;
  /** Human label for the run registry (default: the phrase). */
  label?: string;
}

/**
 * Run `claude -p "<phrase>"` to completion and return its result. The phrase
 * MUST be constructed from validated fields; startRun() re-validates it
 * against the allowlist before spawning (throwing synchronously if rejected).
 *
 * This is a thin wrapper over startRun().done — every invocation is also
 * recorded in the run registry, so apply/reject actions show up in the Logs
 * tab alongside manual agent runs.
 */
export async function runClaude(phrase: string, opts: ClaudeRunOptions = {}): Promise<ClaudeRunResult> {
  const { done } = startRun({
    phrase,
    kind: opts.kind ?? 'task',
    label: opts.label ?? phrase,
    timeoutMs: opts.timeoutMs,
  });
  return done;
}

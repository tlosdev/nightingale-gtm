// Background-run model for `claude -p "<phrase>"` invocations.
//
// This module is the SINGLE place in the codebase that spawns the `claude`
// CLI. It owns the hardened spawn (env, exe resolution, Windows tree-kill,
// always-settle) plus a lightweight run registry so the UI never shows an
// infinite spinner: a manual "Run now" returns a run id immediately and the
// Logs tab polls the run's status + log tail until it settles.
//
// Registry storage:
//  - In-memory Map<id, RunRecord>  (authoritative for the current process)
//  - On disk under SIGNALS_ROOT/_runs/{id}.json  (survives a server restart)
//                  SIGNALS_ROOT/_runs/{id}.log   (streamed stdout+stderr)
//
// The `_runs/` subtree is server-owned infrastructure (underscore-prefixed so
// it is never confused with an agent's Desktop output). This is the one place
// the UI server writes under the signals tree.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { isPhraseAllowed } from '../trigger-allowlist.js';
import { repoRoot, SIGNALS_ROOT } from './paths.js';
import { canSpawnHostProcess, CONTAINER_ACTION_MESSAGE } from './runtime.js';
import type { ClaudeRunResult } from './claude.js';

export type RunStatus = 'running' | 'ok' | 'error' | 'timeout';

export interface RunRecord {
  id: string;
  /** Coarse classification: 'agent' for a Run-now, 'task' for apply/reject etc. */
  kind: string;
  /** Human label (agent name, or the phrase). */
  label: string;
  phrase: string;
  status: RunStatus;
  exit_code: number | null;
  started_at: string;
  duration_ms: number | null;
}

export interface StartRunOptions {
  phrase: string;
  kind?: string;
  label?: string;
  timeoutMs?: number;
}

export interface StartRunHandle {
  id: string;
  record: RunRecord;
  done: Promise<ClaudeRunResult>;
}

const DEFAULT_TIMEOUT_MS = 5 * 60 * 1000;
// Cap how much stdout/stderr we keep in memory for the returned result.
// The full stream still lands in the .log file on disk; this only bounds the
// string handed back to apply/reject callers + the result object.
const MAX_CAPTURE_BYTES = 1_000_000;
// Tail size returned by getRun() for live log viewing.
const LOG_TAIL_BYTES = 32_000;
// How many runs listRuns() returns.
const LIST_LIMIT = 100;

// In-memory registry. Authoritative for runs started in this process.
const runs = new Map<string, RunRecord>();

function runsDir(): string {
  return path.join(SIGNALS_ROOT, '_runs');
}

function ensureRunsDir(): string {
  const dir = runsDir();
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

// ---------------------------------------------------------------------------
// Hardened subprocess environment + exe resolution
// ---------------------------------------------------------------------------

// BLOCKLIST (not allowlist). The previous allowlist stripped a variable the
// Claude CLI needs to skip onboarding/trust-folder/auth, so `claude -p` blocked
// forever on closed stdin. We now inherit the full parent env (matching what
// the working scheduled tasks get) and delete only known third-party secret
// vars that the CLI never needs. We deliberately do NOT fuzzy-match on
// "TOKEN"/"KEY" because that would risk stripping ANTHROPIC_API_KEY / claude
// credentials the CLI may rely on.
const STRIP_ENV_KEYS = new Set(
  [
    'APIFY_API_TOKEN',
    'APIFY_TOKEN',
    'LINKEDIN_LI_AT',
    'LI_AT',
    'GITHUB_TOKEN',
    'GH_TOKEN',
    'HUBSPOT_API_KEY',
    'HUBSPOT_TOKEN',
    'HUBSPOT_PRIVATE_APP_TOKEN',
  ].map((k) => k.toUpperCase()),
);

function envForSubprocess(): NodeJS.ProcessEnv {
  const out: NodeJS.ProcessEnv = { ...process.env };
  for (const key of Object.keys(out)) {
    if (STRIP_ENV_KEYS.has(key.toUpperCase())) delete out[key];
  }
  return out;
}

// Resolve an absolute path to the claude executable once. Under shell:false a
// bare 'claude' can fail to resolve (PATHEXT / .cmd-vs-.exe ambiguity), which
// surfaces as a spawn error rather than a hang — but resolving removes the
// ambiguity entirely and matches how install-schedule.ps1 picks the exe.
// Prefer a real .exe (Node can spawn it with shell:false); fall back to
// whatever `where` returns, then to bare 'claude'.
let resolvedExe: string | null = null;
function resolveClaudeExe(): string {
  if (resolvedExe) return resolvedExe;
  try {
    const r = spawnSync('where', ['claude'], { encoding: 'utf8', windowsHide: true });
    if (r.status === 0 && r.stdout) {
      const lines = r.stdout
        .split(/\r?\n/)
        .map((l) => l.trim())
        .filter(Boolean);
      const exe = lines.find((l) => l.toLowerCase().endsWith('.exe'));
      resolvedExe = exe ?? lines[0] ?? 'claude';
      return resolvedExe;
    }
  } catch {
    // fall through to bare name
  }
  resolvedExe = 'claude';
  return resolvedExe;
}

// ---------------------------------------------------------------------------
// Persistence helpers
// ---------------------------------------------------------------------------

function recordPath(id: string): string {
  return path.join(runsDir(), `${id}.json`);
}
function logPath(id: string): string {
  return path.join(runsDir(), `${id}.log`);
}

function persistRecord(rec: RunRecord): void {
  try {
    ensureRunsDir();
    fs.writeFileSync(recordPath(rec.id), JSON.stringify(rec, null, 2), 'utf8');
  } catch {
    // Persistence is best-effort; the in-memory record is authoritative for
    // this process. A failure here must never break the run itself.
  }
}

// ---------------------------------------------------------------------------
// Windows process-tree kill
// ---------------------------------------------------------------------------

// child.kill() only signals the direct child on Windows; the `claude` launcher
// can spawn a node subprocess that survives. taskkill /T /F kills the whole
// tree so the 'exit' handler actually fires and the run settles.
function treeKill(pid: number | undefined): void {
  if (pid === undefined) return;
  try {
    spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true });
  } catch {
    // best-effort
  }
}

// ---------------------------------------------------------------------------
// startRun — the one hardened spawn
// ---------------------------------------------------------------------------

export function startRun(opts: StartRunOptions): StartRunHandle {
  const { phrase } = opts;
  // Fail-closed backstop: never spawn the host CLI from a container. Routes
  // check this first and return a clean 503, but this guarantees the single
  // spawn chokepoint can't be bypassed.
  if (!canSpawnHostProcess()) {
    throw new Error(`container_mode: ${CONTAINER_ACTION_MESSAGE}`);
  }
  // Defense-in-depth: re-validate the phrase against the allowlist at the spawn
  // boundary. Throws synchronously so the HTTP layer can return 400.
  if (!isPhraseAllowed(phrase)) {
    throw new Error(`Trigger phrase rejected by allowlist: ${JSON.stringify(phrase)}`);
  }

  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const id = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;
  const startedAtMs = Date.now();
  const record: RunRecord = {
    id,
    kind: opts.kind ?? 'task',
    label: opts.label ?? phrase,
    phrase,
    status: 'running',
    exit_code: null,
    started_at: new Date(startedAtMs).toISOString(),
    duration_ms: null,
  };
  runs.set(id, record);

  const exe = resolveClaudeExe();
  ensureRunsDir();
  persistRecord(record);

  // Open the log file for streaming. Failure to open is non-fatal — we still
  // capture in memory.
  let logStream: fs.WriteStream | null = null;
  try {
    logStream = fs.createWriteStream(logPath(id), { flags: 'a' });
    logStream.write(
      `[run ${id}] kind=${record.kind} label=${record.label}\n` +
        `[run ${id}] exe=${exe}\n` +
        `[run ${id}] phrase=${phrase}\n` +
        `[run ${id}] started_at=${record.started_at} timeout_ms=${timeoutMs}\n` +
        `[run ${id}] env_keys=${Object.keys(envForSubprocess()).length}\n` +
        `----\n`,
    );
  } catch {
    logStream = null;
  }

  const done = new Promise<ClaudeRunResult>((resolve) => {
    let stdout = '';
    let stderr = '';
    let settled = false;
    let killedForTimeout = false;

    const append = (target: 'out' | 'err', chunk: Buffer) => {
      const s = chunk.toString('utf8');
      logStream?.write(s);
      if (target === 'out') {
        if (stdout.length < MAX_CAPTURE_BYTES) stdout += s;
      } else {
        if (stderr.length < MAX_CAPTURE_BYTES) stderr += s;
      }
    };

    // shell:false — phrase is a single argv element, never re-parsed by a
    // shell. The allowlist already rejects shell metacharacters.
    const child = spawn(exe, ['-p', phrase], {
      cwd: repoRoot(),
      shell: false,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: envForSubprocess(),
    });

    logStream?.write(`[run ${id}] pid=${child.pid ?? 'unknown'}\n`);

    const settle = (status: RunStatus, exitCode: number, settledVia: string) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const durationMs = Date.now() - startedAtMs;
      record.status = status;
      record.exit_code = exitCode;
      record.duration_ms = durationMs;
      persistRecord(record);
      logStream?.write(`\n----\n[run ${id}] settled via ${settledVia}: status=${status} exit=${exitCode} duration_ms=${durationMs}\n`);
      logStream?.end();
      resolve({
        exitCode,
        stdout,
        stderr:
          status === 'timeout'
            ? stderr + '\n[killed: timeout exceeded]'
            : stderr,
        durationMs,
      });
    };

    // Always-settle backstop: if neither exit nor error fires within the
    // timeout, kill the tree and settle anyway so the request never hangs.
    const timer = setTimeout(() => {
      killedForTimeout = true;
      treeKill(child.pid);
      // Give the tree a moment to die + fire 'exit'; settle regardless.
      setTimeout(() => settle('timeout', -1, 'timeout'), 3000);
    }, timeoutMs);

    child.stdout?.on('data', (b: Buffer) => append('out', b));
    child.stderr?.on('data', (b: Buffer) => append('err', b));

    child.on('error', (err) => {
      append('err', Buffer.from(`\n[spawn error] ${err.message}\n`));
      settle('error', -1, 'error');
    });

    child.on('exit', (code) => {
      if (killedForTimeout) {
        settle('timeout', -1, 'exit-after-timeout');
        return;
      }
      const exitCode = code ?? -1;
      settle(exitCode === 0 ? 'ok' : 'error', exitCode, 'exit');
    });
  });

  return { id, record, done };
}

// ---------------------------------------------------------------------------
// Registry queries
// ---------------------------------------------------------------------------

/** Recent runs, newest first. Merges in-memory + on-disk records. */
export function listRuns(limit = LIST_LIMIT): RunRecord[] {
  const byId = new Map<string, RunRecord>();

  // On-disk first (older / from prior process lifetimes)...
  try {
    const dir = runsDir();
    if (fs.existsSync(dir)) {
      for (const name of fs.readdirSync(dir)) {
        if (!name.endsWith('.json')) continue;
        try {
          const rec = JSON.parse(fs.readFileSync(path.join(dir, name), 'utf8')) as RunRecord;
          if (rec && typeof rec.id === 'string') byId.set(rec.id, rec);
        } catch {
          // skip malformed
        }
      }
    }
  } catch {
    // ignore
  }

  // ...then in-memory wins (authoritative for live status).
  for (const [id, rec] of runs) byId.set(id, rec);

  return Array.from(byId.values())
    .sort((a, b) => b.started_at.localeCompare(a.started_at))
    .slice(0, limit);
}

/** A single run's record + a tail of its log, or null if unknown. */
export function getRun(id: string): { run: RunRecord; log_tail: string } | null {
  let rec = runs.get(id) ?? null;
  if (!rec) {
    try {
      const p = recordPath(id);
      if (fs.existsSync(p)) rec = JSON.parse(fs.readFileSync(p, 'utf8')) as RunRecord;
    } catch {
      rec = null;
    }
  }
  if (!rec) return null;

  let log_tail = '';
  try {
    const lp = logPath(id);
    if (fs.existsSync(lp)) {
      const stat = fs.statSync(lp);
      const start = Math.max(0, stat.size - LOG_TAIL_BYTES);
      const fd = fs.openSync(lp, 'r');
      try {
        const len = stat.size - start;
        const buf = Buffer.alloc(len);
        fs.readSync(fd, buf, 0, len, start);
        log_tail = buf.toString('utf8');
        if (start > 0) log_tail = `…(truncated)\n${log_tail}`;
      } finally {
        fs.closeSync(fd);
      }
    }
  } catch {
    // ignore — return whatever we have
  }
  return { run: rec, log_tail };
}

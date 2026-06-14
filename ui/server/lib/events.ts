// Server-Sent Events broadcaster + filesystem watcher.
//
// This is the event-driven replacement for time-based dashboard polling. Every
// way an agent can run (the GitHub self-hosted runner firing `claude -p`, a
// manual `claude -p "..."` from a terminal, or the UI "Run now" button) ends in
// the SAME observable side effect: new/changed files under SIGNALS_ROOT. So we
// watch that tree once and push a "change" event to every connected browser,
// which then invalidates only the affected React Query keys.
//
// One `fs.watch(..., { recursive: true })` covers the whole subtree (recursive
// watch is supported natively on Windows, the only supported platform). Events
// are debounced (~300ms) and coarsely classified into channels so the client
// can invalidate the right queries without us tracking every file shape.
//
// Caveat: in Docker/container mode the signals tree is a read-only Windows->
// container bind mount, across which inotify-style events do NOT propagate. The
// client falls back to a slow poll there (see web/src/lib/useLiveRefresh.ts);
// this watcher simply never fires in that mode, which is harmless.
import fs from 'node:fs';
import type { Response } from 'express';
import { SIGNALS_ROOT } from './paths.js';

interface Client {
  id: string;
  res: Response;
}

const clients = new Set<Client>();

/** Write one SSE frame to every connected client. Drops nothing on write
 *  failure — a dead socket is reaped by its own 'close' handler. */
function broadcast(event: string, data: unknown): void {
  const frame = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const c of clients) {
    try {
      c.res.write(frame);
    } catch {
      // best-effort; the 'close' handler removes it
    }
  }
}

export function addClient(client: Client): void {
  clients.add(client);
  ensureWatcher();
  startHeartbeat();
}

export function removeClient(client: Client): void {
  clients.delete(client);
}

// ---------------------------------------------------------------------------
// Filesystem watcher
// ---------------------------------------------------------------------------

let watcher: fs.FSWatcher | null = null;
let retryTimer: NodeJS.Timeout | null = null;
let debounceTimer: NodeJS.Timeout | null = null;
const pendingChannels = new Set<string>();

const RETRY_MS = 10_000;
const DEBOUNCE_MS = 300;

/**
 * Map a changed path (relative to SIGNALS_ROOT) to a refresh channel:
 *   - '_runs/**'  -> 'runs'  (the Logs tab's background-run registry)
 *   - everything else -> 'data' (outputs / pending / queues / state)
 */
function classify(relPath: string): 'runs' | 'data' {
  const norm = relPath.replace(/\\/g, '/');
  return norm === '_runs' || norm.startsWith('_runs/') ? 'runs' : 'data';
}

function flush(): void {
  debounceTimer = null;
  if (pendingChannels.size === 0) return;
  const channels = Array.from(pendingChannels);
  pendingChannels.clear();
  broadcast('change', { channels });
}

function scheduleRetry(): void {
  if (retryTimer) return;
  retryTimer = setTimeout(() => {
    retryTimer = null;
    ensureWatcher();
  }, RETRY_MS);
  retryTimer.unref?.();
}

/**
 * Start watching SIGNALS_ROOT if we aren't already. The tree may not exist yet
 * on a fresh install (no agent has run), so if it's missing we retry on a slow
 * timer until it appears. This bootstrap timer is NOT data polling — it only
 * establishes the watch; once attached, all refreshes are event-driven.
 */
export function ensureWatcher(): void {
  if (watcher) return;
  if (!fs.existsSync(SIGNALS_ROOT)) {
    scheduleRetry();
    return;
  }
  try {
    watcher = fs.watch(SIGNALS_ROOT, { recursive: true }, (_eventType, filename) => {
      pendingChannels.add(filename ? classify(filename.toString()) : 'data');
      if (!debounceTimer) {
        debounceTimer = setTimeout(flush, DEBOUNCE_MS);
        debounceTimer.unref?.();
      }
    });
    watcher.on('error', () => {
      try {
        watcher?.close();
      } catch {
        // ignore
      }
      watcher = null;
      scheduleRetry();
    });
  } catch {
    watcher = null;
    scheduleRetry();
  }
}

// ---------------------------------------------------------------------------
// Heartbeat — keepalive comment frames so idle SSE connections aren't reaped.
// These are SSE comments (": ping"), not data; they trigger no client refresh.
// ---------------------------------------------------------------------------

let heartbeat: NodeJS.Timeout | null = null;
const HEARTBEAT_MS = 25_000;

export function startHeartbeat(): void {
  if (heartbeat) return;
  heartbeat = setInterval(() => {
    for (const c of clients) {
      try {
        c.res.write(': ping\n\n');
      } catch {
        // best-effort
      }
    }
  }, HEARTBEAT_MS);
  heartbeat.unref?.();
}

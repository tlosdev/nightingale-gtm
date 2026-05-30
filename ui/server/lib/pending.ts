// Load + merge all hubspot-manager pending/*.json files across all dates.
// Excludes the archive/ subdir. Cross-references against
// approval-history.jsonl to filter out already-decided items.
import fs from 'node:fs';
import path from 'node:path';
import { PATHS } from './paths.js';

export interface QueuedItem {
  pending_id: string;
  action_type: string;
  target_object: {
    type: string;
    id?: string;
    id_or_email?: string;
    label?: string;
    [key: string]: unknown;
  };
  payload: Record<string, unknown>;
  rationale: string;
  queue_reason: string;
  source_quotes: string[];
  source_file_or_thread: string;
}

export interface PendingFile {
  schema_version: number;
  generated_at: string;
  run_date: string;
  auto_applied_count: number;
  auto_cap_hit: boolean;
  queued_items: QueuedItem[];
}

export interface UndecidedPendingItem extends QueuedItem {
  run_date: string;
  source_file: string;
}

/**
 * Build the set of pending_ids that have been decided (approved or rejected)
 * by reading approval-history.jsonl. Returns an empty set if the file
 * doesn't exist.
 */
function loadDecidedIds(): Set<string> {
  const decided = new Set<string>();
  const historyPath = path.join(PATHS.hubspotManager, 'state', 'approval-history.jsonl');
  if (!fs.existsSync(historyPath)) return decided;
  const content = fs.readFileSync(historyPath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const row = JSON.parse(line) as { pending_id?: string };
      if (row.pending_id) decided.add(row.pending_id);
    } catch {
      // Tolerate malformed lines — append-only files can race with reads.
    }
  }
  return decided;
}

// Single-entry mtime-keyed cache. The Layout component re-fetches pending on
// every nav, which would otherwise re-read every pending file + the entire
// approval-history.jsonl per request. Cache key = sum of (pending-dir mtime +
// history-file mtime). Invalidated automatically when either changes.
let cache: { key: string; value: UndecidedPendingItem[] } | null = null;

function buildCacheKey(pendingDir: string, historyPath: string): string {
  let pendingMtime = 0;
  let historyMtime = 0;
  try { pendingMtime = fs.statSync(pendingDir).mtimeMs; } catch { /* missing dir → 0 */ }
  try { historyMtime = fs.statSync(historyPath).mtimeMs; } catch { /* missing → 0 */ }
  return `${pendingMtime}|${historyMtime}`;
}

/**
 * Read every non-archived pending/*.json, filter out decided items, and
 * return the flat list. Sorted by run_date desc, then pending_id asc.
 */
export function loadAllUndecidedPending(): UndecidedPendingItem[] {
  const pendingDir = path.join(PATHS.hubspotManager, 'pending');
  const historyPath = path.join(PATHS.hubspotManager, 'state', 'approval-history.jsonl');
  const key = buildCacheKey(pendingDir, historyPath);
  if (cache && cache.key === key) return cache.value;
  if (!fs.existsSync(pendingDir)) {
    cache = { key, value: [] };
    return cache.value;
  }

  const decided = loadDecidedIds();
  const undecided: UndecidedPendingItem[] = [];

  for (const name of fs.readdirSync(pendingDir)) {
    // Only YYYY-MM-DD.json files at top level; skip archive/ subdir + others.
    if (!/^\d{4}-\d{2}-\d{2}\.json$/.test(name)) continue;
    const full = path.join(pendingDir, name);
    let parsed: PendingFile;
    try {
      parsed = JSON.parse(fs.readFileSync(full, 'utf8'));
    } catch {
      continue;
    }
    const items = Array.isArray(parsed.queued_items) ? parsed.queued_items : [];
    for (const item of items) {
      if (decided.has(item.pending_id)) continue;
      undecided.push({
        ...item,
        run_date: parsed.run_date,
        source_file: full,
      });
    }
  }

  undecided.sort((a, b) => {
    if (a.run_date !== b.run_date) return b.run_date.localeCompare(a.run_date);
    return a.pending_id.localeCompare(b.pending_id);
  });

  cache = { key, value: undecided };
  return undecided;
}

/**
 * Count breakdowns for the dashboard summary.
 */
export function summarizePending(items: UndecidedPendingItem[]): {
  total: number;
  by_day: Record<string, number>;
  by_action_type: Record<string, number>;
} {
  const byDay: Record<string, number> = {};
  const byType: Record<string, number> = {};
  for (const item of items) {
    byDay[item.run_date] = (byDay[item.run_date] ?? 0) + 1;
    byType[item.action_type] = (byType[item.action_type] ?? 0) + 1;
  }
  return { total: items.length, by_day: byDay, by_action_type: byType };
}

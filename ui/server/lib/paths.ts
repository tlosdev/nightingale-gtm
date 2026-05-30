// Filesystem path helpers. All read access from the UI is scoped to the
// signals subtree on the operator's Desktop.
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const HOME = os.homedir();
export const SIGNALS_ROOT = path.join(HOME, 'Desktop', 'nightingale-signals');
export const NIGHTINGALE_DIR = path.join(HOME, '.nightingale');
export const SECRETS_PATH = path.join(NIGHTINGALE_DIR, 'secrets.json');

// Per-agent subtrees on Desktop.
export const PATHS = {
  signalsRoot: SIGNALS_ROOT,
  commercial: path.join(SIGNALS_ROOT, 'commercial'),
  academic: path.join(SIGNALS_ROOT, 'academic'),
  dailyBrief: path.join(SIGNALS_ROOT, 'daily-brief'),
  resurfacer: path.join(SIGNALS_ROOT, 'resurfacer'),
  feedbackInsights: path.join(SIGNALS_ROOT, 'feedback-insights'),
  hubspotManager: path.join(SIGNALS_ROOT, 'hubspot-manager'),
} as const;

/**
 * Resolve the repo root from this file's location: server/lib → server → ui → repo root.
 *
 * Uses `fileURLToPath` rather than `new URL(...).pathname` because the latter
 * returns a percent-encoded path that breaks for any user whose home contains
 * a space (`C:\Users\Jane Doe\...`) or other special character. `fileURLToPath`
 * does the right thing cross-platform and decodes percent-encoding correctly.
 */
export function repoRoot(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  // server/lib → server → ui → repo root
  return path.resolve(here, '..', '..', '..');
}

/**
 * Get the latest file matching a regex within a directory (by mtime desc).
 * Returns null if none found or the directory doesn't exist.
 */
export function latestFileMatching(dir: string, pattern: RegExp): { path: string; mtime: number } | null {
  if (!fs.existsSync(dir)) return null;
  let best: { path: string; mtime: number } | null = null;
  for (const name of fs.readdirSync(dir)) {
    if (!pattern.test(name)) continue;
    const full = path.join(dir, name);
    let stat: fs.Stats;
    try {
      stat = fs.statSync(full);
    } catch {
      continue;
    }
    if (!stat.isFile()) continue;
    if (!best || stat.mtimeMs > best.mtime) {
      best = { path: full, mtime: stat.mtimeMs };
    }
  }
  return best;
}

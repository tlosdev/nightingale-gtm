// Filesystem path helpers. All read access from the UI is scoped to the
// signals subtree on the operator's Desktop; the helpers in this module are
// the single source of truth for those paths so the security audit only has
// one place to look.
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';

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
 * Resolve a path within the signals tree and verify it does not escape the
 * subtree. Returns the canonical absolute path on success, or null if the
 * requested path tries to traverse out of SIGNALS_ROOT.
 *
 * This is the single chokepoint for any UI-driven filesystem read. Every
 * route that reads files must pass its candidate path through this function.
 */
export function safeResolveInSignals(...segments: string[]): string | null {
  const candidate = path.resolve(SIGNALS_ROOT, ...segments);
  const root = path.resolve(SIGNALS_ROOT);
  // Use relative path test: a relative result starting with '..' means escape.
  const rel = path.relative(root, candidate);
  if (rel.startsWith('..') || path.isAbsolute(rel)) {
    return null;
  }
  return candidate;
}

/** Resolve the repo root from the server file's location. server/lib/paths.ts → ../.. */
export function repoRoot(): string {
  // import.meta.url unavailable in CJS mode; this file is ESM via package.json type=module.
  const here = path.dirname(new URL(import.meta.url).pathname);
  // On Windows, the URL path starts with `/C:/...`; strip the leading slash.
  const fixed = process.platform === 'win32' && here.startsWith('/') ? here.slice(1) : here;
  // server/lib → server → ui → repo root
  return path.resolve(fixed, '..', '..', '..');
}

/**
 * Get the latest file matching a glob pattern within a directory (by mtime
 * desc, with filename-date as the tiebreaker for files written on the same
 * second). Returns null if none found or the directory doesn't exist.
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

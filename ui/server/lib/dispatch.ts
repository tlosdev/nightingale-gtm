// GitHub workflow_dispatch — the Phase 3 trigger path that works from inside a
// Docker container (where we cannot spawn the host `claude` CLI). The host-mode
// Run-now still spawns claude directly (see routes/agents.ts); this is used ONLY
// when the UI runs in container mode.
//
// SECURITY:
// - The GitHub PAT is read from secrets.json (BOM-tolerant) ONLY at dispatch
//   time, used to set the Authorization header, and never returned to the
//   browser or logged. The Settings endpoints remain presence-only.
// - The workflow filename is resolved from a fixed AGENT_TO_WORKFLOW map keyed
//   by the validated AgentName enum — no user-supplied path reaches the URL.
import fs from 'node:fs';
import { SECRETS_PATH } from './paths.js';
import type { AgentName } from '../trigger-allowlist.js';

// Agent → workflow file in .github/workflows/. Every agent the dashboard can
// "Run now" must have a dispatchable workflow (scheduled or workflow_dispatch-
// only) or container-mode Run-now would 404 on dispatch.
export const AGENT_TO_WORKFLOW: Record<AgentName, string> = {
  'daily-brief': 'daily-brief.yml',
  'signal-watcher-commercial': 'signal-watcher-commercial.yml',
  'signal-watcher-academic': 'signal-watcher-academic.yml',
  'intro-finder': 'intro-finder.yml',
  'gmail-resurfacer': 'gmail-resurfacer.yml',
  'hubspot-manager': 'hubspot-manager.yml',
  'feedback-analyzer': 'feedback-analyzer.yml',
  'investor-analyzer': 'investor-analyzer.yml',
  'pitch-deck-updater': 'pitch-deck-updater.yml',
  'investor-newsletter': 'investor-newsletter.yml',
};

// owner/repo shape, e.g. ben-nightingale/Nightingale.
const REPO_RE = /^[\w.-]+\/[\w.-]+$/;

interface GithubSecrets {
  pat: string | null;
  repo: string | null;
}

/**
 * Read github_pat + github_repo from secrets.json. Server-side only — these
 * values never leave the process except as an Authorization header to GitHub.
 */
function readGithubSecrets(): GithubSecrets {
  try {
    if (!fs.existsSync(SECRETS_PATH)) return { pat: null, repo: null };
    const rawText = fs.readFileSync(SECRETS_PATH, 'utf8');
    const text = rawText.charCodeAt(0) === 0xfeff ? rawText.slice(1) : rawText;
    const parsed = JSON.parse(text) as Record<string, unknown>;
    const pat = typeof parsed.github_pat === 'string' && parsed.github_pat.length > 0 ? parsed.github_pat : null;
    const repo = typeof parsed.github_repo === 'string' && parsed.github_repo.length > 0 ? parsed.github_repo : null;
    return { pat, repo };
  } catch {
    return { pat: null, repo: null };
  }
}

/** Whether a PAT + valid repo are both present (so dispatch can be attempted). */
export function dispatchConfigured(): boolean {
  const { pat, repo } = readGithubSecrets();
  return Boolean(pat && repo && REPO_RE.test(repo));
}

export interface DispatchResult {
  ok: boolean;
  workflow: string;
  repo?: string;
  status?: number;
  error?: string;
}

/**
 * Fire a workflow_dispatch for one agent against the configured repo on `main`.
 * Returns a structured result; never throws for the caller to handle uniformly.
 */
export async function dispatchWorkflow(agent: AgentName): Promise<DispatchResult> {
  const workflow = AGENT_TO_WORKFLOW[agent];
  if (!workflow) return { ok: false, workflow: String(agent), error: 'no_workflow_for_agent' };

  const { pat, repo } = readGithubSecrets();
  if (!pat || !repo) return { ok: false, workflow, error: 'github_not_configured' };
  if (!REPO_RE.test(repo)) return { ok: false, workflow, error: 'github_repo_invalid' };

  const url = `https://api.github.com/repos/${repo}/actions/workflows/${workflow}/dispatches`;
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${pat}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'nightingale-ui',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ ref: 'main' }),
    });
    // 204 No Content on success. Any non-2xx → surface the status (NOT the body,
    // which could echo back request detail; the status is enough to diagnose:
    // 401 bad PAT, 403 missing Actions scope, 404 wrong repo/workflow).
    if (res.status === 204) return { ok: true, workflow, repo, status: 204 };
    return { ok: false, workflow, repo, status: res.status, error: `github_status_${res.status}` };
  } catch (err) {
    return { ok: false, workflow, repo, error: `fetch_failed: ${(err as Error).message}` };
  }
}

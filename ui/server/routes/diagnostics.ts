import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { PATHS, SECRETS_PATH } from '../lib/paths.js';
import { getNightingaleScheduledTasks } from '../lib/powershell.js';

export const diagnosticsRouter = Router();

const NOTICE_FILES: Array<{ connector: string; dir: string; pattern: RegExp }> = [
  { connector: 'Gmail', dir: path.join(PATHS.resurfacer, 'output'), pattern: /^GMAIL_NOT_AUTHORIZED-\d{4}-\d{2}-\d{2}\.md$/ },
  { connector: 'Google Calendar', dir: path.join(PATHS.dailyBrief, 'output'), pattern: /^CALENDAR_NOT_AUTHORIZED-\d{4}-\d{2}-\d{2}\.md$/ },
  { connector: 'HubSpot', dir: path.join(PATHS.hubspotManager, 'output'), pattern: /^HUBSPOT_NOT_AUTHORIZED-\d{4}-\d{2}-\d{2}\.md$/ },
  { connector: 'Drive + Gmail (feedback-analyzer)', dir: path.join(PATHS.feedbackInsights, 'output'), pattern: /^MCPS_NOT_AUTHORIZED-\d{4}-\d{2}-\d{2}\.md$/ },
  // The hardening pass added these two notice shapes to hubspot-manager +
  // feedback-analyzer. Without these patterns the diagnostics view would
  // show ✓ while the agents are silently broken.
  { connector: 'Operator identity (hubspot-manager)', dir: path.join(PATHS.hubspotManager, 'output'), pattern: /^OPERATOR_DOMAIN_UNRESOLVED-\d{4}-\d{2}-\d{2}\.md$/ },
  { connector: 'Operator identity (feedback-analyzer)', dir: path.join(PATHS.feedbackInsights, 'output'), pattern: /^OPERATOR_DOMAIN_UNRESOLVED-\d{4}-\d{2}-\d{2}\.md$/ },
  { connector: 'Persona files (hubspot-manager)', dir: path.join(PATHS.hubspotManager, 'output'), pattern: /^PERSONA_FILES_MISSING-\d{4}-\d{2}-\d{2}\.md$/ },
  { connector: 'Persona files (feedback-analyzer)', dir: path.join(PATHS.feedbackInsights, 'output'), pattern: /^PERSONA_FILES_MISSING-\d{4}-\d{2}-\d{2}\.md$/ },
];

function mostRecentNotice(dir: string, pattern: RegExp): { path: string; mtime: number } | null {
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
    if (!best || stat.mtimeMs > best.mtime) {
      best = { path: full, mtime: stat.mtimeMs };
    }
  }
  return best;
}

// Best-effort MCP authorization detection: an unauthorized connector is one
// that has emitted a NOT_AUTHORIZED notice in the last 7 days. Older notices
// are stale (operator may have fixed it since). Genuinely-authorized = no
// recent notice.
diagnosticsRouter.get('/mcp', (_req, res) => {
  const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const mcp_status = NOTICE_FILES.map(({ connector, dir, pattern }) => {
    const notice = mostRecentNotice(dir, pattern);
    const recentNotice = notice && notice.mtime > sevenDaysAgo;
    return {
      connector,
      authorized: !recentNotice,
      last_notice_path: recentNotice ? notice.path : null,
      last_notice_at: recentNotice ? new Date(notice.mtime).toISOString() : null,
    };
  });
  res.json({ mcp_status });
});

diagnosticsRouter.get('/tasks', async (_req, res) => {
  const tasks = await getNightingaleScheduledTasks();
  if (!tasks) {
    res.status(503).json({
      error: 'powershell_unavailable',
      message: 'Could not invoke Get-ScheduledTask. Are you on Windows with Task Scheduler service running?',
    });
    return;
  }
  res.json({ tasks });
});

// IMPORTANT: this endpoint returns PRESENCE-OF-FIELDS only — never the
// actual secret values. The response shape is enforced by tsc; reviewers
// should confirm this when auditing the security boundary.
interface SecretsHealth {
  exists: boolean;
  schema_version: number | null;
  has_apify_api_token: boolean;
  has_apify_actor_id: boolean;
  has_apify_validation_url: boolean;
  has_linkedin_li_at: boolean;
  has_apify_company_roster_actor_id: boolean;
  updated_at: string | null;
}

diagnosticsRouter.get('/secrets', (_req, res) => {
  if (!fs.existsSync(SECRETS_PATH)) {
    const out: SecretsHealth = {
      exists: false,
      schema_version: null,
      has_apify_api_token: false,
      has_apify_actor_id: false,
      has_apify_validation_url: false,
      has_linkedin_li_at: false,
      has_apify_company_roster_actor_id: false,
      updated_at: null,
    };
    res.json(out);
    return;
  }
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(fs.readFileSync(SECRETS_PATH, 'utf8'));
  } catch {
    // Could not parse — treat as exists but malformed.
    const out: SecretsHealth = {
      exists: true,
      schema_version: null,
      has_apify_api_token: false,
      has_apify_actor_id: false,
      has_apify_validation_url: false,
      has_linkedin_li_at: false,
      has_apify_company_roster_actor_id: false,
      updated_at: null,
    };
    res.json(out);
    return;
  }
  const has = (k: string) => typeof parsed[k] === 'string' && (parsed[k] as string).length > 0;
  const out: SecretsHealth = {
    exists: true,
    schema_version: typeof parsed.schema_version === 'number' ? parsed.schema_version : null,
    has_apify_api_token: has('apify_api_token'),
    has_apify_actor_id: has('apify_actor_id'),
    has_apify_validation_url: has('apify_validation_url'),
    has_linkedin_li_at: has('linkedin_li_at'),
    has_apify_company_roster_actor_id: has('apify_company_roster_actor_id'),
    updated_at: typeof parsed.updated_at === 'string' ? (parsed.updated_at as string) : null,
  };
  res.json(out);
});

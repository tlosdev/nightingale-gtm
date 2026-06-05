import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { PATHS } from '../lib/paths.js';
import { getNightingaleScheduledTasks } from '../lib/powershell.js';
import { readSecretsHealth } from '../lib/secrets-health.js';

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

export interface ConnectorStatus {
  connector: string;
  authorized: boolean;
  last_notice_path: string | null;
  last_notice_at: string | null;
}

// Best-effort MCP authorization detection: an unauthorized connector is one
// that has emitted a NOT_AUTHORIZED notice in the last 7 days. Older notices
// are stale (operator may have fixed it since). Genuinely-authorized = no
// recent notice. Exported so the Settings "Connections" panel reuses the exact
// same heuristic as the diagnostics endpoint.
export function computeMcpStatus(): ConnectorStatus[] {
  const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
  return NOTICE_FILES.map(({ connector, dir, pattern }) => {
    const notice = mostRecentNotice(dir, pattern);
    const recentNotice = notice && notice.mtime > sevenDaysAgo;
    return {
      connector,
      authorized: !recentNotice,
      last_notice_path: recentNotice ? notice.path : null,
      last_notice_at: recentNotice ? new Date(notice.mtime).toISOString() : null,
    };
  });
}

diagnosticsRouter.get('/mcp', (_req, res) => {
  res.json({ mcp_status: computeMcpStatus() });
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

// IMPORTANT: this endpoint returns PRESENCE-OF-FIELDS only — never the actual
// secret values. The logic lives in lib/secrets-health.ts so the Settings GET
// shares exactly one implementation of this security boundary.
diagnosticsRouter.get('/secrets', (_req, res) => {
  res.json(readSecretsHealth());
});

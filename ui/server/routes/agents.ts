import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { z } from 'zod';
import { PATHS, latestFileMatching } from '../lib/paths.js';
import { AGENT_TRIGGERS, type AgentName } from '../trigger-allowlist.js';
import { runClaude } from '../lib/claude.js';
import { getNightingaleScheduledTasks } from '../lib/powershell.js';

export const agentsRouter = Router();

interface AgentSummary {
  name: AgentName;
  trigger_phrase: string;
  scheduled_task_name: string | null;
  scheduled_task_state: string | null;
  last_run_time: string | null;
  next_run_time: string | null;
  last_output_path: string | null;
  last_output_generated_at: string | null;
}

const AGENT_TO_TASK: Record<AgentName, string | null> = {
  'daily-brief': 'Nightingale-Daily-Brief-Morning',
  'signal-watcher-commercial': 'Nightingale-Commercial-Sweep',
  'signal-watcher-academic': 'Nightingale-Academic-Sweep',
  'intro-finder': 'Nightingale-Intro-Finder-Morning',
  'gmail-resurfacer': 'Nightingale-Gmail-Resurfacer-Morning',
  'hubspot-manager': 'Nightingale-HubSpot-Manager-Nightly',
  'feedback-analyzer': null, // on-demand, no scheduled task
  'investor-analyzer': 'Nightingale-Investor-Analyzer-Weekly',
  'pitch-deck-updater': null, // chained off investor-analyzer, no scheduled task
  'investor-newsletter': 'Nightingale-Investor-Newsletter-Biweekly',
};

function latestOutputFor(agent: AgentName): { path: string; mtime: number } | null {
  switch (agent) {
    case 'daily-brief':
      return latestFileMatching(path.join(PATHS.dailyBrief, 'output'), /^daily-brief-\d{4}-\d{2}-\d{2}\.md$/);
    case 'signal-watcher-commercial':
      return latestFileMatching(path.join(PATHS.commercial, 'output'), /^commercial-signals-\d{4}-\d{2}-\d{2}\.md$/);
    case 'signal-watcher-academic':
      return latestFileMatching(path.join(PATHS.academic, 'output'), /^academic-signals-\d{4}-\d{2}-\d{2}\.md$/);
    case 'intro-finder': {
      // Latest intros output across both sides.
      const cm = latestFileMatching(path.join(PATHS.commercial, 'intros', 'output'), /^intros-\d{4}-\d{2}-\d{2}\.md$/);
      const ac = latestFileMatching(path.join(PATHS.academic, 'intros', 'output'), /^intros-\d{4}-\d{2}-\d{2}\.md$/);
      if (!cm) return ac;
      if (!ac) return cm;
      return cm.mtime > ac.mtime ? cm : ac;
    }
    case 'gmail-resurfacer':
      return latestFileMatching(path.join(PATHS.resurfacer, 'output'), /^resurfacer-\d{4}-\d{2}-\d{2}\.md$/);
    case 'hubspot-manager':
      return latestFileMatching(path.join(PATHS.hubspotManager, 'output'), /^run-\d{4}-\d{2}-\d{2}\.md$/);
    case 'feedback-analyzer':
      return latestFileMatching(path.join(PATHS.feedbackInsights, 'output'), /^refinement-\d{4}-\d{2}-\d{2}\.md$/);
    case 'investor-analyzer':
      return latestFileMatching(path.join(PATHS.investorInsights, 'output'), /^refinement-\d{4}-\d{2}-\d{2}\.md$/);
    case 'pitch-deck-updater':
      return latestFileMatching(path.join(PATHS.pitchDeck, 'output'), /^proposed-edits-\d{4}-\d{2}-\d{2}\.md$/);
    case 'investor-newsletter':
      return latestFileMatching(path.join(PATHS.investorNewsletter, 'output'), /^newsletter-\d{4}-\d{2}-\d{2}\.md$/);
    default:
      return null;
  }
}

agentsRouter.get('/', async (_req, res) => {
  const tasks = await getNightingaleScheduledTasks();
  const tasksByName = new Map(tasks?.map((t) => [t.name, t]) ?? []);
  const summaries: AgentSummary[] = (Object.keys(AGENT_TRIGGERS) as AgentName[]).map((name) => {
    const taskName = AGENT_TO_TASK[name];
    const taskInfo = taskName ? tasksByName.get(taskName) : null;
    const latest = latestOutputFor(name);
    const exists = latest && fs.existsSync(latest.path);
    return {
      name,
      trigger_phrase: AGENT_TRIGGERS[name],
      scheduled_task_name: taskName,
      scheduled_task_state: taskInfo?.state ?? null,
      last_run_time: taskInfo?.last_run_time ?? null,
      next_run_time: taskInfo?.next_run_time ?? null,
      last_output_path: exists ? latest.path : null,
      last_output_generated_at: exists ? new Date(latest.mtime).toISOString() : null,
    };
  });
  res.json({ agents: summaries });
});

const RunRequestSchema = z.object({
  agent: z.enum(Object.keys(AGENT_TRIGGERS) as [AgentName, ...AgentName[]]),
});

// Per-agent timeout. Apify-driven and long-aggregating agents need more
// headroom — a full nightly hubspot-manager run with 20+ writes including
// per-attendee Apify polls can hit 10+ minutes.
const AGENT_TIMEOUT_MS: Record<AgentName, number> = {
  'hubspot-manager': 15 * 60 * 1000,
  'intro-finder': 15 * 60 * 1000,
  'signal-watcher-commercial': 15 * 60 * 1000,
  'signal-watcher-academic': 15 * 60 * 1000,
  'gmail-resurfacer': 10 * 60 * 1000,
  'feedback-analyzer': 10 * 60 * 1000,
  'daily-brief': 5 * 60 * 1000,
  // investor-analyzer chains pitch-deck-updater (Drive read + deck parse), so give it headroom.
  'investor-analyzer': 15 * 60 * 1000,
  'pitch-deck-updater': 10 * 60 * 1000,
  'investor-newsletter': 10 * 60 * 1000,
};

agentsRouter.post('/run', async (req, res) => {
  const parse = RunRequestSchema.safeParse(req.body);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_request', details: parse.error.flatten() });
    return;
  }
  const phrase = AGENT_TRIGGERS[parse.data.agent];
  const timeoutMs = AGENT_TIMEOUT_MS[parse.data.agent] ?? 5 * 60 * 1000;
  try {
    const result = await runClaude(phrase, { timeoutMs });
    res.json({
      agent: parse.data.agent,
      phrase,
      ok: result.exitCode === 0,
      exit_code: result.exitCode,
      duration_ms: result.durationMs,
      stdout: result.stdout,
      stderr: result.stderr,
    });
  } catch (err) {
    res.status(500).json({ error: 'claude_invocation_failed', detail: (err as Error).message });
  }
});

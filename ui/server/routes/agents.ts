import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { z } from 'zod';
import { PATHS, latestFileMatching } from '../lib/paths.js';
import { AGENT_TRIGGERS, type AgentName } from '../trigger-allowlist.js';
import { startRun } from '../lib/runs.js';
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

// Latest Desktop output markdown for one agent. The agent name is validated
// against AGENT_TRIGGERS (an enum), so no user-supplied path ever reaches the
// filesystem — latestOutputFor() resolves a fixed per-agent directory + regex.
// This is what the Agents tab uses to render an agent's most recent output
// uniformly, instead of wiring six different per-agent markdown endpoints.
agentsRouter.get('/:name/output', (req, res) => {
  const name = String(req.params.name);
  if (!Object.prototype.hasOwnProperty.call(AGENT_TRIGGERS, name)) {
    res.status(404).json({ error: 'unknown_agent', name });
    return;
  }
  const latest = latestOutputFor(name as AgentName);
  if (!latest || !fs.existsSync(latest.path)) {
    res.json({ found: false, message: 'No output produced yet for this agent.' });
    return;
  }
  let raw_markdown = '';
  try {
    raw_markdown = fs.readFileSync(latest.path, 'utf8');
  } catch {
    res.json({ found: false, message: 'Output file could not be read.' });
    return;
  }
  res.json({
    found: true,
    path: latest.path,
    generated_at: new Date(latest.mtime).toISOString(),
    raw_markdown,
  });
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

// Run-now is now ASYNCHRONOUS. We start the background run and return its
// run_id IMMEDIATELY — the client opens the Logs tab and polls /api/runs/:id
// for live status + log tail. This is what fixes the "spinner hangs forever"
// UX: even if a run takes 15 minutes (or wedges and is timeout-killed), the
// HTTP request returns in milliseconds and the run settles in the registry.
agentsRouter.post('/run', (req, res) => {
  const parse = RunRequestSchema.safeParse(req.body);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_request', details: parse.error.flatten() });
    return;
  }
  const agent = parse.data.agent;
  const phrase = AGENT_TRIGGERS[agent];
  const timeoutMs = AGENT_TIMEOUT_MS[agent] ?? 5 * 60 * 1000;
  try {
    const { id, done } = startRun({ phrase, kind: 'agent', label: agent, timeoutMs });
    // The run executes in the background. Attach a no-op catch so a settle path
    // we didn't await can never surface as an unhandled rejection (it won't —
    // done always resolves — but this keeps lint + future-proofing happy).
    void done.catch(() => undefined);
    res.json({ run_id: id, agent, phrase });
  } catch (err) {
    // Thrown synchronously only if the constructed phrase fails the allowlist.
    res.status(400).json({ error: 'claude_invocation_rejected', detail: (err as Error).message });
  }
});

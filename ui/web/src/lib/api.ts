// Typed fetch client for the local /api/* endpoints. Each function returns
// the parsed JSON or throws on non-2xx. Used by React Query hooks in
// queries.ts.

export interface ApiError extends Error {
  status: number;
  body?: unknown;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
  if (!res.ok) {
    let body: unknown = undefined;
    try { body = await res.json(); } catch { /* ignore */ }
    const err = new Error(`API ${res.status}: ${res.statusText}`) as ApiError;
    err.status = res.status;
    err.body = body;
    throw err;
  }
  return res.json() as Promise<T>;
}

// === Schemas (kept loose; server is the type authority) ===
export type RunMode = 'host' | 'container';

export interface HealthResp {
  ok: boolean;
  version: string;
  signals_dir: string;
  signals_dir_found: boolean;
  repo_root: string;
  host: string;
  port: number;
  // 'container' = Docker (dashboard-only): agent runs / approvals / secrets
  // edits are disabled. Absent on older servers → treat as 'host'.
  run_mode?: RunMode;
}

export interface AgentSummary {
  name: string;
  trigger_phrase: string;
  scheduled_task_name: string | null;
  scheduled_task_state: string | null;
  last_run_time: string | null;
  next_run_time: string | null;
  last_output_path: string | null;
  last_output_generated_at: string | null;
}

export interface BriefResp {
  found: boolean;
  date?: string;
  title?: string;
  file_path?: string;
  generated_at?: string;
  raw_markdown?: string;
  message?: string;
}

export interface PendingItem {
  pending_id: string;
  run_date: string;
  action_type: string;
  target_object: { type: string; id?: string; id_or_email?: string; label?: string };
  payload: Record<string, unknown>;
  rationale: string;
  queue_reason: string;
  source_quotes: string[];
  source_file_or_thread: string;
  source_file: string;
}

export interface PendingResp {
  pending: PendingItem[];
  counts: {
    total: number;
    by_day: Record<string, number>;
    by_action_type: Record<string, number>;
  };
}

export type QueueName = 'hubspot' | 'pitch-deck' | 'newsletter';

export interface QueueResp {
  queue: QueueName;
  pending: PendingItem[];
  counts: {
    total: number;
    by_day: Record<string, number>;
    by_action_type: Record<string, number>;
  };
}

export interface ActionResp {
  phrase: string;
  ok: boolean;
  exit_code: number;
  duration_ms: number;
  stdout: string;
  stderr: string;
}

export interface MdResp {
  found: boolean;
  kind?: string;
  date?: string;
  file_path?: string;
  generated_at?: string;
  raw_markdown?: string;
  message?: string;
}

export interface FeedbackReportSummary {
  date: string | null;
  file_path: string;
  generated_at: string;
  size_bytes: number;
}

export interface FeedbackReportDetail {
  date: string;
  file_path: string;
  raw_markdown: string;
}

export interface McpStatus {
  connector: string;
  authorized: boolean;
  last_notice_path: string | null;
  last_notice_at: string | null;
}

export interface TaskInfo {
  name: string;
  state: string;
  description: string;
  last_run_time: string | null;
  next_run_time: string | null;
  last_task_result: number | null;
}

export interface SecretsHealth {
  exists: boolean;
  schema_version: number | null;
  has_apify_api_token: boolean;
  has_apify_actor_id: boolean;
  has_apify_validation_url: boolean;
  has_linkedin_li_at: boolean;
  has_apify_company_roster_actor_id: boolean;
  has_pitch_deck_drive_file_id: boolean;
  has_pitch_deck_drive_url: boolean;
  has_github_pat: boolean;
  has_github_repo: boolean;
  updated_at: string | null;
}

// Unified approvals (Dashboard). Each item is a PendingItem tagged with the
// queue it came from so the row can route Apply/Reject to the right endpoint.
export type ApprovalCategory = QueueName;
export interface ApprovalItem extends PendingItem {
  category: ApprovalCategory;
}
export interface ApprovalsResp {
  approvals: ApprovalItem[];
  counts: {
    total: number;
    by_category: Record<string, number>;
  };
}

// Partial secrets update. All fields optional; optionals may be '' to clear.
export interface SecretsUpdate {
  apify_api_token?: string;
  apify_actor_id?: string;
  apify_validation_url?: string;
  linkedin_li_at?: string;
  apify_company_roster_actor_id?: string;
  pitch_deck_drive_file_id?: string;
  pitch_deck_drive_url?: string;
  github_pat?: string;
  github_repo?: string;
}
export interface SecretsSaveResp {
  ok: boolean;
  written_fields: string[];
  schema_version: number | null;
  health: SecretsHealth;
}

// Background-run registry (Logs tab).
export type RunStatus = 'running' | 'ok' | 'error' | 'timeout';
export interface RunRecord {
  id: string;
  kind: string;
  label: string;
  phrase: string;
  status: RunStatus;
  exit_code: number | null;
  started_at: string;
  duration_ms: number | null;
}
export interface RunDetail {
  run: RunRecord;
  log_tail: string;
}
export interface AgentRunResp {
  agent: string;
  // Host mode: a background run was started — poll runDetail(run_id).
  run_id?: string;
  phrase?: string;
  // Container (Docker) mode: a GitHub workflow_dispatch was fired to the
  // self-hosted runner instead of spawning the host CLI.
  dispatched?: boolean;
  workflow?: string;
}

// === Callers ===
export const api = {
  health: () => request<HealthResp>('/api/health'),

  agents: () => request<{ agents: AgentSummary[] }>('/api/agents'),
  // Run-now is async: returns a run_id immediately; poll runDetail() for status.
  agentRun: (agent: string) =>
    request<AgentRunResp>('/api/agents/run', { method: 'POST', body: JSON.stringify({ agent }) }),
  agentOutput: (name: string) => request<MdResp>(`/api/agents/${encodeURIComponent(name)}/output`),

  briefToday: () => request<BriefResp>('/api/brief/today'),

  // Unified approvals aggregator (Dashboard). Apply/Reject still route through
  // the per-queue endpoints below (pendingApply / queueApply).
  approvals: () => request<ApprovalsResp>('/api/approvals/'),

  // Background-run history + detail (Logs tab).
  runs: () => request<{ runs: RunRecord[] }>('/api/runs/'),
  runDetail: (id: string) => request<RunDetail>(`/api/runs/${encodeURIComponent(id)}`),

  // Settings tab.
  settingsSecrets: () => request<SecretsHealth>('/api/settings/secrets'),
  settingsSecretsSave: (partial: SecretsUpdate) =>
    request<SecretsSaveResp>('/api/settings/secrets', { method: 'POST', body: JSON.stringify(partial) }),
  settingsConnectors: () => request<{ connectors: McpStatus[] }>('/api/settings/connectors'),

  pending: () => request<PendingResp>('/api/pending/'),
  pendingApply: (pending_ids: number[] | 'all', run_date: string) =>
    request<ActionResp>('/api/pending/apply', {
      method: 'POST',
      body: JSON.stringify({ pending_ids, run_date }),
    }),
  pendingReject: (pending_ids: number[] | 'all', run_date: string) =>
    request<ActionResp>('/api/pending/reject', {
      method: 'POST',
      body: JSON.stringify({ pending_ids, run_date }),
    }),

  // Generic approval queues (pitch-deck, newsletter — and hubspot via the same
  // loader). `pending_ids` is omitted for single-item queues (newsletter).
  queue: (name: QueueName) => request<QueueResp>(`/api/queues/${name}`),
  queueApply: (name: QueueName, run_date: string, pending_ids?: number[] | 'all') =>
    request<ActionResp>(`/api/queues/${name}/apply`, {
      method: 'POST',
      body: JSON.stringify(pending_ids === undefined ? { run_date } : { pending_ids, run_date }),
    }),
  queueReject: (name: QueueName, run_date: string, pending_ids?: number[] | 'all') =>
    request<ActionResp>(`/api/queues/${name}/reject`, {
      method: 'POST',
      body: JSON.stringify(pending_ids === undefined ? { run_date } : { pending_ids, run_date }),
    }),

  signalsLatest: (side: 'commercial' | 'academic') =>
    request<MdResp>(`/api/signals/${side}/latest`),
  buyingGroupsLatest: (side: 'commercial' | 'academic') =>
    request<MdResp>(`/api/signals/${side}/buying-groups/latest`),
  introsLatest: (side: 'commercial' | 'academic') =>
    request<MdResp>(`/api/signals/${side}/intros/latest`),

  resurfacerLatest: () => request<MdResp>('/api/resurfacer/latest'),

  feedbackReports: () => request<{ reports: FeedbackReportSummary[] }>('/api/feedback/refinements'),
  feedbackReport: (date: string) =>
    request<FeedbackReportDetail>(`/api/feedback/refinement/${encodeURIComponent(date)}`),

  diagnosticsMcp: () => request<{ mcp_status: McpStatus[] }>('/api/diagnostics/mcp'),
  diagnosticsTasks: () => request<{ tasks: TaskInfo[] }>('/api/diagnostics/tasks'),
  diagnosticsSecrets: () => request<SecretsHealth>('/api/diagnostics/secrets'),
};

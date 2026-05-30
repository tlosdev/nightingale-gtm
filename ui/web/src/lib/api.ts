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
export interface HealthResp {
  ok: boolean;
  version: string;
  signals_dir: string;
  signals_dir_found: boolean;
  repo_root: string;
  host: string;
  port: number;
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
  updated_at: string | null;
}

// === Callers ===
export const api = {
  health: () => request<HealthResp>('/api/health'),

  agents: () => request<{ agents: AgentSummary[] }>('/api/agents'),
  agentRun: (agent: string) =>
    request<ActionResp>('/api/agents/run', { method: 'POST', body: JSON.stringify({ agent }) }),

  briefToday: () => request<BriefResp>('/api/brief/today'),

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

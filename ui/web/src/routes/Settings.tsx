import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, SecretsHealth, SecretsUpdate } from '../lib/api';
import { useContainerMode, CONTAINER_DISABLED_HINT } from '../lib/useRunMode';

type FieldKey = keyof SecretsUpdate;

interface FieldDef {
  key: FieldKey;
  label: string;
  required: boolean;
  secret: boolean; // render as password input + never echoed
  placeholder: string;
  presence: (h: SecretsHealth) => boolean;
}

const FIELDS: FieldDef[] = [
  { key: 'apify_api_token', label: 'Apify API token', required: true, secret: true, placeholder: 'apify_api_…', presence: (h) => h.has_apify_api_token },
  { key: 'apify_actor_id', label: 'Apify Actor ID (mutual connections)', required: true, secret: false, placeholder: 'username~actor-name', presence: (h) => h.has_apify_actor_id },
  { key: 'apify_validation_url', label: 'LinkedIn profile URL (validation)', required: true, secret: false, placeholder: 'https://www.linkedin.com/in/you', presence: (h) => h.has_apify_validation_url },
  { key: 'linkedin_li_at', label: 'LinkedIn li_at cookie', required: true, secret: true, placeholder: 'AQED…', presence: (h) => h.has_linkedin_li_at },
  { key: 'apify_company_roster_actor_id', label: 'Company-roster Actor ID (optional, Layer-B)', required: false, secret: false, placeholder: 'username~actor-name', presence: (h) => h.has_apify_company_roster_actor_id },
  { key: 'pitch_deck_drive_file_id', label: 'Pitch-deck Drive file ID (optional)', required: false, secret: false, placeholder: '1AbC…', presence: (h) => h.has_pitch_deck_drive_file_id },
  { key: 'pitch_deck_drive_url', label: 'Pitch-deck Drive URL (optional)', required: false, secret: false, placeholder: 'https://docs.google.com/presentation/d/…', presence: (h) => h.has_pitch_deck_drive_url },
  { key: 'github_pat', label: 'GitHub PAT (optional — Run-now in Docker + boot-catchup)', required: false, secret: true, placeholder: 'github_pat_…', presence: (h) => h.has_github_pat },
  { key: 'github_repo', label: 'GitHub repo (optional — owner/repo)', required: false, secret: false, placeholder: 'ben-nightingale/Nightingale', presence: (h) => h.has_github_repo },
];

export default function Settings() {
  const qc = useQueryClient();
  const containerMode = useContainerMode();
  const secrets = useQuery({ queryKey: ['settings', 'secrets'], queryFn: api.settingsSecrets });
  const connectors = useQuery({ queryKey: ['settings', 'connectors'], queryFn: api.settingsConnectors });

  const [drafts, setDrafts] = useState<Partial<Record<FieldKey, string>>>({});
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);

  const save = useMutation({
    mutationFn: (partial: SecretsUpdate) => api.settingsSecretsSave(partial),
    onSuccess: (resp) => {
      setResult({ ok: true, text: `Saved: ${resp.written_fields.join(', ') || '(none)'}` });
      setDrafts({});
      qc.setQueryData(['settings', 'secrets'], resp.health);
      qc.invalidateQueries({ queryKey: ['settings', 'secrets'] });
    },
    onError: (err) => {
      const e = err as { body?: { detail?: string; details?: unknown }; message: string };
      setResult({ ok: false, text: e.body?.detail ?? e.message });
    },
  });

  const submit = () => {
    // Send only fields the operator actually typed into. Empty string on an
    // optional field is a deliberate "clear" (handled by the Clear buttons).
    const partial: SecretsUpdate = {};
    for (const f of FIELDS) {
      const v = drafts[f.key];
      if (v !== undefined && v !== '') partial[f.key] = v;
    }
    if (Object.keys(partial).length === 0) {
      setResult({ ok: false, text: 'No changes to save.' });
      return;
    }
    save.mutate(partial);
  };

  const clearOptional = (key: FieldKey) => {
    save.mutate({ [key]: '' } as SecretsUpdate);
  };

  const health = secrets.data;

  return (
    <div className="p-6 max-w-3xl space-y-8">
      <header>
        <h1 className="text-2xl font-semibold">Settings</h1>
        <p className="text-sm text-gray-500 mt-1">
          Credentials are written to <code>~/.nightingale/secrets.json</code> with an owner-only lock. This panel
          shows only whether each field is set — values are never sent back to the browser.
        </p>
      </header>

      {/* ===== Credentials ===== */}
      <section>
        <h2 className="text-lg font-medium mb-3">Credentials</h2>
        {secrets.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
        {health && (
          <div className="space-y-3">
            {FIELDS.map((f) => (
              <div key={f.key} className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-3">
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-sm font-medium" htmlFor={`f-${f.key}`}>
                    {f.label}
                  </label>
                  {f.presence(health) ? (
                    <span className="text-xs text-green-700 dark:text-green-400">✓ Configured</span>
                  ) : (
                    <span className={`text-xs ${f.required ? 'text-amber-700 dark:text-amber-400' : 'text-gray-500'}`}>
                      {f.required ? '⚠ Not set' : '— Not set'}
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <input
                    id={`f-${f.key}`}
                    type={f.secret ? 'password' : 'text'}
                    autoComplete="off"
                    placeholder={f.presence(health) ? '•••••• (leave blank to keep)' : f.placeholder}
                    value={drafts[f.key] ?? ''}
                    onChange={(e) => setDrafts({ ...drafts, [f.key]: e.target.value })}
                    className="flex-1 px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-700 rounded bg-white dark:bg-gray-950 font-mono"
                  />
                  {!f.required && f.presence(health) && (
                    <button
                      type="button"
                      disabled={save.isPending || containerMode}
                      title={containerMode ? CONTAINER_DISABLED_HINT : undefined}
                      onClick={() => clearOptional(f.key)}
                      className="px-2 py-1.5 text-xs rounded border border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-50"
                    >
                      Clear
                    </button>
                  )}
                </div>
              </div>
            ))}

            <div className="flex items-center gap-3">
              <button
                type="button"
                disabled={save.isPending || containerMode}
                title={containerMode ? CONTAINER_DISABLED_HINT : undefined}
                onClick={submit}
                className="px-4 py-1.5 text-sm font-medium rounded bg-accent-600 hover:bg-accent-700 text-white disabled:opacity-50"
              >
                {save.isPending ? 'Saving…' : 'Save changes'}
              </button>
              {containerMode && <span className="text-xs text-amber-700 dark:text-amber-400">Editing disabled in Docker mode — edit on the host.</span>}
              {health.updated_at && <span className="text-xs text-gray-500">Last updated {health.updated_at} · schema v{health.schema_version ?? '?'}</span>}
            </div>

            {result && (
              <div className={`p-3 rounded border text-sm ${
                result.ok
                  ? 'border-green-500/30 bg-green-500/5 text-green-800 dark:text-green-300'
                  : 'border-red-500/30 bg-red-500/5 text-red-800 dark:text-red-300'
              }`}>
                {result.ok ? '✓ ' : '✗ '}{result.text}
                <button onClick={() => setResult(null)} className="ml-2 text-xs underline">dismiss</button>
              </div>
            )}
          </div>
        )}
      </section>

      {/* ===== Connections (claude.ai MCP) ===== */}
      <section>
        <h2 className="text-lg font-medium mb-3">Connections</h2>
        <p className="text-sm text-gray-500 mb-3">
          The agents reach Gmail, Calendar, HubSpot, Drive, Apollo, and ClinicalTrials.gov through claude.ai MCP
          connectors. Those use interactive OAuth that a browser can't complete — connect or re-authorize them in
          Claude Code directly. Status below is inferred from recent agent "not authorized" notices.
        </p>
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 dark:bg-gray-800 text-xs uppercase">
              <tr>
                <th className="px-3 py-2 text-left">Connector</th>
                <th className="px-3 py-2 text-left">Status</th>
                <th className="px-3 py-2 text-left">Last notice</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200 dark:divide-gray-800">
              {connectors.data?.connectors.map((c) => (
                <tr key={c.connector}>
                  <td className="px-3 py-2">{c.connector}</td>
                  <td className="px-3 py-2">
                    {c.authorized ? (
                      <span className="text-green-700 dark:text-green-400">✓ no recent notice</span>
                    ) : (
                      <span className="text-amber-700 dark:text-amber-400">⚠ needs re-auth</span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-xs text-gray-500">{c.last_notice_at ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <details className="mt-3">
          <summary className="text-sm text-accent-600 dark:text-accent-500 cursor-pointer">How to connect / re-authorize</summary>
          <div className="mt-2 text-sm text-gray-700 dark:text-gray-300 space-y-2">
            <p>In Claude Code, open <strong>Settings → Connectors</strong> and authorize each connector (Gmail, Google Calendar, HubSpot, Google Drive, Apollo, ClinicalTrials.gov). Each opens a claude.ai OAuth flow in your browser.</p>
            <p>If a connector shows "needs re-auth", its token likely expired — re-run the same authorize flow. The status here clears once the next agent run completes without emitting a not-authorized notice.</p>
            <p className="text-xs text-gray-500">This UI cannot drive that OAuth on your behalf; the browser can only report status.</p>
          </div>
        </details>
      </section>
    </div>
  );
}

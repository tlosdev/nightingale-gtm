// Presence-only view of ~/.nightingale/secrets.json.
//
// SECURITY: this returns BOOLEANS for which fields are populated and never the
// values themselves. Both the diagnostics endpoint and the Settings GET use
// this single helper so the "never leak secret values over the wire" boundary
// has exactly one implementation.
import fs from 'node:fs';
import { SECRETS_PATH } from './paths.js';

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
  updated_at: string | null;
}

function emptyHealth(exists: boolean): SecretsHealth {
  return {
    exists,
    schema_version: null,
    has_apify_api_token: false,
    has_apify_actor_id: false,
    has_apify_validation_url: false,
    has_linkedin_li_at: false,
    has_apify_company_roster_actor_id: false,
    has_pitch_deck_drive_file_id: false,
    has_pitch_deck_drive_url: false,
    updated_at: null,
  };
}

export function readSecretsHealth(): SecretsHealth {
  if (!fs.existsSync(SECRETS_PATH)) return emptyHealth(false);
  let parsed: Record<string, unknown>;
  try {
    // Windows PowerShell 5.1 `Set-Content -Encoding utf8` writes a UTF-8 BOM,
    // which JSON.parse rejects. Strip a leading BOM so files written by either
    // setup-secrets.ps1 or write-secrets.ps1 parse cleanly. (Strip by charcode
    // 0xFEFF rather than a literal BOM in source, which is invisible/fragile.)
    const rawText = fs.readFileSync(SECRETS_PATH, 'utf8');
    const text = rawText.charCodeAt(0) === 0xfeff ? rawText.slice(1) : rawText;
    parsed = JSON.parse(text);
  } catch {
    // Exists but malformed — report exists with everything false.
    return emptyHealth(true);
  }
  const has = (k: string) => typeof parsed[k] === 'string' && (parsed[k] as string).length > 0;
  return {
    exists: true,
    schema_version: typeof parsed.schema_version === 'number' ? parsed.schema_version : null,
    has_apify_api_token: has('apify_api_token'),
    has_apify_actor_id: has('apify_actor_id'),
    has_apify_validation_url: has('apify_validation_url'),
    has_linkedin_li_at: has('linkedin_li_at'),
    has_apify_company_roster_actor_id: has('apify_company_roster_actor_id'),
    has_pitch_deck_drive_file_id: has('pitch_deck_drive_file_id'),
    has_pitch_deck_drive_url: has('pitch_deck_drive_url'),
    updated_at: typeof parsed.updated_at === 'string' ? (parsed.updated_at as string) : null,
  };
}

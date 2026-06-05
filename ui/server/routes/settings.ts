import { Router } from 'express';
import { z } from 'zod';
import { readSecretsHealth } from '../lib/secrets-health.js';
import { writeSecrets } from '../lib/powershell.js';
import { computeMcpStatus } from './diagnostics.js';
import { canSpawnHostProcess, CONTAINER_ACTION_MESSAGE } from '../lib/runtime.js';

/**
 * Settings tab backend.
 *   GET  /api/settings/secrets     → presence-only health (never values)
 *   POST /api/settings/secrets     → partial update via scripts/write-secrets.ps1
 *   GET  /api/settings/connectors  → claude.ai MCP connector status (heuristic)
 *
 * SECURITY:
 * - GET never returns secret values, only booleans (lib/secrets-health.ts).
 * - POST accepts only the known fields, validates each shape, and hands the
 *   values to PowerShell on STDIN (never argv) so they never appear in a
 *   process listing. The script performs the ACL-first atomic write.
 * - Connector OAuth (claude.ai) cannot be driven from a browser; this endpoint
 *   only reports status. The client shows re-auth instructions.
 */
export const settingsRouter = Router();

settingsRouter.get('/secrets', (_req, res) => {
  res.json(readSecretsHealth());
});

settingsRouter.get('/connectors', (_req, res) => {
  res.json({ connectors: computeMcpStatus() });
});

// Apify Actor IDs are `username~actorname`. Validation URL must be a LinkedIn
// /in/ profile. The deck file id is an opaque Drive id. Required fields cannot
// be set to empty; optional fields MAY be set to "" to clear them.
const actorIdRe = /^[^~\s/]+~[^~\s/]+$/;

const SecretsUpdateSchema = z
  .object({
    apify_api_token: z.string().min(1).optional(),
    apify_actor_id: z.string().regex(actorIdRe, 'expected username~actor').optional(),
    apify_validation_url: z
      .string()
      .refine((u) => /linkedin\.com\/in\//i.test(u), 'expected a linkedin.com/in/ profile URL')
      .optional(),
    linkedin_li_at: z.string().min(1).optional(),
    // Optionals — empty string is allowed and means "clear this field".
    apify_company_roster_actor_id: z
      .string()
      .refine((v) => v === '' || actorIdRe.test(v), 'expected username~actor or empty')
      .optional(),
    pitch_deck_drive_file_id: z.string().optional(),
    pitch_deck_drive_url: z
      .string()
      .refine((v) => v === '' || /^https:\/\//i.test(v), 'expected an https URL or empty')
      .optional(),
  })
  .strict();

settingsRouter.post('/secrets', async (req, res) => {
  // write-secrets.ps1 needs PowerShell, which the Linux container doesn't have.
  if (!canSpawnHostProcess()) {
    res.status(503).json({ error: 'container_mode', message: CONTAINER_ACTION_MESSAGE });
    return;
  }
  const parse = SecretsUpdateSchema.safeParse(req.body);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_request', details: parse.error.flatten() });
    return;
  }
  const fields = parse.data;
  if (Object.keys(fields).length === 0) {
    res.status(400).json({ error: 'empty_update', message: 'No fields supplied.' });
    return;
  }

  // Hand the partial object to the script on stdin. The script merges it with
  // the existing secrets.json (preserving created_at, bumping updated_at).
  let result;
  try {
    result = await writeSecrets(JSON.stringify(fields));
  } catch (err) {
    res.status(500).json({ error: 'write_failed', detail: (err as Error).message });
    return;
  }

  if (!result.ok) {
    res.status(500).json({ error: 'write_failed', detail: result.error ?? 'unknown', raw: result.raw_stderr });
    return;
  }

  // Echo back presence-only health so the client refreshes without a second
  // round-trip. Never includes values.
  res.json({
    ok: true,
    written_fields: result.written_fields ?? [],
    schema_version: result.schema_version ?? null,
    health: readSecretsHealth(),
  });
});

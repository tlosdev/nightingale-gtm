import { Router } from 'express';
import path from 'node:path';
import { z } from 'zod';
import { PATHS, latestFileMatching } from '../lib/paths.js';
import { readFileOrNull, extractDateFromFilename } from '../lib/markdown.js';

export const signalsRouter = Router();

const SideSchema = z.enum(['commercial', 'academic']);

function sideRoot(side: 'commercial' | 'academic'): string {
  return side === 'commercial' ? PATHS.commercial : PATHS.academic;
}

// Helper to share the "find latest md and return parsed shape" logic.
function latestMdResponse(dir: string, pattern: RegExp, kind: string) {
  const latest = latestFileMatching(dir, pattern);
  if (!latest) {
    return { found: false, kind, message: `No ${kind} file found at ${dir}` };
  }
  const raw = readFileOrNull(latest.path);
  if (raw === null) return { found: false, kind, message: 'File disappeared between stat and read.' };
  return {
    found: true,
    kind,
    date: extractDateFromFilename(path.basename(latest.path)),
    file_path: latest.path,
    generated_at: new Date(latest.mtime).toISOString(),
    raw_markdown: raw,
  };
}

signalsRouter.get('/:side/latest', (req, res) => {
  const parse = SideSchema.safeParse(req.params.side);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_side' });
    return;
  }
  const side = parse.data;
  const outputDir = path.join(sideRoot(side), 'output');
  res.json(latestMdResponse(outputDir, new RegExp(`^${side}-signals-\\d{4}-\\d{2}-\\d{2}\\.md$`), `${side}-signal-watcher`));
});

signalsRouter.get('/:side/buying-groups/latest', (req, res) => {
  const parse = SideSchema.safeParse(req.params.side);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_side' });
    return;
  }
  const side = parse.data;
  const outputDir = path.join(sideRoot(side), 'buying-groups', 'output');
  res.json(latestMdResponse(outputDir, /^buying-group-\d{4}-\d{2}-\d{2}\.md$/, `${side}-buying-group`));
});

signalsRouter.get('/:side/intros/latest', (req, res) => {
  const parse = SideSchema.safeParse(req.params.side);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_side' });
    return;
  }
  const side = parse.data;
  const outputDir = path.join(sideRoot(side), 'intros', 'output');
  res.json(latestMdResponse(outputDir, /^intros-\d{4}-\d{2}-\d{2}\.md$/, `${side}-intros`));
});

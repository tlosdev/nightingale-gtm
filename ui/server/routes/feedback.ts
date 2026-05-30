import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { z } from 'zod';
import { PATHS } from '../lib/paths.js';
import { readFileOrNull, extractDateFromFilename } from '../lib/markdown.js';

export const feedbackRouter = Router();

const DateParamSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

feedbackRouter.get('/refinements', (_req, res) => {
  const outputDir = path.join(PATHS.feedbackInsights, 'output');
  if (!fs.existsSync(outputDir)) {
    res.json({ reports: [] });
    return;
  }
  const reports = fs
    .readdirSync(outputDir)
    .filter((name) => /^refinement-\d{4}-\d{2}-\d{2}\.md$/.test(name))
    .map((name) => {
      const full = path.join(outputDir, name);
      const stat = fs.statSync(full);
      return {
        date: extractDateFromFilename(name),
        file_path: full,
        generated_at: stat.mtime.toISOString(),
        size_bytes: stat.size,
      };
    })
    .sort((a, b) => (b.date ?? '').localeCompare(a.date ?? ''));
  res.json({ reports });
});

feedbackRouter.get('/refinement/:date', (req, res) => {
  const parse = DateParamSchema.safeParse(req.params.date);
  if (!parse.success) {
    res.status(400).json({ error: 'invalid_date_format' });
    return;
  }
  const file = path.join(PATHS.feedbackInsights, 'output', `refinement-${parse.data}.md`);
  const raw = readFileOrNull(file);
  if (raw === null) {
    res.status(404).json({ error: 'not_found', message: `No refinement report at ${file}` });
    return;
  }
  res.json({ date: parse.data, file_path: file, raw_markdown: raw });
});

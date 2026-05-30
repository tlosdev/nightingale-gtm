import { Router } from 'express';
import path from 'node:path';
import { PATHS, latestFileMatching } from '../lib/paths.js';
import { readFileOrNull, extractDateFromFilename, extractH1 } from '../lib/markdown.js';

export const briefRouter = Router();

briefRouter.get('/today', (_req, res) => {
  const outputDir = path.join(PATHS.dailyBrief, 'output');
  const latest = latestFileMatching(outputDir, /^daily-brief-\d{4}-\d{2}-\d{2}\.md$/);
  if (!latest) {
    res.json({
      found: false,
      message: 'No daily-brief file found on Desktop yet. Run `daily brief morning` to generate one.',
    });
    return;
  }
  const raw = readFileOrNull(latest.path);
  if (raw === null) {
    res.status(500).json({ error: 'Brief file disappeared between stat and read.' });
    return;
  }
  const date = extractDateFromFilename(path.basename(latest.path));
  res.json({
    found: true,
    date,
    title: extractH1(raw),
    file_path: latest.path,
    generated_at: new Date(latest.mtime).toISOString(),
    raw_markdown: raw,
  });
});

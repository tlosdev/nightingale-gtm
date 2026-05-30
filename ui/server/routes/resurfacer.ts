import { Router } from 'express';
import path from 'node:path';
import { PATHS, latestFileMatching } from '../lib/paths.js';
import { readFileOrNull, extractDateFromFilename } from '../lib/markdown.js';

export const resurfacerRouter = Router();

resurfacerRouter.get('/latest', (_req, res) => {
  const outputDir = path.join(PATHS.resurfacer, 'output');
  const latest = latestFileMatching(outputDir, /^resurfacer-\d{4}-\d{2}-\d{2}\.md$/);
  if (!latest) {
    res.json({
      found: false,
      message: 'No re-surfacer file found yet. Run `gmail resurfacer daily morning` to generate one.',
    });
    return;
  }
  const raw = readFileOrNull(latest.path);
  if (raw === null) {
    res.status(500).json({ error: 'File disappeared between stat and read.' });
    return;
  }
  res.json({
    found: true,
    date: extractDateFromFilename(path.basename(latest.path)),
    file_path: latest.path,
    generated_at: new Date(latest.mtime).toISOString(),
    raw_markdown: raw,
  });
});

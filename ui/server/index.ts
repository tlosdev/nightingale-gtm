// Nightingale UI — Express server entry.
//
// Binds to 127.0.0.1 only (never 0.0.0.0). Serves the built React app from
// web/dist + a small REST API at /api/*. Mutation surfaces are: spawning
// `claude -p "<allowlisted phrase>"`, the dedicated write-secrets.ps1 script
// (Settings), and (read-only) `powershell Get-ScheduledTask`. The only place
// the server writes under ~/Desktop/nightingale-signals/** is the server-owned
// run registry at _runs/ (lib/runs.ts) — never an agent's output tree.
import express from 'express';
import helmet from 'helmet';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { SIGNALS_ROOT, repoRoot } from './lib/paths.js';
import { briefRouter } from './routes/brief.js';
import { pendingRouter } from './routes/pending.js';
import { queuesRouter } from './routes/queues.js';
import { signalsRouter } from './routes/signals.js';
import { resurfacerRouter } from './routes/resurfacer.js';
import { feedbackRouter } from './routes/feedback.js';
import { agentsRouter } from './routes/agents.js';
import { diagnosticsRouter } from './routes/diagnostics.js';
import { approvalsRouter } from './routes/approvals.js';
import { settingsRouter } from './routes/settings.js';
import { runsRouter } from './routes/runs.js';

const PORT = Number(process.env.NIGHTINGALE_UI_PORT ?? 8765);
const HOST = '127.0.0.1';  // loopback ONLY — never bind to 0.0.0.0

const app = express();

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      // React sometimes emits inline styles for layout; allow them. No inline scripts.
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      // Allow https images so markdown rendering doesn't break on external img refs
      // (CT.gov, persona docs, etc.). data: kept for our SVG favicon.
      imgSrc: ["'self'", 'data:', 'https:'],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      frameAncestors: ["'none'"],
    },
  },
  // No HSTS — loopback HTTP only.
  hsts: false,
  // COEP=require-corp would silently block external images from servers that
  // don't send Cross-Origin-Resource-Policy headers (which is most of them).
  // Disable so markdown img tags actually render.
  crossOriginEmbedderPolicy: false,
}));

// Strict body parser: only application/json content-type, max 64kb. Defends
// against `text/plain` form-post bypass attempts even though CORS already
// rejects cross-origin.
app.use(express.json({ type: 'application/json', limit: '64kb' }));

// Per-request UUID for correlating an error response with a server log line.
// Operators debugging a failed apply can grep for the id in the terminal.
app.use((_req, res, next) => {
  res.locals.requestId = crypto.randomUUID();
  next();
});

// Hand-rolled CORS: only allow same-origin (the server itself). No
// Access-Control-Allow-Origin: * ever. Browser tabs on other origins
// (including other localhost ports) get blocked.
app.use((req, res, next) => {
  // Always set Vary: Origin so intermediate caches don't reuse a CORS-tagged
  // response across origins.
  res.setHeader('Vary', 'Origin');
  const origin = req.headers.origin;
  const selfOrigin = `http://${HOST}:${PORT}`;
  if (origin && origin === selfOrigin) {
    res.setHeader('Access-Control-Allow-Origin', selfOrigin);
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  }
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  next();
});

// Health endpoint — used by the start-ui.ps1 launcher to know when to open the browser.
app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    version: '0.1.0',
    signals_dir: SIGNALS_ROOT,
    signals_dir_found: fs.existsSync(SIGNALS_ROOT),
    repo_root: repoRoot(),
    host: HOST,
    port: PORT,
  });
});

app.use('/api/brief', briefRouter);
app.use('/api/pending', pendingRouter);
app.use('/api/hubspot', pendingRouter); // alias: /api/hubspot/apply + /api/hubspot/reject
app.use('/api/queues', queuesRouter);   // generic approval queues: hubspot / pitch-deck / newsletter
app.use('/api/signals', signalsRouter);
app.use('/api/buying-groups', signalsRouter); // legacy alias if frontend uses it
app.use('/api/intros', signalsRouter); // legacy alias
app.use('/api/resurfacer', resurfacerRouter);
app.use('/api/feedback', feedbackRouter);
app.use('/api/agents', agentsRouter);
app.use('/api/diagnostics', diagnosticsRouter);
app.use('/api/approvals', approvalsRouter); // unified, category-tagged approvals (Dashboard)
app.use('/api/settings', settingsRouter);   // editable secrets + connector status
app.use('/api/runs', runsRouter);           // background-run history + live status (Logs)

// Static frontend served from web/dist. fileURLToPath handles Windows paths
// + percent-encoding correctly (paths with spaces work).
const distDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'web', 'dist');
if (fs.existsSync(distDir)) {
  app.use(express.static(distDir, { index: 'index.html', maxAge: 0 }));
  // SPA fallback — any non-API path serves index.html.
  app.get(/^\/(?!api\/).*/, (_req, res) => {
    res.sendFile(path.join(distDir, 'index.html'));
  });
} else {
  // dist not built yet — return a helpful message instead of 404.
  app.get('/', (_req, res) => {
    res.status(503).type('text/plain').send(
      `Frontend not built yet. Run "npm run build" in the ui/ directory, then refresh.\nLooked for: ${distDir}`,
    );
  });
}

// Error handler — log + return JSON. Never leak stack traces.
// Includes a request_id correlating the log line with the response.
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  const requestId = (res.locals.requestId as string | undefined) ?? 'no-id';
  console.error(`[ui] [${requestId}]`, err);
  if (!res.headersSent) {
    res.status(500).json({ error: 'internal_error', request_id: requestId });
  }
});

const server = app.listen(PORT, HOST, () => {
  console.log(`Nightingale UI listening on http://${HOST}:${PORT}`);
  console.log(`Signals tree: ${SIGNALS_ROOT}${fs.existsSync(SIGNALS_ROOT) ? '' : ' (does NOT exist yet)'}`);
});

const shutdown = () => {
  console.log('\nShutting down...');
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

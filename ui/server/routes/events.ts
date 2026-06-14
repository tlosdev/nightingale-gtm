// SSE endpoint: GET /api/events
//
// Opens a long-lived text/event-stream the browser subscribes to via
// EventSource. The server pushes a `change` event (with affected channels)
// whenever the signals tree changes — see lib/events.ts. This is what makes the
// dashboard event-driven instead of polling on a clock.
import { Router } from 'express';
import crypto from 'node:crypto';
import { addClient, removeClient } from '../lib/events.js';

export const eventsRouter = Router();

eventsRouter.get('/', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    // Disable proxy buffering (harmless on loopback; correct if ever fronted).
    'X-Accel-Buffering': 'no',
  });
  // Ask EventSource to reconnect 3s after any drop, and confirm the stream is up.
  res.write('retry: 3000\n\n');
  res.write('event: hello\ndata: {}\n\n');

  const client = { id: crypto.randomUUID(), res };
  addClient(client);

  req.on('close', () => removeClient(client));
});

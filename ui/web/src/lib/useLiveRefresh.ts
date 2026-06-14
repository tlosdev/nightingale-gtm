import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useContainerMode } from './useRunMode';

// Query keys refreshed when the signals tree's data area changes (outputs,
// pending queues, agent state). Kept in sync with the keys used across the app.
// Exported so a finished UI run (AgentsControlPanel) can invalidate the same set.
export const DATA_KEYS = [['approvals'], ['brief', 'today'], ['resurfacer', 'latest'], ['agents']];

/**
 * Event-driven dashboard refresh. Subscribes to the server's SSE stream
 * (/api/events) and invalidates the affected React Query keys when the agent
 * output tree changes on disk — which happens for scheduled runs, terminal
 * `claude -p` runs, AND the UI "Run now" button alike. No clock-based polling.
 *
 * Container (Docker) mode exception: fs.watch events don't cross the read-only
 * Windows->container bind mount, so SSE never fires there. We fall back to a
 * slow 30s poll in that mode only. Host mode (the default) is fully push-based.
 *
 * Mount once, high in the tree (Layout).
 */
export function useLiveRefresh(): void {
  const qc = useQueryClient();
  const containerMode = useContainerMode();

  useEffect(() => {
    if (containerMode) {
      const t = setInterval(() => qc.invalidateQueries(), 30_000);
      return () => clearInterval(t);
    }

    const es = new EventSource('/api/events');
    es.addEventListener('change', (e) => {
      let channels: string[] = ['data'];
      try {
        const parsed = JSON.parse((e as MessageEvent).data);
        if (Array.isArray(parsed?.channels)) channels = parsed.channels;
      } catch {
        // malformed frame — fall back to refreshing data
      }
      if (channels.includes('runs')) qc.invalidateQueries({ queryKey: ['runs'] });
      if (channels.includes('data')) {
        for (const key of DATA_KEYS) qc.invalidateQueries({ queryKey: key });
      }
    });
    // EventSource auto-reconnects on error (server sends `retry: 3000`), so we
    // don't tear down on transient errors — only on unmount.
    return () => es.close();
  }, [qc, containerMode]);
}

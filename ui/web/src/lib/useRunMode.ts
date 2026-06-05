import { useQuery } from '@tanstack/react-query';
import { api } from './api';

// Shared health query (one fetch, deduped by React Query across components).
// run_mode is near-static for the life of the server, so cache it long.
export function useContainerMode(): boolean {
  const health = useQuery({
    queryKey: ['health'],
    queryFn: api.health,
    staleTime: 5 * 60 * 1000,
    refetchOnWindowFocus: false,
  });
  return health.data?.run_mode === 'container';
}

export const CONTAINER_DISABLED_HINT =
  'Disabled in Docker (container) mode — run the UI natively on the host (scripts/start-ui.ps1) to use this.';

import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import './styles.css';

// Apply dark mode BEFORE React mounts so first paint matches preference.
// This used to live as an inline script in index.html, but CSP scriptSrc:
// 'self' rejects inline scripts. Inside the bundle is allowed.
(() => {
  try {
    const stored = localStorage.getItem('nightingale-theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    if (stored === 'dark' || (!stored && prefersDark)) {
      document.documentElement.classList.add('dark');
    }
  } catch (e) {
    // localStorage can throw in private-window / restricted contexts; ignore.
  }
})();

// Global React Query client. Defaults are conservative for most queries
// (stale after 30s, refetch on focus). The /api/health endpoint is overridden
// per-query with a longer staleTime + no focus refetch since it's near-static.
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30 * 1000,
      retry: 1,
      refetchOnWindowFocus: true,
    },
  },
});

const rootEl = document.getElementById('root');
if (!rootEl) throw new Error('Could not find #root');

ReactDOM.createRoot(rootEl).render(
  <React.StrictMode>
    <BrowserRouter>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </BrowserRouter>
  </React.StrictMode>,
);

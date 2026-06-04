import { NavLink, Outlet } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';
import { useEffect, useState } from 'react';

const NAV = [
  { to: '/', label: 'Dashboard', end: true },
  { to: '/brief', label: "Today's Brief" },
  { to: '/pending', label: 'Pending Approvals', badge: true },
  { to: '/pitch-deck', label: 'Pitch Deck Edits' },
  { to: '/newsletter', label: 'Investor Newsletter' },
  { to: '/agents', label: 'Agents' },
  { to: '/signals/commercial', label: 'Signals' },
  { to: '/resurfacer', label: 'Re-surfacer' },
  { to: '/feedback', label: 'Feedback' },
  { to: '/diagnostics', label: 'Diagnostics' },
] as const;

export function Layout() {
  const pending = useQuery({ queryKey: ['pending'], queryFn: () => api.pending() });
  const pendingCount = pending.data?.counts.total ?? 0;
  return (
    <div className="flex h-full">
      <aside className="w-56 shrink-0 border-r border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 flex flex-col">
        <header className="px-4 py-3 border-b border-gray-200 dark:border-gray-800 flex items-center gap-2">
          <span className="inline-block w-6 h-6 rounded-full bg-accent-500" />
          <h1 className="text-sm font-semibold">Nightingale</h1>
        </header>
        <nav className="flex-1 overflow-y-auto px-2 py-3 space-y-0.5">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={'end' in item ? item.end : false}
              className={({ isActive }) =>
                `flex items-center justify-between px-3 py-1.5 rounded text-sm transition-colors ${
                  isActive
                    ? 'bg-accent-500/10 text-accent-700 dark:text-accent-500 font-medium'
                    : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800'
                }`
              }
            >
              <span>{item.label}</span>
              {'badge' in item && item.badge && pendingCount > 0 && (
                <span className="text-xs bg-amber-500 text-white rounded-full px-1.5 py-0.5 min-w-[1.25rem] text-center">
                  {pendingCount}
                </span>
              )}
            </NavLink>
          ))}
        </nav>
        <ThemeToggle />
      </aside>
      <main className="flex-1 overflow-y-auto">
        <Outlet />
      </main>
    </div>
  );
}

function ThemeToggle() {
  const [theme, setTheme] = useState<'light' | 'dark'>(() =>
    document.documentElement.classList.contains('dark') ? 'dark' : 'light',
  );
  useEffect(() => {
    if (theme === 'dark') document.documentElement.classList.add('dark');
    else document.documentElement.classList.remove('dark');
    try { localStorage.setItem('nightingale-theme', theme); } catch { /* ignore */ }
  }, [theme]);
  return (
    <div className="px-3 py-2 border-t border-gray-200 dark:border-gray-800">
      <button
        type="button"
        onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
        className="w-full text-xs text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100 text-left"
      >
        {theme === 'dark' ? '☀ Switch to light' : '☾ Switch to dark'}
      </button>
    </div>
  );
}

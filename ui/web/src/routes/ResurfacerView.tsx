import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';

export default function ResurfacerView() {
  const r = useQuery({ queryKey: ['resurfacer', 'latest'], queryFn: api.resurfacerLatest });
  return (
    <div className="p-6 max-w-5xl">
      <header className="mb-4 flex items-baseline justify-between">
        <h1 className="text-2xl font-semibold">Re-surfacer</h1>
        {r.data?.found && r.data.date && <span className="text-xs text-gray-500">{r.data.date}</span>}
      </header>
      <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
        {r.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
        {r.data && !r.data.found && <p className="text-sm text-gray-500">{r.data.message}</p>}
        {r.data?.found && r.data.raw_markdown && <MarkdownRenderer markdown={r.data.raw_markdown} />}
      </article>
    </div>
  );
}

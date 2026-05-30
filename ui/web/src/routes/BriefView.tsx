import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';

export default function BriefView() {
  const brief = useQuery({ queryKey: ['brief', 'today'], queryFn: api.briefToday });

  return (
    <div className="p-6 max-w-5xl">
      <header className="mb-4 flex items-baseline justify-between">
        <h1 className="text-2xl font-semibold">Today's Brief</h1>
        {brief.data?.found && brief.data.generated_at && (
          <span className="text-xs text-gray-500">Generated {new Date(brief.data.generated_at).toLocaleString()}</span>
        )}
      </header>

      {brief.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
      {brief.error && <p className="text-sm text-red-500">Failed to load brief.</p>}
      {brief.data && !brief.data.found && (
        <div className="rounded-lg border border-gray-200 dark:border-gray-800 p-4 bg-white dark:bg-gray-900">
          <p className="text-sm text-gray-500">{brief.data.message}</p>
        </div>
      )}
      {brief.data?.found && brief.data.raw_markdown && (
        <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6">
          <MarkdownRenderer markdown={brief.data.raw_markdown} />
        </article>
      )}
      {brief.data?.found && brief.data.file_path && (
        <p className="mt-3 text-xs text-gray-500">
          Source: <code>{brief.data.file_path}</code>
        </p>
      )}
    </div>
  );
}

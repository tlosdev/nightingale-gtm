import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';

export default function FeedbackRefinementView() {
  const reports = useQuery({ queryKey: ['feedback', 'reports'], queryFn: api.feedbackReports });
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const detail = useQuery({
    queryKey: ['feedback', 'report', selectedDate],
    queryFn: () => api.feedbackReport(selectedDate!),
    enabled: !!selectedDate,
  });

  return (
    <div className="p-6 max-w-6xl">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold">Feedback refinements</h1>
        <p className="text-sm text-gray-500 mt-1">
          Propose-only persona-refinement reports. To accept any diff, copy the trigger phrase shown in the report
          and run it manually (or paste it into Claude Code).
        </p>
      </header>

      <div className="grid grid-cols-[14rem_1fr] gap-6">
        <aside className="space-y-1">
          {reports.isLoading && <p className="text-xs text-gray-500">Loading…</p>}
          {reports.data?.reports.length === 0 && (
            <p className="text-xs text-gray-500">No reports yet. Run <code>ANALYZE feedback</code>.</p>
          )}
          {reports.data?.reports.map((r) => (
            <button
              key={r.file_path}
              type="button"
              onClick={() => setSelectedDate(r.date)}
              className={`w-full text-left text-sm px-3 py-1.5 rounded transition-colors ${
                selectedDate === r.date
                  ? 'bg-accent-500/10 text-accent-700 dark:text-accent-500 font-medium'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800'
              }`}
            >
              {r.date}
              <span className="block text-xs text-gray-500">{(r.size_bytes / 1024).toFixed(1)} KB</span>
            </button>
          ))}
        </aside>
        <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-6 min-h-[20rem]">
          {!selectedDate && (
            <p className="text-sm text-gray-500">Select a report from the left.</p>
          )}
          {selectedDate && detail.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
          {selectedDate && detail.data && (
            <MarkdownRenderer markdown={detail.data.raw_markdown} />
          )}
        </article>
      </div>
    </div>
  );
}

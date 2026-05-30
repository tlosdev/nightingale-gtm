import { NavLink, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';
import { MarkdownRenderer } from '../components/MarkdownRenderer';

const TABS = [
  { key: 'sweep', label: 'Sweep' },
  { key: 'buying-groups', label: 'Buying groups' },
  { key: 'intros', label: 'Intros' },
] as const;

type Tab = (typeof TABS)[number]['key'];

export default function SignalsView() {
  const { side } = useParams<{ side: 'commercial' | 'academic' }>();
  const validSide: 'commercial' | 'academic' = side === 'academic' ? 'academic' : 'commercial';

  return (
    <div className="p-6 max-w-5xl">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold capitalize">{validSide} signals</h1>
        <div className="mt-3 flex gap-1">
          <SideToggle side="commercial" current={validSide} />
          <SideToggle side="academic" current={validSide} />
        </div>
      </header>
      <SideContent side={validSide} />
    </div>
  );
}

function SideToggle({ side, current }: { side: 'commercial' | 'academic'; current: string }) {
  return (
    <NavLink
      to={`/signals/${side}`}
      className={`px-3 py-1 text-sm rounded border ${
        current === side
          ? 'bg-accent-600 text-white border-accent-600'
          : 'border-gray-300 dark:border-gray-700 hover:bg-gray-100 dark:hover:bg-gray-800'
      }`}
    >
      {side}
    </NavLink>
  );
}

function SideContent({ side }: { side: 'commercial' | 'academic' }) {
  return (
    <>
      <Section title="Latest sweep" query={() => api.signalsLatest(side)} queryKey={['signals', side]} />
      <Section title="Latest buying group" query={() => api.buyingGroupsLatest(side)} queryKey={['buying-groups', side]} />
      <Section title="Latest intros" query={() => api.introsLatest(side)} queryKey={['intros', side]} />
    </>
  );
}

function Section<T extends { found: boolean; raw_markdown?: string; message?: string; date?: string; file_path?: string; generated_at?: string }>(
  { title, query, queryKey }: { title: string; query: () => Promise<T>; queryKey: string[] },
) {
  const result = useQuery({ queryKey, queryFn: query });
  return (
    <section className="mb-6">
      <div className="flex items-baseline justify-between mb-2">
        <h2 className="text-lg font-medium">{title}</h2>
        {result.data?.found && result.data.date && (
          <span className="text-xs text-gray-500">{result.data.date}</span>
        )}
      </div>
      <article className="rounded-lg border border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 p-4">
        {result.isLoading && <p className="text-sm text-gray-500">Loading…</p>}
        {result.data && !result.data.found && (
          <p className="text-sm text-gray-500">{result.data.message ?? 'No output yet.'}</p>
        )}
        {result.data?.found && result.data.raw_markdown && (
          <MarkdownRenderer markdown={result.data.raw_markdown} />
        )}
      </article>
    </section>
  );
}

// Registry of approval queues surfaced in the dashboard. Each queue is a
// Desktop subtree (pending/*.json + state/approval-history.jsonl) written by
// an agent, read by routes/queues.ts, and decided via an allowlisted
// `<verb> <noun> [<ids> ]from <date>` trigger phrase that re-invokes the agent.
//
// SECURITY: the `verb`/`noun`/`idStyle` here drive the phrase the server
// constructs and hands to runClaude(). The constructed phrase is ALWAYS
// re-validated against trigger-allowlist.ts before spawning — adding a queue
// here without the matching allowlist regex makes apply/reject fail closed.
import { PATHS } from './paths.js';

export interface QueueConfig {
  /** Desktop subtree root (contains pending/ + state/). */
  subdir: string;
  /** Approve/apply verb pair, e.g. ['apply','reject'] or ['approve','reject']. */
  verbs: readonly [string, string];
  /** Noun phrase in the trigger, e.g. 'hubspot updates'. */
  noun: string;
  /**
   * 'list'  → phrase carries a comma-separated numeric id list (or 'all'):
   *           `<verb> <noun> <ids> from <date>`  (hubspot, pitch-deck)
   * 'none'  → single-item queue, no id list:
   *           `<verb> <noun> from <date>`         (newsletter)
   */
  idStyle: 'list' | 'none';
}

export const QUEUES: Readonly<Record<string, QueueConfig>> = {
  hubspot: {
    subdir: PATHS.hubspotManager,
    verbs: ['apply', 'reject'],
    noun: 'hubspot updates',
    idStyle: 'list',
  },
  'pitch-deck': {
    subdir: PATHS.pitchDeck,
    verbs: ['apply', 'reject'],
    noun: 'pitch-deck updates',
    idStyle: 'list',
  },
  newsletter: {
    subdir: PATHS.investorNewsletter,
    verbs: ['approve', 'reject'],
    noun: 'newsletter draft',
    idStyle: 'none',
  },
} as const;

export type QueueName = keyof typeof QUEUES;

export function isQueueName(name: string): name is QueueName {
  return Object.prototype.hasOwnProperty.call(QUEUES, name);
}

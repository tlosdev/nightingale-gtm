// SECURITY-CRITICAL: this allowlist is the only thing standing between an
// API caller and an arbitrary `claude -p "..."` invocation. The set of
// allowed trigger phrases must exactly match the set the agents themselves
// understand — adding a regex here without a corresponding agent trigger
// has no effect; ADDING A REGEX HERE THAT MATCHES MORE THAN INTENDED IS
// A SECURITY HOLE.
//
// Two flavors of regex:
//  1. Exact-match phrases for agent runs (no user-supplied data interpolated).
//  2. Parameterized phrases for HubSpot apply/reject, which the server
//     CONSTRUCTS from validated request fields (numeric IDs + ISO date),
//     then matches against the regex as belt-and-suspenders.

export const ALLOWED_TRIGGER_PATTERNS: ReadonlyArray<RegExp> = [
  // === Agent-run triggers (cron-equivalent or named manual phrases) ===
  /^daily brief morning$/,
  /^daily brief dry run$/,
  /^RUN daily brief$/,
  /^brief me on today$/,
  /^weekly commercial sweep$/,
  /^weekly academic sweep$/,
  /^intro-finder daily morning$/,
  /^RUN intro-finder$/,
  /^find intros from latest commercial buying group$/,
  /^find intros from latest academic buying group$/,
  /^gmail resurfacer daily morning$/,
  /^RUN gmail resurfacer$/,
  /^re-surface my inbox$/,
  /^nightly hubspot manage$/,
  /^RUN hubspot-manager$/,
  /^ANALYZE feedback$/,
  /^ANALYZE email replies$/,
  /^ANALYZE calls$/,
  /^RUN feedback-analyzer$/,
  /^WEEKLY feedback insights$/,
  /^list pending hubspot updates$/,

  // === Investor-side loop (investor-analyzer / pitch-deck-updater / newsletter) ===
  /^RUN investor-analyzer$/,
  /^ANALYZE investor feedback$/,
  /^WEEKLY investor insights$/,
  /^RUN pitch-deck-updater$/,
  /^update pitch deck$/,
  /^RUN investor-newsletter$/,
  /^compose investor newsletter$/,

  // === Apply / reject — strict numeric ID lists + ISO date ===
  // `pending_ids` are constructed server-side from validated integers; this
  // regex re-validates the constructed phrase as defense-in-depth.
  /^apply hubspot updates (all|\d+(,\d+)*) from \d{4}-\d{2}-\d{2}$/,
  /^reject hubspot updates (all|\d+(,\d+)*) from \d{4}-\d{2}-\d{2}$/,
  /^apply pitch-deck updates (all|\d+(,\d+)*) from \d{4}-\d{2}-\d{2}$/,
  /^reject pitch-deck updates (all|\d+(,\d+)*) from \d{4}-\d{2}-\d{2}$/,

  // === Newsletter decision — single-item queue, no id list ===
  /^approve newsletter draft from \d{4}-\d{2}-\d{2}$/,
  /^reject newsletter draft from \d{4}-\d{2}-\d{2}$/,
];

export function isPhraseAllowed(phrase: string): boolean {
  if (typeof phrase !== 'string' || phrase.length === 0 || phrase.length > 300) {
    return false;
  }
  // No newlines, no shell metacharacters that could affect spawn even with
  // shell: false (defense in depth — the subprocess is invoked with arg
  // arrays, not a shell string, but rejecting these characters here keeps
  // the audit story simple).
  if (/[\n\r\t\0;|&`$<>]/.test(phrase)) {
    return false;
  }
  return ALLOWED_TRIGGER_PATTERNS.some((re) => re.test(phrase));
}

/**
 * Friendly names for the agents, used to validate `/api/agents/run` requests.
 * Each maps to the canonical trigger phrase the cron (or chain) uses.
 */
export const AGENT_TRIGGERS: Readonly<Record<string, string>> = {
  'daily-brief': 'daily brief morning',
  'signal-watcher-commercial': 'weekly commercial sweep',
  'signal-watcher-academic': 'weekly academic sweep',
  'intro-finder': 'intro-finder daily morning',
  'gmail-resurfacer': 'gmail resurfacer daily morning',
  'hubspot-manager': 'nightly hubspot manage',
  'feedback-analyzer': 'ANALYZE feedback',
  'investor-analyzer': 'RUN investor-analyzer',
  'pitch-deck-updater': 'RUN pitch-deck-updater',
  'investor-newsletter': 'RUN investor-newsletter',
};

export type AgentName = keyof typeof AGENT_TRIGGERS;

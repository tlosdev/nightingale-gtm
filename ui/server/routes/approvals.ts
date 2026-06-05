import { Router } from 'express';
import { loadUndecidedForQueue, type UndecidedPendingItem } from '../lib/pending.js';
import { QUEUES, type QueueName } from '../lib/queues.js';

/**
 * Unified approvals aggregator for the Dashboard. Merges every registered
 * approval queue (hubspot / pitch-deck / newsletter) into one list, tagging
 * each item with its `category` so the Dashboard can render a single list with
 * per-row category chips and route Apply/Reject back to the correct existing
 * per-queue endpoint.
 *
 *   GET /api/approvals → { approvals: (item & {category})[], counts }
 *
 * This is purely a READ aggregator. The decision endpoints stay where they
 * are: HubSpot via /api/pending/{apply,reject}, the rest via
 * /api/queues/:queue/{apply,reject}. Nothing here constructs a trigger phrase.
 */
export const approvalsRouter = Router();

export interface ApprovalItem extends UndecidedPendingItem {
  category: QueueName;
}

approvalsRouter.get('/', (_req, res) => {
  const approvals: ApprovalItem[] = [];
  const byCategory: Record<string, number> = {};

  for (const category of Object.keys(QUEUES) as QueueName[]) {
    const items = loadUndecidedForQueue(QUEUES[category].subdir);
    byCategory[category] = items.length;
    for (const item of items) {
      approvals.push({ ...item, category });
    }
  }

  // Newest first, then category, then id — stable ordering for the UI.
  approvals.sort((a, b) => {
    if (a.run_date !== b.run_date) return b.run_date.localeCompare(a.run_date);
    if (a.category !== b.category) return a.category.localeCompare(b.category);
    return a.pending_id.localeCompare(b.pending_id);
  });

  res.json({
    approvals,
    counts: {
      total: approvals.length,
      by_category: byCategory,
    },
  });
});

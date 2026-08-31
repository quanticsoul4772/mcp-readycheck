// report.ts — the audit-report view's pure transforms.
//
// Kept separate from view.tsx so the ten locked tests can exercise them under
// node:test without a DOM (decide D1). Nothing here touches React, the network
// or the host bridge.
//
// The rule that governs this whole file: `category`, `severity` and `scope` are
// open vocabularies. A real audit of this server returned four category slugs —
// connectivity, tool-metadata, client-compatibility, resource-metadata — not
// the six documented prose names. Nothing here renames, drops, defaults or
// enumerates a value the API sent.

/** One check as the view reads it. Mirrors `checkSchema` in lib/audit-schema.ts. */
export interface ViewCheck {
  id: string;
  checkId: string;
  checkName: string;
  status: string;
  severity: string;
  category: string;
  scope: string;
  platforms: string[];
  message: string | null;
  details: unknown;
  hint: unknown;
  durationMs: number | null;
}

export interface CategoryGroup {
  category: string;
  checks: ViewCheck[];
}

/**
 * Display order for the categories seen so far.
 *
 * A lookup, never a filter: a slug absent from this map still renders, under
 * its raw name, after everything known. Adding a slug here changes only where
 * its heading appears.
 */
const CATEGORY_ORDER: Record<string, number> = {
  connectivity: 0,
  "tool-metadata": 1,
  "resource-metadata": 2,
  "client-compatibility": 3,
};

/** Rank for sorting. Unknown slugs sort after every known one. */
export function categoryRank(category: string): number {
  const known = CATEGORY_ORDER[category];
  return known === undefined ? Number.MAX_SAFE_INTEGER : known;
}

/**
 * Groups checks by the category the API reported.
 *
 * Known categories come first in lookup order; anything unrecognised follows,
 * alphabetically among itself, under its raw slug. Every input check lands in
 * exactly one group.
 */
export function groupByCategory(checks: readonly ViewCheck[]): CategoryGroup[] {
  const byCategory = new Map<string, ViewCheck[]>();
  for (const check of checks) {
    const existing = byCategory.get(check.category);
    if (existing) existing.push(check);
    else byCategory.set(check.category, [check]);
  }

  return [...byCategory.entries()]
    .map(([category, group]) => ({ category, checks: group }))
    .sort((a, b) => {
      const rank = categoryRank(a.category) - categoryRank(b.category);
      // Two unknowns share a rank, so fall back to the slug itself.
      return rank !== 0 ? rank : a.category.localeCompare(b.category);
    });
}

/** How a readiness flag reads. `null` is unknown — never "not ready". */
export function readinessLabel(flag: boolean | null | undefined): string {
  if (flag === true) return "ready";
  if (flag === false) return "not ready";
  return "unknown";
}

/**
 * Whether an audit has settled.
 *
 * This vocabulary is the audit's alone. A deployment settles at `running`;
 * here `running` means still in progress. No terminal check is ever shared
 * between the two.
 */
export function isTerminal(status: string): boolean {
  return status === "completed" || status === "failed";
}

/** Poll every 2 s, and give up after 5 minutes. */
export const POLL_INTERVAL_MS = 2_000;
export const POLL_DEADLINE_MS = 5 * 60 * 1_000;

/**
 * Milliseconds until the next `get_audit`, or `null` to stop.
 *
 * A fixed interval rather than backoff (Q2). The decide preferred backoff at
 * 0.57 — a near-tie — but audits of this server settle in under about ten
 * seconds, so backoff's advantage is theoretical while its extra state is real.
 * At 2 s a typical audit costs about five calls. The deadline exists so an
 * audit that never settles stops being polled rather than being polled forever.
 */
export function nextPollDelay(state: { status: string; elapsedMs: number }): number | null {
  if (isTerminal(state.status)) return null;
  if (state.elapsedMs >= POLL_DEADLINE_MS) return null;
  return POLL_INTERVAL_MS;
}

/**
 * Arguments for the refresh call, or `null` when they cannot be formed.
 *
 * `get_audit` needs both ids. Inventing either would be a fallback, so a
 * missing one yields no call at all.
 */
export function refreshArgs(
  toolInput: { serverId?: string } | undefined,
  toolOutput: { auditId?: string } | undefined,
): { serverId: string; auditId: string } | null {
  const serverId = toolInput?.serverId;
  const auditId = toolOutput?.auditId;
  if (!serverId || !auditId) return null;
  return { serverId, auditId };
}

/** Whether the API sent no checks at all, sent none, or sent some. */
export type ChecksState = "absent" | "empty" | "present";

export interface AuditSummary {
  checksState: ChecksState;
  errorMessage: string | null;
  isFailed: boolean;
  isSettled: boolean;
}

/**
 * The facts the view renders from, in one place.
 *
 * `absent` and `empty` stay distinct: "still running, nothing yet" and
 * "finished, found nothing" are different facts, and the spec omits `checks`
 * from its required list precisely so the first can be expressed.
 */
export function summarize(audit: {
  status: string;
  checks?: readonly ViewCheck[] | undefined;
  errorMessage?: string | null;
}): AuditSummary {
  const checksState: ChecksState =
    audit.checks === undefined ? "absent" : audit.checks.length === 0 ? "empty" : "present";

  return {
    checksState,
    errorMessage: audit.errorMessage ?? null,
    isFailed: audit.status === "failed",
    isSettled: isTerminal(audit.status),
  };
}

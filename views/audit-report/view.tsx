/**
 * audit-report — renders one Manufact readiness audit.
 *
 * Bound to `start_audit`. The tool returns an auditId immediately, so this view
 * shows a pending state from that alone and then refreshes itself by calling
 * `get_audit` until the audit settles. It never issues a second `start_audit`.
 *
 * Why the refresh is a separate call rather than a re-read: `useToolContext`
 * latches the first structured result for the view's lifetime and later
 * notifications cannot overwrite it, so the rendering invocation's result is
 * the *start* of the audit, permanently. Progress has to come from
 * `useCallTool("get_audit")`.
 *
 * This view makes no network request of its own — `get_audit` goes through the
 * host bridge — which is why it declares no CSP `connectDomains` entry.
 */
import { useCallTool, useToolContext } from "mcp-use/react";
import { useEffect, useRef, useState } from "react";

import {
  type AuditSummary,
  type ViewCheck,
  groupByCategory,
  isTerminal,
  nextPollDelay,
  readinessLabel,
  refreshArgs,
  summarize,
} from "./report.js";
import "./view.css";

/** The seven-field contract `get_audit` returns. */
interface AuditOutput {
  auditId: string;
  status: string;
  isReadyForChatgpt: boolean | null;
  isReadyForClaudeai: boolean | null;
  targetUrl: string;
  errorMessage: string | null;
  checks?: ViewCheck[];
}

function ReadinessBadge({ label, flag }: { label: string; flag: boolean | null }) {
  const state = readinessLabel(flag);
  return (
    <div className={`ar-badge ar-badge--${state.replace(/\s+/g, "-")}`}>
      <span className="ar-badge__label">{label}</span>
      <span className="ar-badge__value">{state}</span>
    </div>
  );
}

function CheckRow({ check }: { check: ViewCheck }) {
  return (
    <li className={`ar-check ar-check--${check.status}`}>
      <span className="ar-check__status">{check.status}</span>
      <span className="ar-check__name">{check.checkName}</span>
      <span className="ar-check__severity">{check.severity}</span>
      {check.message ? <p className="ar-check__message">{check.message}</p> : null}
      {/* `hint` is untyped in the spec — any JSON value or null. Stringify
          rather than assume, so a non-string hint cannot break the render. */}
      {check.hint === null || check.hint === undefined ? null : (
        <p className="ar-check__hint">
          {typeof check.hint === "string" ? check.hint : JSON.stringify(check.hint)}
        </p>
      )}
    </li>
  );
}

function Checks({ audit, summary }: { audit: AuditOutput; summary: AuditSummary }) {
  if (summary.checksState === "absent") {
    return <p className="ar-note">No checks yet — the audit is still running.</p>;
  }
  if (summary.checksState === "empty") {
    return <p className="ar-note">The audit finished and reported no checks.</p>;
  }

  // Groups and their order come from the data. A slug this code has never seen
  // renders under its own name, after the ones it knows.
  const groups = groupByCategory(audit.checks ?? []);
  return (
    <div className="ar-groups">
      {groups.map((group) => (
        <section key={group.category} className="ar-group">
          <h3 className="ar-group__title">{group.category}</h3>
          <ul className="ar-group__checks">
            {group.checks.map((check) => (
              <CheckRow key={check.id} check={check} />
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}

export default function AuditReport() {
  const view = useToolContext<"start_audit">();
  const getAudit = useCallTool("get_audit");

  const [audit, setAudit] = useState<AuditOutput | null>(null);
  const [pollError, setPollError] = useState<Error | null>(null);
  const [gaveUp, setGaveUp] = useState(false);
  const startedAt = useRef<number>(Date.now());

  // The latched rendering invocation. Read only when it is ready — a pending or
  // errored context has no toolOutput.
  const latched =
    view.status === "ready"
      ? (view.toolOutput as { auditId?: string; status?: string } | undefined)
      : undefined;

  // Built by the same function the locked test pins, rather than a second
  // inline copy of the rule — so T8 guards the path that actually runs.
  const args = refreshArgs(view.toolInput as { serverId?: string } | undefined, {
    auditId: audit?.auditId ?? latched?.auditId,
  });

  // start_audit already told us the status; use it rather than assuming pending.
  const status = audit?.status ?? latched?.status ?? "pending";
  const statusRef = useRef(status);
  statusRef.current = status;

  const serverId = args?.serverId;
  const auditId = args?.auditId;

  useEffect(() => {
    if (!serverId || !auditId) return;

    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    // Scheduling happens on completion, never at call time. Arming the next
    // timer before the current call returns lets a slow response overlap the
    // one after it, and an out-of-order arrival can then overwrite a settled
    // audit with a stale running one.
    const schedule = (current: string) => {
      const delay = nextPollDelay({
        status: current,
        elapsedMs: Date.now() - startedAt.current,
      });
      if (delay === null) {
        if (!isTerminal(current)) setGaveUp(true);
        return;
      }
      timer = setTimeout(poll, delay);
    };

    const poll = async () => {
      if (cancelled) return;
      try {
        const result = await getAudit.callTool({ serverId, auditId });
        if (cancelled) return;
        const next = result.structuredContent as AuditOutput;
        setAudit(next);
        setPollError(null);
        schedule(next.status);
      } catch (error) {
        if (cancelled) return;
        // Surfaced, not swallowed. Rendering continues to retry until the
        // deadline, because one failed read does not mean the audit is gone.
        setPollError(error instanceof Error ? error : new Error(String(error)));
        schedule(statusRef.current);
      }
    };

    schedule(statusRef.current);

    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
    // Only the ids drive the loop. The loop reschedules itself from its own
    // results, so status must not be a dependency or every tick would restart it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [serverId, auditId]);

  if (view.status === "error") {
    return (
      <div className="ar">
        <p className="ar-error">Could not start the audit: {view.error.message}</p>
      </div>
    );
  }

  // Refresh failures render above the pending branch. Placing this below it
  // made the banner unreachable whenever the *first* poll failed, so a broken
  // get_audit showed as a healthy running audit for the whole deadline.
  const refreshBanner = pollError ? (
    <p className="ar-error">Could not read the audit: {pollError.message}</p>
  ) : null;

  const gaveUpBanner = gaveUp ? (
    <p className="ar-note">
      Stopped checking after 5 minutes. The audit had not settled.
    </p>
  ) : null;

  if (!audit) {
    return (
      <div className="ar">
        <h2 className="ar-title">Readiness audit</h2>
        {refreshBanner}
        {gaveUpBanner}
        <p className="ar-note">
          {auditId ? `Audit ${auditId} is running…` : "Starting the audit…"}
        </p>
      </div>
    );
  }

  const summary = summarize(audit);

  return (
    <div className="ar">
      <h2 className="ar-title">Readiness audit</h2>
      <p className="ar-target">{audit.targetUrl}</p>

      <div className="ar-badges">
        <ReadinessBadge label="ChatGPT" flag={audit.isReadyForChatgpt} />
        <ReadinessBadge label="Claude.ai" flag={audit.isReadyForClaudeai} />
      </div>

      <p className={`ar-status ar-status--${audit.status}`}>
        {summary.isSettled ? audit.status : `${audit.status}…`}
      </p>

      {/* errorMessage is nullable and not gated on `failed`: the spec does not
          forbid the API populating it on a settled-but-not-failed audit. */}
      {summary.errorMessage ? <p className="ar-error">{summary.errorMessage}</p> : null}

      {refreshBanner}
      {gaveUpBanner}

      <Checks audit={audit} summary={summary} />
    </div>
  );
}

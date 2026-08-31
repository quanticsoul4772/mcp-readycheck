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
  nextPollDelay,
  readinessLabel,
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
  const startedAt = useRef<number>(Date.now());

  // The ids the refresh needs, off the latched rendering invocation.
  const serverId = (view.toolInput as { serverId?: string } | undefined)?.serverId;
  const auditId =
    audit?.auditId ??
    (view.status === "ready"
      ? (view.toolOutput as { auditId?: string } | undefined)?.auditId
      : undefined);

  const status = audit?.status ?? "pending";

  useEffect(() => {
    if (!serverId || !auditId) return;

    const delay = nextPollDelay({ status, elapsedMs: Date.now() - startedAt.current });
    if (delay === null) return; // settled, or past the deadline

    const timer = setTimeout(() => {
      void getAudit
        .callTool({ serverId, auditId })
        .then((result) => setAudit(result.structuredContent as AuditOutput))
        .catch(() => {
          // The handle keeps the error; the banner below reads it. Swallowing
          // it here would only stop the next tick from being scheduled.
        });
    }, delay);

    return () => clearTimeout(timer);
    // `getAudit.data` advances the effect after each completed call.
  }, [serverId, auditId, status, getAudit.data, getAudit.error]);

  if (view.status === "error") {
    return (
      <div className="ar">
        <p className="ar-error">Could not start the audit: {view.error.message}</p>
      </div>
    );
  }

  if (!audit) {
    return (
      <div className="ar">
        <h2 className="ar-title">Readiness audit</h2>
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

      {summary.isFailed && summary.errorMessage ? (
        <p className="ar-error">{summary.errorMessage}</p>
      ) : null}

      {getAudit.error ? (
        <p className="ar-error">Refresh failed: {getAudit.error.message}</p>
      ) : null}

      <Checks audit={audit} summary={summary} />
    </div>
  );
}

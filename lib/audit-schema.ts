// audit-schema.ts — zod schemas for the tools' structured output, and the
// mapper from the API's audit shape to it.
//
// Two rules govern everything in this file:
//
//   1. `category`, `severity` and `scope` are unconstrained strings in the
//      OpenAPI document — no enum, no example, no documented value list. They
//      are never enumerated, defaulted or coerced here. Whatever the API sends
//      is what a caller receives, including a value this code has never seen.
//
//   2. `hint` and `details` are `anyOf: [{}, null]` — any JSON value or null,
//      not strings. Narrowing them to `string` would turn a valid API response
//      into a tool failure, because mcp-use validates structuredContent
//      against outputSchema at runtime.

import { z } from "zod";

import type { RawAudit, RawCheck } from "#lib/manufact";

/**
 * The audit lifecycle, which the spec does enumerate.
 *
 * This vocabulary is the audit's alone. A deployment settles at `running`;
 * here `running` means still in progress and `completed` is terminal. No
 * terminal-state check is ever shared between the two.
 */
export const auditStatusSchema = z.enum(["pending", "running", "completed", "failed"]);

/** The non-terminal audit states. `start_audit` returns one of these. */
export const NON_TERMINAL_AUDIT_STATUSES = ["pending", "running"] as const;

export const checkSchema = z.object({
  id: z.string().describe("Unique id of this check result"),
  checkId: z.string().describe("Stable identifier of the check that ran"),
  checkName: z.string().describe("Human-readable name of the check"),
  status: z.string().describe("Check outcome, e.g. pass, fail, skip or pending"),
  severity: z
    .string()
    .describe("Severity as the API reports it — an open vocabulary, not an enum"),
  category: z
    .string()
    .describe("Category as the API reports it — an open vocabulary, not an enum"),
  scope: z.string().describe("Scope as the API reports it — an open vocabulary, not an enum"),
  platforms: z.array(z.string()).describe("Platforms this check applies to"),
  message: z.string().nullable().describe("Failure message, when the API supplies one"),
  details: z
    .unknown()
    .describe("Untyped in the spec: any JSON value, or null. Never assume a string"),
  hint: z
    .unknown()
    .describe("Untyped in the spec: any JSON value, or null. Never assume a string"),
  durationMs: z.number().nullable().describe("How long the check took, in milliseconds"),
});

export const auditOutputSchema = z.object({
  auditId: z.string().describe("The audit's id, for a later get_audit call"),
  status: auditStatusSchema.describe(
    "pending or running means still in progress; completed and failed are terminal",
  ),
  isReadyForChatgpt: z
    .boolean()
    .nullable()
    .describe("Whether the audit judged the server ready for ChatGPT; null until decided"),
  isReadyForClaudeai: z
    .boolean()
    .nullable()
    .describe("Whether the audit judged the server ready for Claude.ai; null until decided"),
  targetUrl: z
    .string()
    .describe("The endpoint the audit ran against — server-derived, never an input"),
  errorMessage: z
    .string()
    .nullable()
    .describe(
      "Why the audit failed, when it did. Null otherwise. Without this a failed " +
        "audit reports only that it failed, and the cause the API supplied is lost",
    ),
  checks: z
    .array(checkSchema)
    .optional()
    .describe(
      "Absent while the audit has produced no checks yet — the spec omits it from the " +
        "required list. Absent and empty mean different things and are kept different",
    ),
});

export const startAuditOutputSchema = z.object({
  auditId: z.string().describe("The created audit's id"),
  status: auditStatusSchema.describe("The audit's state at creation — pending or running"),
});

export type AuditOutput = z.infer<typeof auditOutputSchema>;

/** Maps one API check to the output shape, preserving every open-vocabulary value verbatim. */
function mapCheck(check: RawCheck) {
  return {
    id: check.id,
    checkId: check.checkId,
    checkName: check.checkName,
    status: check.status,
    severity: check.severity,
    category: check.category,
    scope: check.scope,
    platforms: check.platforms,
    message: check.message,
    details: check.details,
    hint: check.hint,
    durationMs: check.durationMs,
  };
}

/**
 * Maps an audit-detail response to `structuredContent`.
 *
 * `checks` is passed through only when the API sent it. Substituting an empty
 * array would collapse "still running, nothing yet" into "finished, found
 * nothing", which are different facts.
 */
export function mapAuditResponse(audit: RawAudit): AuditOutput {
  return {
    auditId: audit.id,
    status: auditStatusSchema.parse(audit.status),
    isReadyForChatgpt: audit.isReadyForChatgpt,
    isReadyForClaudeai: audit.isReadyForClaudeai,
    targetUrl: audit.targetUrl,
    errorMessage: audit.errorMessage,
    ...(audit.checks === undefined ? {} : { checks: audit.checks.map(mapCheck) }),
  };
}

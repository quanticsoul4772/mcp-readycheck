# Plan: audit-report view (G2)

Written by the orchestrator, approved by the human at **Gate A**. Nothing
executes before that approval.

Every SDK claim below was read from the installed `mcp-use@2.3.3` type
declarations under `node_modules/`, not from memory. Claims that did not
survive are marked **refuted** and do not enter.

---

## Uncertainty protocol

Two questions are **blocking**. The rest are stated and carried.

### Q1 — BLOCKING. This PR is not exempt from the verdict check.

S0 narrowed the `[plan]`/`[docs]` exemption to Markdown under `docs/` plus the
root README, because treating every `.md` as inert let `AGENTS.md` and
`.claude/agents/*.md` — standing instructions to agents — merge unevaluated.
This PR carries `tests/audit-report-view.test.ts`, which is executable.

So the `[plan]` prefix will **not** exempt it, and `verdict` is now a required
check with `bypass_actors: []`. This PR needs an evaluator verdict in its body
naming its head commit, exactly like an implementation PR.

That is the rule working as intended rather than a defect, but it changes the
Gate A ritual: the plan PR is now evaluated too. Confirm that is what you want,
or say the tests should land in the implementation PR instead — in which case
"Default-FAIL tests that fail against main" moves to S3 and Gate A approves the
plan document alone.

### Q2 — BLOCKING. Polling cadence has low confidence.

> **decide — recommended: exponential backoff from ~1 s, capped ~10 s, stopping
> on terminal status or a deadline (88). Runner-up: fixed 2 s interval (74).
> Confidence 0.57.**

0.57 is a coin-flip dressed as a preference, and the two differ in observable
behaviour: backoff is snappier on the common fast case and gentler on a stuck
one, but it is more code and more to get wrong in a `useEffect`. Measured
evidence: the audits this server has run settled in **under ~10 s** with 32
checks. At that duration a fixed 2 s interval costs at most about five calls
and is trivially correct.

**Recommendation: the fixed 2 s interval,** against the decide's ranking, on
the grounds that the measured settle time makes backoff's advantage
theoretical while its complexity is real. Your call.

### Q3 — carried. Rendering is not covered by the test suite.

`node:test` cannot mount React without a DOM, and adding a testing library
would trip never-relax lock 4. The tests therefore cover the **pure transforms**
(D1) and AC7 covers the rendering, by eye, in the Inspector against a live
audit. Stated so the coverage claim is not read as stronger than it is.

### Q4 — carried. `checks` absent vs empty is preserved but barely observable.

The contract keeps `checks: undefined` distinct from `checks: []`. The view
renders "no checks yet" for the first and "no checks found" for the second;
only AC7 can confirm the wording is right.

---

## Verified SDK facts

| Fact | Source |
|---|---|
| `useToolContext()` returns `pending \| ready \| error`; `toolInput` is progressive while pending; the first structured success or tool error **latches for the view's lifetime** and later notifications cannot overwrite it | `react/hooks/use-tool-context.d.ts` |
| `useCallTool(name)` returns `{ callTool, data, error, isPending }`; `callTool` **rejects** on `isError: true` and on transport failure; `data` holds the last success only | `react/hooks/use-call-tool.d.ts` |
| `useCallTool` requires the tool be exported from the server entry — otherwise the type resolves to an error string. `getAudit` is already exported | `react/hooks/use-call-tool.d.ts` |
| A view is one directory under `views/<name>/`, primed into a `ViewsManifest` keyed by directory name at build/dev | `views/types.d.ts` |
| Binding a view absent from the primed registry **throws at mount** — not at build or typecheck | `#validateViewBindingsAtMount`, STAGE-PLAN correction 11 |
| `csp.connectDomains` maps to CSP `connect-src` — fetch/XHR/WebSocket origins. Omitted → no network connections | `ext-apps/spec.types.d.ts` |
| The framework **already appends the server origin** to `connectDomains` and the assets origin to `resourceDomains` at emission | `views/types.d.ts` |

**Refuted: that this view needs a `connectDomains` entry for the Manufact API.**
It does not, and adding one would be wrong. The view calls `get_audit` through
the host bridge; the *server* contacts `cloud.manufact.com`. The view makes no
network request of its own, so it declares **no `csp` block at all** — the
framework's automatic server-origin entry is sufficient and the secure default
(no connections) is correct.

## Goal

`start_audit` renders a view. It shows a pending state immediately from the
`auditId` it already has, calls `get_audit` on a timer until the audit reaches a
terminal status, then shows the checks grouped by category with both readiness
badges. No second `start_audit` is ever issued.

Done means AC1–7 demonstrated, the view live at the deployed endpoint, and G3
handed a concrete 32-check worklist.

## Design decisions

**D1 — pure logic in `views/audit-report/report.ts`** (0.66; runner-up `lib/`,
−32). Imported by both `view.tsx` and the tests, so the transforms are testable
under `node:test` with no new dependency. Keeping it in `view.tsx` scored 28 —
it would need a render shim, and the shim is the dependency the lock forbids.

**D2 — polling cadence.** Unresolved; see Q2.

**D3 — category display order: a lookup with raw fallback.** A `CATEGORY_ORDER`
map gives known slugs a position; anything absent sorts after them,
alphabetically, and renders under its **raw slug**. No slug is ever renamed,
dropped or defaulted — STAGE-PLAN correction 3, and the one that has already
been proved right once: the live values are four slugs, not the six documented
prose names.

**D4 — no `csp` block.** See the refuted claim above.

**D5 — one change for all three edits.** The view directory, the
`view: { name: "audit-report" }` binding on `start_audit`, and restoring
`visibility: "app"` on `get_audit` land together — correction 12. Binding
before the directory exists throws at mount; restoring app-visibility before
the view exists makes `get_audit` unreachable by the model with nothing to call
it. Neither is catchable by CI.

## Acceptance criteria

Default-FAIL: `views/audit-report/` does not exist, `start_audit` has no `view`,
and `get_audit` has no `visibility`.

1. **Given** `start_audit` returns, **when** the host renders the view, **then**
   a pending state appears and results replace it, with no second `start_audit`.
2. **Given** checks with a category the code has never seen, **when** grouped,
   **then** the group appears under its raw slug and display order comes from a
   lookup with a raw fallback.
3. **Given** a non-terminal audit, **when** the view refreshes, **then** it calls
   `get_audit` with `serverId` and `auditId` taken from `toolInput`/`toolOutput`,
   and stops once the status is terminal.
4. **Given** `isReadyForChatgpt`/`isReadyForClaudeai`, **when** either is `null`,
   **then** the badge reads "unknown" — never "false".
5. **Given** the deployed server, **when** `tools/list` is read, **then**
   `get_audit` carries `_meta.ui.visibility: ["app"]`, the model-facing list
   excludes it, and the view still calls it.
6. **Given** an audit that failed, **when** rendered, **then** `errorMessage` is
   shown.
7. **Given** the deployed endpoint, **when** the view is opened in the Inspector
   against a live audit, **then** it renders.

## Test list — frozen at Gate A

`tests/audit-report-view.test.ts`, run with `node --test`. Ten tests over the
pure transforms in `views/audit-report/report.ts`.

| # | Test | AC |
|---|---|---|
| T1 | `groupByCategory` returns one group per distinct category | AC2 |
| T2 | an unknown slug is preserved verbatim as its group key | AC2 |
| T3 | known categories sort by the lookup, unknown ones after, alphabetically | AC2 |
| T4 | every check in the input appears in exactly one group | AC2 |
| T5 | `readinessLabel(true/false/null)` → `ready` / `not ready` / `unknown` | AC4 |
| T6 | `isTerminal` is true for `completed` and `failed`, false for `pending` and `running` | AC3 |
| T7 | `nextPollDelay` stops at the deadline and returns null once terminal | AC3 |
| T8 | `refreshArgs` builds `{serverId, auditId}` from `toolInput`/`toolOutput` | AC3 |
| T9 | absent `checks` and empty `checks` produce distinguishable states | AC2 |
| T10 | a `failed` audit surfaces `errorMessage` through `summarize` | AC6 |

AC1, AC5 and AC7 are not unit-testable: they are properties of the host, the
wire and the browser. AC5 is demonstrated by reading `tools/list` from the
deployed endpoint; AC1 and AC7 in the Inspector at S5.

## Files to touch

| Path | Why |
|---|---|
| `views/audit-report/view.tsx` | the component; one view per directory |
| `views/audit-report/report.ts` | the pure transforms (D1) |
| `views/audit-report/view.css` | styling, matching the `my-view` convention |
| `index.ts` | the `view:` binding on `start_audit` and `visibility` on `get_audit` |
| `tests/audit-report-view.test.ts` | the ten locked tests |

Nothing else. `mcp-env.d.ts` regenerates on typecheck and is not hand-edited.

## Symbol anchors

`groupByCategory`, `categoryRank`, `readinessLabel`, `isTerminal`,
`nextPollDelay`, `refreshArgs`, `summarize` in `report.ts`; `AuditReport` in
`view.tsx`; `startAudit`, `getAudit` in `index.ts`. Never line numbers.

## Invariants

- No category, severity or scope value is enumerated, renamed or defaulted.
- `checks: undefined` never becomes `[]`.
- `null` readiness renders "unknown", never "false".
- The view makes no network request; it calls `get_audit` through the host.
- Exactly one `start_audit` per view lifetime.
- Polling stops at a terminal status and at the deadline.
- The three edits of D5 ship together or not at all.
- Nothing under `.claude/` changes.

## Out of scope

Fixing anything the audit reports (G3). Demo assets (G4). CSP beyond the
framework's own defaults. Any file the table above does not list.

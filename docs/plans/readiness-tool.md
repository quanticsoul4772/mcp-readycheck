# Plan: readiness tool (G1)

Written by the orchestrator, approved by the human at **Gate A**. Nothing
executes before that approval.

Every factual claim below carries how it was established. Claims marked
**refuted** were checked and did not survive; per the goal's protocol they do
not enter the plan as fact, and where the goal text asserted one, the
correction is raised as a question rather than silently applied.

---

## Uncertainty protocol

Three questions are **blocking** — each changes the shape of the work, and two
of them contradict the goal text, so they cannot be resolved by assumption.
The rest are stated and carried forward.

### Q1 — BLOCKING. `get_audit` cannot take `auditId` alone.

The goal specifies `get_audit(auditId)`. The API has no endpoint that retrieves
an audit by `auditId` alone.

> **verify — refuted (execution, confidence: certain).** Parsing the live spec:
> `GET /api/v1/server-audits/{serverId}/audits/{auditId}` declares two path
> parameters, `serverId` and `auditId`, both `required: true`. The audits *list*
> endpoint is likewise keyed by `serverId`. No `auditId`-only route exists among
> the 235 paths.

`serverId` cannot be carried over from the `start_audit` call: AGENTS.md states
the runtime is stateless, registrations replay into a fresh SDK server per
request, and identity must be request-scoped or in an external store.

> **decide — recommended: `get_audit(auditId)` with `serverId` as a module
> constant. Runner-up: `serverId` from a new env var (scored 33 lower).
> Confidence 0.665.** Reasoning: matches the goal signature, needs no
> cross-call state and no new pipeline variable, and this app exists to audit
> its own deployment.

**Why this is a question and not a decision.** The confidence is moderate, and
the recommended option creates an asymmetry the decide record did not weigh:
`start_audit` takes `serverId` as an argument while `get_audit` would ignore it
and use a constant. A caller who starts an audit for server X and then reads it
back gets a 404 against server Y, and AC4 would render that as an ordinary "not
found" — a correct-looking error for a wrong-parameter bug. Options:

- **(a)** `get_audit(auditId, serverId)` — both explicit. Departs from the goal
  signature; removes the mismatch entirely.
- **(b)** `get_audit(auditId)` + module constant — the decide recommendation.
  Keeps the goal signature; leaves the mismatch. Would be consistent if
  `start_audit` also dropped its `serverId` argument.
- **(c)** `get_audit(auditId, serverId)` and `start_audit(serverId)` — symmetric
  and explicit, at the cost of the goal's stated signature.

**Recommendation: (c).** It is the only option under which the two tools agree
about what a server id is. Needs your call.

### Q2 — BLOCKING. `visibility: ["app"]` is not the SDK's type.

> **verify — refuted (read of installed types, confidence: certain).**
> `node_modules/mcp-use/dist/tools.d.ts` declares
> `visibility?: "model" | "app"` — a string union, not an array. The array form
> is the *wire* encoding only: `views/wire.d.ts` documents that the framework
> "emits `ui.visibility: [visibility]`" from the singular field.

Writing `visibility: ["app"]` is a type error. The plan uses
`visibility: "app"`, which produces the array the goal describes on the wire.
Confirm this reading of the goal's intent.

### Q3 — BLOCKING. There is no 60-second host ceiling.

The goal's OUTCOME requires "no single call over the 60s host ceiling".

> **verify — refuted (3 passes, confidence 1.0).** The MCP specification sets no
> numeric per-call limit; it says implementations SHOULD establish configurable
> per-request timeouts and MAY reset them on progress notifications. The 60 000
> ms figure is `DEFAULT_REQUEST_TIMEOUT_MSEC` in the TypeScript SDK — an
> overridable per-request default. Other implementations differ: the Python
> SDK's `read_timeout_seconds` defaults to no timeout. Claude Code exposes
> `MCP_TIMEOUT` / `MCP_TOOL_TIMEOUT`. Hosted platforms apply their own request
> duration limits, which are the binding constraint, not an MCP host ceiling.

The same verification called the *design* — start plus single-read rather than a
blocking poll — sound. So the split survives; only its stated justification
changes. The plan therefore rests the split on three grounds that did survive:

1. The TypeScript SDK's 60 s default is what an unconfigured host most likely
   applies, so a blocking poll is a real risk even though it is not a ceiling.
2. The deployment platform's own request-duration limit binds regardless.
3. STAGE-PLAN.md correction 5, which is binding above the spec: a single
   polling tool "holds a request open for the whole audit and gives the widget
   nothing to render until it finishes", and makes the timeout case
   unrenderable.

Confirm the OUTCOME's wording is amended, or tell me to keep it as written.

### Q4 — carried. Binding a view name whose directory does not exist.

The goal says bind `view: { name: ... }` now and build nothing else; AGENTS.md
says the directory name must match. Reading the SDK's `views/*.d.ts` did not
settle whether a missing directory fails the build.

> **decide — recommended: declare the binding now with no directory, *after*
> empirically confirming build and typecheck pass. Runner-up: create a minimal
> placeholder directory (scored 23 lower). Confidence 0.615.**

Not blocking because it is empirically settleable in one command during Stage 3.
Step 0 of the TDD sequence is that experiment. If build or typecheck fails, the
binding is deferred to G2 and this plan is amended — the view name is recorded
here either way as `audit-report`.

### Q5 — carried. Real `category` and `severity` values are still unknown.

STAGE-PLAN.md open questions 1 and 2 remain open. A live authenticated
`GET /api/v1/server-audits/{serverId}/audits?limit=5` returned
`{"items":[],"total":0}` — **this server has never been audited**, so no real
category value exists to read. Resolving it requires creating an audit, which is
a write and out of scope for a plan-only stage.

This does not change the shape of the work: the design derives groupings from
the response, so the values are data, never code. AC2 and AC3 are written to
hold for any value.

### Q6 — carried. `runE2E` behaviour on the Free tier is untested.

STAGE-PLAN.md open question 4. `runE2E` is an optional boolean on the POST body.
The plan does not send it, so the question stays open and unexercised.

### Q7 — carried. The POST returns `id`, not `auditId`.

> **verify — supported (execution).** `POST .../audits` → 201
> `{ id: string, status: enum }`, both required. The nested `checks[]` items
> carry their own `id` *and* an `auditId`.

`start_audit` renames `id` to `auditId` in its output. Stated so the rename is
not mistaken later for a field the API actually returns.

### Q8 — carried. AC6 needs a way to observe "no request was sent".

The key check runs before any `fetch`, so the assertion is that zero requests
were issued. The test wraps `globalThis.fetch` with a counter for the duration
of the call. This counts requests; it does not stub a response, so it is not a
mock standing in for a lifecycle.

---

## Goal

`mcp-readycheck` gains the two tools that let it run Manufact's publishing
checks against its own deployment and read the result back. `start_audit`
resolves the server's active deployment, creates an audit and returns its id
immediately. `get_audit` reads one audit's current state, preserving whatever
category values the API returns rather than mapping them onto a fixed list.

Done means: both tools are registered, the six acceptance criteria below are
each positively demonstrated against the real API, and the widget that G2 will
build has a typed `structuredContent` contract to render — with no design
choice left unrecorded.

## Verified contract facts

Established by parsing the live spec at `https://manufact.com/openapi.json`
(792 456 bytes, `openapi: 3.1.0`, `Manufact Cloud API` v1.0.0, server
`https://cloud.manufact.com`) with a script, not by reading prose. Each is
**supported by execution** unless noted.

| Fact | Detail |
|---|---|
| Audit create | `POST /api/v1/server-audits/{serverId}/audits`; body optional `deploymentId` (uuid), `runE2E` (bool), `branch` (string\|null); **no required array**, so `{}` is valid |
| Create response | `201 { id, status }`, both required |
| Audit read | `GET /api/v1/server-audits/{serverId}/audits/{auditId}` — **both** ids required |
| Audit `status` | **has an enum**: `pending`, `running`, `completed`, `failed` |
| Check `status` | separate enum: `pass`, `fail`, `skip`, `pending` |
| `category`, `severity`, `scope` | plain `type: string`, **no enum** — confirms AGENTS.md |
| `hint`, `details` | `anyOf: [{}, null]` — any JSON value or null, **not** strings |
| `checks` | **absent from the 14-entry `required` list** — legitimately omissible. Answers STAGE-PLAN.md open question 3 |
| Errors | `400` (`code: "VALIDATION_ERROR"`), `401`, `403`, `404`, each `{ error: string }` |
| Server read | `GET /api/v1/servers/{id}` → `activeDeploymentId` (string\|null, required), `mcpUrl` (required) |
| Auth | `bearerAuth` (HTTP bearer). Spec declares no global or per-operation `security`; established **empirically**: bearer → `200`, unauthenticated → `401` |

Live values read during planning (read-only GET, no audit created):
`activeDeploymentId = c453caba-5a9b-428e-94f8-b4fe35ffbe2d`,
`mcpUrl = https://mcp-readycheck.run.mcp-use.com/mcp`, `status = running`
(a deployment settling at `running` — the vocabulary that must never be shared
with an audit's `running`).

## Design decisions

Every choice below carries a decide record. A choice without one is a defect the
evaluator must BLOCK on.

**D1 — `get_audit` parameter shape.** Unresolved; see Q1. Recommended (c),
against the decide's (b), for the stated reason. **Gate A must settle this.**

**D2 — resolve `deploymentId` explicitly.** *Recommended:* GET the server
record, then POST `deploymentId` explicitly; fail closed when it is `null`.
*Runner-up:* omit `deploymentId` and let the API bind (scored 52 lower).
*Confidence 0.64.* The extra round trip is affordable — see the check below —
and omitting it would let the API silently choose the binding.

**D3 — `hint` and `details` typing.** *Recommended:* `z.unknown().nullable()`,
matching `anyOf: [{}, null]` exactly. *Runner-up:* omit both from the schema
(scored 47 lower). *Confidence 0.735.* Narrowing to `string` is the exact
mistake AGENTS.md already records; because mcp-use validates `structuredContent`
against `outputSchema` at runtime, an over-narrow schema converts a valid API
response into a tool failure.

**D4 — view binding.** Conditional; see Q4. *Confidence 0.615.*

**D5 — absent `checks`.** *Recommended:* mirror the API — emit `checks` only
when present, declare it optional. *Runner-up:* substitute `[]` (scored 63
lower). *Confidence 0.815.* Substituting an empty array collapses "still
running, no checks yet" into "finished, found nothing", destroying the
distinction G2's widget needs.

**D6 — test runner.** *Recommended:* `node:test` via `node --test`, built into
Node 22. *Runner-up:* vitest as a devDependency (scored 46 lower).
*Confidence 0.73.* Adding vitest would trip never-relax lock 4 and block TDD on
a dependency approval; `node:test` adds nothing to install.

> **check — supported (arithmetic).** `start_audit` issues two sequential
> requests. At ≤ 2000 ms each, total network time ≤ 4000 ms < 10 000 ms (AC1)
> and < 60 000 ms (the SDK default). Formal form:
> `(2000 + 2000 <= 4000) && (4000 < 10000) && (4000 < 60000)` → true.

## Acceptance criteria

Default-FAIL: every one is false against today's `index.ts`, which registers
only `show-app` and `say-hello`.

1. **Given** a valid `serverId`, **when** `start_audit` runs, **then** it
   returns an `auditId` and a status in `{pending, running}` in under 10 s, and
   a subsequent GET on that `auditId` returns a real audit.
2. **Given** an `auditId` for a completed audit, **when** `get_audit` runs,
   **then** `structuredContent` validates against `outputSchema` and `checks[]`
   contains every `category` string present in the raw API response.
3. **Given** a `category` value the code has never seen, **when** the response
   is mapped, **then** it validates and the value is preserved — not dropped,
   not coerced, not defaulted.
4. **Given** an invalid `serverId` or `auditId`, **when** either tool runs,
   **then** the failure surfaces as `isError: true` with a model-readable
   message, with no retry, no fallback and nothing swallowed.
5. **Given** the deployed endpoint and this server's own `serverId`
   (`a9f68f45-7160-4b30-8855-06399bd6aebb`), **when** an audit is created,
   **then** the audit's `targetUrl` equals `MCP_URL` + `/mcp`.
6. **Given** `MANUFACT_API_KEY` is absent, **when** either tool runs, **then**
   it fails closed with a clear message and issues zero HTTP requests.

## Test list — frozen at Gate A

This is the list `.tests-locked` freezes. Twelve tests in
`tests/readiness-tool.test.ts`, run with `node --test`.

| # | Test | AC |
|---|---|---|
| T1 | `start_audit` on the real `serverId` returns `{auditId, status}` with status in `{pending, running}` | AC1 |
| T2 | the `auditId` from T1 fetched back via the API returns `200` with a matching `id` | AC1 |
| T3 | `start_audit` returns in under 10 000 ms | AC1 |
| T4 | `get_audit`'s `structuredContent` parses against `outputSchema` | AC2 |
| T5 | the multiset of `category` values in the output equals that of the raw response | AC2 |
| T6 | mapping a payload whose `category` is `"totally-unheard-of-category"` validates and round-trips the value unchanged | AC3 |
| T7 | `start_audit` with a well-formed but nonexistent `serverId` returns `isError` with a message | AC4 |
| T8 | `get_audit` with a nonexistent `auditId` returns `isError` with a message | AC4 |
| T9 | a failing call issues exactly one HTTP request — no retry | AC4 |
| T10 | the created audit's `targetUrl` equals `MCP_URL + "/mcp"` and the server record's `mcpUrl` | AC5 |
| T11 | with the key unset, `start_audit` errors and issues zero HTTP requests | AC6 |
| T12 | with the key unset, `get_audit` errors and issues zero HTTP requests | AC6 |

> **check — supported (arithmetic).** Coverage per criterion is
> `(3,2,1,3,1,2) >= 1` for AC1..AC6 respectively; every criterion has at least
> one test and none is uncovered.

T1, T2, T4, T5 and T10 exercise the real API — the smallest real lifecycle that
proves the change, as AGENTS.md requires. T6 tests the pure mapping function on
a crafted input; it is not a mock standing in for a lifecycle, because the
lifecycle is already covered by the live tests.

## Phased TDD steps

0. **Experiment, not a test.** Add a view binding for a directory that does not
   exist; run `npm run typecheck` and `npm run build`. Record the result. This
   settles Q4 before any code depends on the answer.
1. T11, T12 first — the key guard, before any network path exists. Add
   `requireApiKey()`.
2. T7, T8, T9 — the error path. Add the fetch wrapper that raises on non-2xx
   and never retries.
3. T1, T2, T3 — `start_audit`: resolve, POST, return.
4. T6 — the pure mapper, with the unknown category.
5. T4, T5 — `get_audit` against a real completed audit.
6. T10 — `targetUrl` against the live `MCP_URL`.

## Files to touch

| Path | Why |
|---|---|
| `index.ts` | registers both tools; the only place `server.tool` is called |
| `lib/manufact.ts` | new: the API client — key guard, bearer header, non-retrying fetch |
| `lib/audit-schema.ts` | new: zod input/output schemas and the response mapper |
| `tests/readiness-tool.test.ts` | new: the twelve locked tests |
| `package.json` | a `test` script only — `node --test`; no new dependency |
| `AGENTS.md` | the `test` row currently reads "no suite yet" |

Nothing else. Anything outside this list is scope creep needing a new plan.

## Symbol anchors

`startAudit`, `getAudit` (the exported `ToolRef`s from `server.tool`);
`requireApiKey`, `manufactFetch`, `resolveActiveDeploymentId`, `createAudit`,
`fetchAudit` in `lib/manufact.ts`; `auditOutputSchema`, `checkSchema`,
`mapAuditResponse` in `lib/audit-schema.ts`. Never line numbers.

## Invariants

- `MANUFACT_API_KEY` is read from `process.env` only, never logged, never in
  tool output, never in an error message.
- Audit `status` and deployment `status` never share a terminal-state check.
- No `category`, `severity` or `scope` value is ever hardcoded, enumerated or
  defaulted in a schema.
- Every failure surfaces; no retry, no fallback, no `catch` that returns a
  success shape.
- `outputSchema` and returned `structuredContent` stay in lockstep.
- Nothing under `.claude/` changes — the guard layer is frozen.

## Out of scope

The view and widget, and CSP configuration (G2). Making the self-audit green
(G3). `runE2E`, autofix, the submission pack. Any change under `.claude/`.
Anything the files-to-touch table does not list.

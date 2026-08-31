# Plan: self-audit green (G3)

Written by the orchestrator, approved by the human at **Gate A** — which here is
the merge of this PR, since this PR carries `.tests-locked`.

Every framework claim below was **proved by execution** against the installed
`mcp-use@2.3.3`. Two of the audit's own hints name fields this SDK does not
have; following them literally would have produced two wrong fixes.

---

## Uncertainty protocol

### Q1 — BLOCKING. There are five failures, not seven.

The goal names "the seven named failures". The live baseline `523f56dc` tallies
`{"pass":27,"fail":5}` — 5 of 32 checks with `status !== "pass"`.

The "seven" traces to my own PROGRESS.md wording: *"5 tools return raw errors"*
and *"2 tools missing metadata"* are **tool counts inside two checks**, and read
as seven if added. **AC1 as written cannot be satisfied.** This plan targets the
five. Confirm at Gate A, or name the other two.

### Q2 — BLOCKING. `fuzz-edge-case-handling` states no criterion.

The goal's AC4 requires "the audit's stated criterion (quoted in the plan)". That
check's `hint` is **`null`**. There is nothing to quote. The criterion in fix 2
is *derived* from the two error strings the deployed server actually returns. It
is labelled derived rather than dressed up as a citation.

### Q3 — carried. "5 tool(s)" exceeds the number of tools.

`fuzz-edge-case-handling` reports `"5 tool(s) return raw/technical errors"`; the
server has **four** tools. Either the audit counts probe cases, or it counts
something absent from `tools/list`. Unexplained. Recorded so that at S5 a count
of "0 tool(s)" is read as success and **any other number is investigated, not
assumed to be progress**.

### Q4 — carried. The audit does not name which tool trips `tool-hints-present`.

It reports `"1 behavior annotation issue(s) found"` with no tool name. Deployed:

| tool | readOnlyHint | destructiveHint | openWorldHint |
|---|---|---|---|
| `show-app` | true | false | false |
| `say-hello` | true | false | false |
| `start_audit` | false | false | true |
| `get_audit` | **true** | false | **true** |

Against the hint's own wording — *"openWorldHint is true for writes that change
publicly visible internet state or send/submit to third parties, and false for
closed/private workflows"* — the only inconsistent row is `get_audit`: read-only,
writes nothing, yet open-world. That is the hypothesis fix 1 acts on. If the
count is still 1 at S5, the hypothesis was wrong and the tool is another one.

### Q5 — carried. `_meta.ui.widgetDescription` cannot be emitted by this SDK.

`buildResourceUiMeta` in `mcp-use/dist` emits exactly four keys under
`_meta.ui`: `csp`, `permissions`, `domain`, `prefersBorder`. The resource's
`description` comes from `view.description` and is already set on both views.
There is **no code path** in 2.3.3 that emits `widgetDescription`, and
`widgetMetadata` — the field the audit's hint recommends "for mcp-use servers" —
appears nowhere in the package.

So fix 4's only actionable missing field is the one fix 5 names: `domain`. The
plan treats checks 4 and 5 as **one root cause**, which their identical count of
2 (the two view resources) supports. If `tool-resource-metadata-complete` still
fails at S5 after `domain` is set, the remainder is an SDK gap, not a repo
defect, and it is recorded as a residual — not worked around.

---

## Verified framework facts

| Claim | Verdict | How |
|---|---|---|
| `_meta` on `server.tool` reaches `tools/list` verbatim | **supported** | Built an in-process `MCPServer`, drove a real `initialize` + `tools/list`; both vendor keys (`openai/toolInvocation`, `vendor/custom`) survived intact |
| `ToolViewConfig.domain` exists and emits `_meta.ui.domain` | **supported** | `tools.d.ts` — *"Dedicated origin hint … → resource `_meta.ui.domain`"*; emitted by `buildResourceUiMeta` |
| `widgetMetadata` is where an mcp-use widget description goes | **REFUTED** | The identifier appears in no file of `mcp-use@2.3.3` or `@modelcontextprotocol/*`. The audit's hint names a field this stack does not have |
| `openai/toolInvocation` is a typed SDK field | **REFUTED** | Also absent. It is a vendor key carried through `_meta` — which is why the passthrough proof above is what licenses fix 3 |
| Neither view resource declares a domain | **supported** | `resources/list` on the deployed server: both carry `_meta.ui.csp` and `prefersBorder`; neither carries `domain` |
| Validation errors are emitted before any handler runs | **supported** | `{"serverId":""}` returns `"Input validation error: Invalid arguments for tool start_audit: serverId: Too small: expected string to have >=1 characters"` — Zod's default text, from mcp-use's own layer |

The last row bounds fix 2: the wrapper `"Input validation error: Invalid
arguments for tool start_audit: "` is framework-owned and **not** removable from
this repo. Only the text after the field name is ours. If the fuzz check objects
to the wrapper itself, that too is an SDK gap, recorded as a residual.

## Goal

The app's audit of its own deployment reports `isReadyForChatgpt: true` and
`isReadyForClaudeai: true`. Done means a fresh live audit shows the five failing
checks passing, no previously-passing check regressed, and the bound view renders
both badges green.

## The five failures, and the fix for each

### 1. `tool-hints-present` — severity `error`, `["chatgpt"]`

> message: `"1 behavior annotation issue(s) found"`
> hint: *"On each tool, declare all three booleans accurately. readOnlyHint is
> true only when no state changes; openWorldHint is true for writes that change
> publicly visible internet state or send/submit to third parties, and false for
> closed/private workflows; destructiveHint is true for irreversible side
> effects, including messages and transactions that cannot be undone."*

**Fix:** `get_audit` → `openWorldHint: false`. It reads; it changes nothing and
submits to nobody. `start_audit` keeps `readOnlyHint: false` / `openWorldHint:
true` — it POSTs and creates a persistent record on an external service. See Q4:
the tool is inferred, not named by the audit.

### 2. `fuzz-edge-case-handling` — severity `warning`, `[]`

> message: `"5 tool(s) return raw/technical errors on bad inputs"`
> hint: **`null`**

**Derived criterion** (Q2): an error is raw when it hands the caller an internal
identifier they cannot act on — an API path, an HTTP status code, or a schema
constraint name — instead of what to do. Both observed strings do:

```
Manufact API returned 404 for /api/v1/servers/not-a-uuid: Server not found
Input validation error: … serverId: Too small: expected string to have >=1 characters
```

**Fix (decide D2, 0.82):** custom `.min(1, "…")` messages on every schema
constraint, **and** a `humanError` mapper that rewrites thrown API failures into
a sentence naming the tool and the remedy, with no path and no status code. The
runner-up — rewriting handler errors only — scored 64 lower because it cannot
reach the pre-handler text at all, and that is the worse of the two strings.

Bounded by the wrapper caveat above.

### 3. `tool-invocation-metadata-present` — severity `warning`, `["chatgpt"]`

> message: `"2 tool(s) missing openai/toolInvocation metadata"`
> hint: *"For tools that render a UI resource, add openai/toolInvocation with
> string fields invoking and invoked (present-tense labels shown while the tool
> runs and after it finishes, e.g. \"Searching…\" / \"Searched\")."*

**Fix:** `_meta: { "openai/toolInvocation": { invoking, invoked } }` on
`start_audit` — passthrough proved above. The other of the two tools is
`show-app`, which D1 removes.

### 4. `tool-resource-metadata-complete` — severity `warning`, `["chatgpt","claudeai"]`

> message: `"2 resource(s) have incomplete metadata"`
> hint: *"Use a ui:// URI and text/html;profile=mcp-app. For mcp-use servers,
> set the widget description in widgetMetadata; other stacks can use
> \_meta.ui.widgetDescription or the OpenAI compatibility alias."*

Both resources already have the `ui://` URI, the `text/html;profile=mcp-app`
mimeType, and a `description`. The recommended field does not exist here (Q5).
**Fix:** the same `domain` as fix 5, then re-measure. Any residue is an SDK gap.

### 5. `view-domain-present` — severity `error`, `["chatgpt"]`

> message: `"2 ChatGPT UI domain issue(s) found"`
> hint: *"For ChatGPT submission, set one exact HTTPS origin such as
> \"https://app.example.com\" on every view via \_meta.ui.domain (or
> openai/widgetDomain). Paths are not valid and all views in one app must share
> the origin."*

**Fix:** `view: { domain: "https://mcp-readycheck.run.mcp-use.com" }` — a typed
field, origin only, no path, no trailing slash. After D1 exactly one view
remains, so "all views share the origin" holds by construction.

## Design decisions

**D1 — remove the scaffold. Score 78, confidence 0.54.** Delete the `show-app`
and `say-hello` tools and the `views/my-view` directory. Runner-up: keep
`my-view` as a reference, 70. Fixing all three so they pass, 52 — that spends the
work on example code whose only remaining product is a passing audit.

The scaffold is not incidental to this goal: four of the five failures count
**two** of something, and the app has exactly two view-bound tools and two views.
`show-app` also logs its caller's input to the console on every call and sleeps
1.5 s to make a skeleton visible in a demo.

**Confidence 0.54 is a near-tie, and this is the most destructive choice in the
plan — flagged for Gate A.** Reversal cost is one `git revert`; nothing is lost
that history does not hold.

**D2 — error format. Score 88, confidence 0.82.** Above.

**D3 — `openai/toolInvocation` strings are per-tool, not shared.** `invoking` and
`invoked` are labels a host shows for *that* tool's run; a shared pair would
mislabel every tool but one. After D1 only `start_audit` is view-bound, so the
question has no practical bite here. Recorded because the goal asked for it.

## Acceptance criteria

Default-FAIL: all five checks fail against baseline `523f56dc` today.

1. **Given** a fresh live audit of the deployed server after merge, **when** its
   checks are read, **then** all five checks in the table above report `pass`.
2. **Given** baseline `523f56dc` and the new audit, **when** they are diffed by
   `checkId`, **then** no check that passed in the baseline fails now.
3. **Given** the deployed `get_audit` on that audit, **then** both
   `isReadyForChatgpt` and `isReadyForClaudeai` are `true`.
4. **Given** any tool error this repo produces, **then** its text carries no API
   path, no HTTP status code and no schema-constraint phrasing (Q2's criterion).
5. **Given** `tools/list` from the deployed endpoint, **then** the view-bound
   tool carries `_meta["openai/toolInvocation"]`, and its view resource carries
   `_meta.ui.domain` as a bare HTTPS origin.
6. **Given** the green audit, **when** `start_audit` renders `audit-report`,
   **then** both badges read "ready".

## Phased TDD steps

Each phase writes nothing until its test fails for the stated reason.

1. **Annotations.** T1 fails (`get_audit` is read-only *and* open-world). Export
   the registered definitions from `index.ts`; set `openWorldHint: false` on
   `get_audit`. → T1.
2. **Scaffold removal.** T4 fails (`show-app` and `say-hello` are registered).
   Remove both tools and `views/my-view/`; drop the `instructions` string that
   tells the model to call `show-app`. → T4.
3. **View metadata.** T2 and T3 fail (no `_meta`, no `domain`). Add
   `openai/toolInvocation` and `view.domain` to `start_audit`. → T2, T3.
4. **Schema messages.** T5 fails (Zod default text is reachable). Give every
   `.min(1)` a custom message. → T5.
5. **Error mapping.** T6, T7, T8 fail (`humanError` does not exist). Add it to
   `lib/manufact.ts`; route `toolError` through it. → T6, T7, T8.
6. **Live.** Deploy — announced first, as its own line — then run `start_audit`
   and `get_audit` against the deployed endpoint and diff every check against
   `523f56dc`. → AC1, AC2, AC3, AC5, AC6.

## Test list — frozen by this PR's `.tests-locked`

`tests/self-audit-green.test.ts`, run by `npm test` (`node --test`).

| # | Test | AC |
|---|---|---|
| T1 | every registered definition declares all three annotation booleans, and `readOnlyHint: true` implies `openWorldHint: false` | AC1 |
| T2 | `start_audit` carries `_meta["openai/toolInvocation"]` with non-empty string `invoking` and `invoked` | AC5 |
| T3 | `start_audit`'s `view.domain` is a bare HTTPS origin — no path, no trailing slash, no port-less garbage | AC5 |
| T4 | the registered tool names are exactly `start_audit` and `get_audit`, and `index.ts` exports no `showApp` or `sayHello` | AC1 |
| T5 | every input-schema constraint rejects with a custom message — no Zod default text is reachable | AC4 |
| T6 | `humanError` on a `ManufactApiError` yields no `/api/` path and no status code, and still says what to do | AC4 |
| T7 | `humanError` never emits the API key, and passes a `MissingApiKeyError` through as its own guidance | AC4 |
| T8 | a handler failure is still `isError: true` with non-empty text — rewriting a message never swallows a failure | AC4 |

AC1's live half, AC2, AC3 and AC6 are properties of the deployed server, the wire
and the browser. They are demonstrated at S5 against the live endpoint and in the
Inspector, not by a unit test — the same split G2 used, stated so the coverage
claim is not read as stronger than it is.

## Files to touch

| Path | Why |
|---|---|
| `index.ts` | remove the scaffold tools; export the registered definitions; annotations, `_meta`, `view.domain` on `start_audit`; route `toolError` through `humanError` |
| `lib/manufact.ts` | add `humanError` |
| `lib/audit-schema.ts` | custom constraint messages (if any constraint there is reachable by a caller) |
| `tests/self-audit-green.test.ts` | the eight locked tests |
| `views/my-view/**` | removed (D1) |
| `.tests-locked` | created by this PR; merging it is Gate A |

Nothing else. A file not in this table is scope creep and needs a new plan.

## Symbol anchors

`startAudit`, `getAudit`, `startAuditInputSchema`, `getAuditInputSchema`,
`startAuditHandler`, `getAuditHandler`, `toolError` in `index.ts`; `humanError`,
`ManufactApiError`, `MissingApiKeyError` in `lib/manufact.ts`. Never line numbers.

## Invariants

- No failure is swallowed. A rewritten message is still an `isError: true` result.
- No `category`, `severity` or `scope` value is enumerated, defaulted or coerced.
- `MANUFACT_API_KEY` never reaches a message, a log line or a tool result.
- `checks: undefined` never becomes `[]`.
- Nothing under `.claude/` changes.
- No new dependency.

## Out of scope

Demo assets (G4). Autofix (G5). Any check outside the five. Any SDK gap recorded
under Q5 — recorded, not worked around. Any file absent from the table above.

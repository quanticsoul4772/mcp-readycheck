# Plan: mcp-readycheck stage sequence

The twelve-stage sequence for the project, its current position, and the
corrections accumulated from work already done. Individual features still get
their own plan file from `TEMPLATE.md`; this one is the spine they hang off.

## Uncertainty protocol

Assumptions still open, numbered, to be answered before the code they affect:

1. **ANSWERED (G1).** They are **slugs, and there are four, not six**:
   `connectivity`, `tool-metadata`, `client-compatibility`,
   `resource-metadata`. Read from audit `52eb5de9` (completed, 32 checks).
   Hardcoding the documented prose names would have been wrong about the
   spelling and the count at once.
2. **ANSWERED (G1).** `error`, `warning`, `info`. Scopes alongside them:
   `server`, `view`. Check statuses seen: `pass`, `fail`.
3. **ANSWERED (G1, from the spec).** `checks` is absent from the audit-detail
   200 schema's fourteen-entry `required` list, so it is optional in all
   states — not merely while pending. The output mirrors that: absent stays
   absent, never coerced to `[]`, because "still running, nothing yet" and
   "finished, found nothing" are different facts.
4. Does `runE2E: true` fail with a plan-tier error on Free, or is it silently
   ignored?

## Goal

Ship an MCP App that runs Manufact's publishing checks against its own deployed
URL and renders them grouped by category, then demonstrate a one-line failure
going red and back to green. Done means: the app audits itself, the widget
renders the real result, and the fail-to-green cycle is reproducible.

## Stages

| # | Stage | State |
|---|---|---|
| 1 | Preflight verification — Node, API key, OpenAPI contract | complete |
| 2 | Skill install and CLI login | complete |
| 3 | Scaffold `--template mcp-apps`, verify dev + Inspector | complete |
| 4 | Git baseline, harden `.gitignore`, GitHub repo, first push | complete |
| 5 | GitHub App connection, first deploy, managed env vars | complete |
| 6 | Slug rename, CI workflow, ruleset, PROGRESS.md | complete |
| 7 | Phase 0 floor — hooks, settings, agents, AGENTS.md, plans | complete |
| 8 | `run_readiness_check` — start/get tool pair | complete (G1: `start_audit` / `get_audit`) |
| 9 | Readiness widget — one View, grouped by category | next (G2) |
| 10 | Redeploy and self-audit green | |
| 11 | Staged one-line failure, red to green | |
| 12 | Autofix trigger surfacing the PR link (optional) | |

Stages 8 onward run the operating cycle: issue with Default-FAIL criteria →
plan file → **Gate A** → `.tests-locked` → TDD → evaluator → CI → **Gate B**.

## Accumulated corrections

Each of these was learned by being wrong about it. They are binding on the
stages that follow.

1. **The audit is keyed by `serverId`, not a URL.** `POST /api/v1/server-audits/{serverId}/audits`
   takes only optional `deploymentId`, `branch`, `runE2E` in its body. There is
   no URL field. `targetUrl` is server-derived output on the GET. `MCP_URL` is
   for self-identification and display only — and it carries no `/mcp` suffix,
   so a clickable endpoint must append it.
2. **Deployment and audit status vocabularies differ and must never share code.**
   A deployment settles at `running`; an audit's `running` means still in
   progress, with `completed` terminal. The reliable deploy-completion signal is
   `activeDeploymentId` becoming populated, not a status string.
3. **Derive category groups from the response.** `category`, `severity`, and
   `scope` are unconstrained strings with no enum, no example, no documented
   value list. The six category names come from marketing prose. Group by what
   comes back; keep a display-order lookup with a fallback to the raw string.
   Wire values may be slugs where the prose is a phrase.
4. **`hint` and `details` are untyped** — `anyOf: [{}, null]`, not strings. The
   widget must render a non-string hint without breaking.
5. **Split the tool in two: start and get.** A single tool that posts and then
   polls to completion holds a request open for the whole audit and gives the
   widget nothing to render until it finishes. `start_readiness_check` returns
   the `auditId` immediately; `get_readiness_check` returns the current state.
   The widget polls the second. This also makes the timeout case renderable
   rather than a dead request.
6. **CSP belongs in the View's resource metadata,** not an env var. The scaffold
   declares `view.csp.resourceDomains`. `CSP_URLS` is injected by the pipeline
   and is not the app's knob to turn.
7. **`pendingSlug` promotes on the next production deploy.** Undocumented in the
   spec, confirmed empirically. The server record lags the routing switch, so
   read-after-write on `slug` and `activeDeploymentId` can return stale values.

## Corrections added by G1

8. **`get_audit` cannot be keyed by `auditId` alone.** The audit-detail GET
   declares `serverId` and `auditId` as required path parameters, and no
   `auditId`-only route exists. The runtime is stateless, so the id cannot be
   carried over from the start call. Both tools take `serverId` explicitly.
9. **Audit `status` does have an enum** — `pending`, `running`, `completed`,
   `failed` — even though `category`, `severity` and `scope` do not. The POST
   returns `id`, not `auditId`.
10. **There is no 60-second host ceiling.** Refuted at confidence 1.0: the
    figure is the TypeScript SDK's overridable `DEFAULT_REQUEST_TIMEOUT_MSEC`,
    the MCP spec sets no numeric limit, and the Python SDK defaults to none.
    The start/get split stands on correction 5 above, which is the reason that
    survived. Do not justify anything by the 60-second number.
11. **A view binding with no directory throws at mount, not at build.** The SDK
    validates bindings when the server mounts, so `typecheck` and `build` both
    pass and the deployed server then crashes on startup. CI runs only those
    two commands and cannot catch this class of defect.
12. **`visibility: "app"` hides a tool from the model.** Combined with having no
    view, it leaves the tool callable by nothing. Confirmed live: the deployed
    `get_audit` advertises `_meta.ui.visibility: ["app"]` — the SDK emits the
    array from the singular `"model" | "app"` field. Only pair it with a view.
13. **`readOnlyHint` is a claim about state, not about intent.** `start_audit`
    creates a persistent audit record, so the hint is false for it, whatever
    the tool's read-only purpose.
15. **`get_audit` returns seven fields, not the five the goal named.**
    `errorMessage` and `targetUrl` were added deliberately (decide 0.67,
    runner-up: pass all fifteen response fields). Without `errorMessage`, an
    audit that settles at `failed` returns only that it failed and discards the
    cause the API supplied; without `targetUrl`, AC5's own subject is
    unobservable through the tools. Both are in the audit-detail `required`
    list, so the schema cannot be broken by a spec-conforming response. G2's
    widget contract is these seven fields.
14. **A relative module specifier cannot satisfy both toolchains.** TypeScript
    NodeNext wants `./x.js` and resolves it to `x.ts`; Node's type stripping
    resolves it literally. The `#lib/*` subpath imports map in `package.json`
    is what both resolve. Node's strip-only mode also rejects TypeScript
    parameter properties, which `typecheck` does not catch.
16. **A view needs no `connectDomains` entry for the API, and adding one would
    be wrong.** `connectDomains` maps to CSP `connect-src` — origins for fetch,
    XHR and WebSocket. A view calls a tool through the host bridge; the *server*
    contacts `cloud.manufact.com`. The framework already appends the server
    origin to `connectDomains` and the assets origin to `resourceDomains` at
    emission, so a view that makes no network request of its own declares no
    `csp` block at all and keeps the secure default of no connections. Naming
    the API origin would grant reach the view neither needs nor uses.
17. **`useToolContext` latches; it cannot be polled.** The first structured
    success or tool error becomes terminal for the view's lifetime and later
    notifications cannot overwrite it. A view that refreshes must call the tool
    itself via `useCallTool`, reading its ids off the latched
    `toolInput`/`toolOutput`. `useCallTool` also requires the tool be exported
    from the server entry — the type resolves to an error string otherwise.
18. **A verdict is now a required check, and it binds to a commit.** Ruleset
    `21871580` requires `verdict` alongside `fast-checks`, `bypass_actors: []`.
    A PR merges only with a fenced JSON object in its body carrying both
    `"verdict"` and an `"evaluated_commit"` naming the head SHA, so an approval
    given for one commit does not cover what is pushed after it. `[plan]` and
    `[docs]` titles are exempt only when every changed file is Markdown under
    `docs/` or the root README — a plan PR carrying tests is not exempt.
19. **Verify a gate by executing it, not by reading it.** Six distinct bypasses
    of `verdict.yml` were found across four evaluations, every one by extracting
    the `script:` body into a runnable function and running it against
    constructed cases. Reading passed all six. Two of the six were introduced by
    *tightening* the gate, and both were the same shape: a branch that
    terminates where it should continue.

## Invariants

- Secrets never enter the repository.
- The widget performs no network calls.
- `outputSchema` and returned `structuredContent` stay in lockstep.
- Every stage leaves `main` deployable.

## Out of scope

mcplint integration, E2E checks, the submission pack, preview-branch demos, and
custom domains. Each needs its own plan, and the last three need the Hobby tier.

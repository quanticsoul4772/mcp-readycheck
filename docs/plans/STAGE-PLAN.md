# Plan: mcp-readycheck stage sequence

The twelve-stage sequence for the project, its current position, and the
corrections accumulated from work already done. Individual features still get
their own plan file from `TEMPLATE.md`; this one is the spine they hang off.

## Uncertainty protocol

Assumptions still open, numbered, to be answered before the code they affect:

1. Do the `category` values returned by a live audit match the six documented
   category names, or are they slugs? Unknown until Stage 8 runs one.
2. What are the possible `severity` values? No enum in the spec.
3. Is `checks[]` absent while an audit is `pending`/`running`, or merely
   optional in all states?
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
| 7 | Phase 0 floor — hooks, settings, agents, AGENTS.md, plans | in progress |
| 8 | `run_readiness_check` — start/get tool pair | next |
| 9 | Readiness widget — one View, grouped by category | |
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

## Invariants

- Secrets never enter the repository.
- The widget performs no network calls.
- `outputSchema` and returned `structuredContent` stay in lockstep.
- Every stage leaves `main` deployable.

## Out of scope

mcplint integration, E2E checks, the submission pack, preview-branch demos, and
custom domains. Each needs its own plan, and the last three need the Hobby tier.

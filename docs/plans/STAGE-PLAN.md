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
| 9 | Readiness widget — one View, grouped by category | complete (G2) |
| 10 | Redeploy and self-audit green | complete (G3): green baseline `f4022c88`, 31/32 |
| 11 | Staged one-line failure, red to green | complete (G4): `docs/demo/`, red `5309c70b` → green `a8c78006` |
| 12 | Autofix trigger surfacing the PR link (optional) | probed (G5): autofix declined to fix the SDK gap, no PR — `docs/demo/autofix-probe.md` |
| — | CI actually runs tests (`test:pure`), test split | complete (G5) |
| — | Test discovery replaces enumeration; `test:check` in CI | complete (G6 S0): PRs #34, #35 |
| — | Submission package — README, ledger, census, 17 tests | complete (G6 S3): PR #37 |

**The plan is complete.** Post-merge audit [`6262a04a`](../demo/audit-post-g6.json)
against production returns
32 checks, 31 passing, both readiness flags true, and **zero deviations** from the
`f4022c88` baseline — run through the deployed tools rather than the API.

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
20. **Mark Stage 9 complete.** The `audit-report` view ships: `start_audit` is
    bound to it, `get_audit` carries `visibility: ["app"]`, and the deployed
    Inspector renders a live audit. Verified on the wire and in the browser,
    not inferred from the diff.
21. **`hint` really is an object on the wire.** A completed audit of this
    server returned `hint` types `["null","object"]` — never a string. G1's D3
    chose `z.unknown()` for `hint` and `details` on the strength of the spec's
    `anyOf: [{}, null]`; this is the live confirmation. A `z.string()` there
    would fail runtime validation against an ordinary response, and any view
    rendering it must stringify rather than assume.
22. **A view cannot poll `useToolContext`.** It latches the first structured
    result for the view's lifetime and later notifications cannot overwrite it,
    so the rendering invocation is permanently the *start* of the job. Progress
    comes from `useCallTool`, and the ids come off the latched
    `toolInput`/`toolOutput`.
23. **Schedule a polling loop from completion, never from call time.** Arming
    the next timer before the current call returns lets a slow response overlap
    the one after it, and an out-of-order arrival then overwrites a settled
    result with a stale one and restarts polling. Schedule in the completion
    path of each call, so exactly one is ever in flight.
24. **Put the error banner above the early return.** A refresh failure that
    leaves the primary state null takes the "still loading" branch, so a banner
    rendered after that branch is unreachable on exactly the path that needs
    it — a broken refresh then displays as healthy progress. This shipped once
    and an evaluation caught it.

## Corrections added by G3

25. **The green baseline.** Audit `f4022c88` on deployment #44 (`41f910b`,
    the merge of PR #20) is the reference G4 stages failures against:
    `isReadyForChatgpt: true`, `isReadyForClaudeai: true`, 32 checks, 31 pass.
    Diffed against baseline `523f56dc` by `checkId`: `tool-hints-present`,
    `fuzz-edge-case-handling`, `tool-invocation-metadata-present` and
    `view-domain-present` all moved fail → pass, 28 unchanged, **zero
    regressions**.
26. **One check remains red, and it is an SDK gap, not a repo defect.**
    `tool-resource-metadata-complete` (warning) reports "1 resource(s) have
    incomplete metadata" — down from 2, because removing the scaffold view took
    one with it. The check wants a widget description.
    `buildResourceUiMeta` in mcp-use 2.3.3 emits exactly `csp`, `permissions`,
    `domain`, `prefersBorder`, and `widgetMetadata` and `widgetDescription`
    appear in **no file** of the package. There is no way to set it from this
    repo. The plan pre-declared this as a residual before the work started,
    which is why it did not turn into a workaround.
27. **Severity gates readiness; warnings do not.** Both `error`-severity checks
    now pass and both flags are true while a `warning` is still failing. That
    confirms the hypothesis the plan recorded and refutes the assumption that
    every check must be green for a platform to accept the app.
28. **The audit's own hints can be wrong for your stack.** Two of the five
    named a field mcp-use 2.3.3 does not have. Following them literally would
    have set fields the framework ignores and produced two wrong fixes. Prove a
    framework behaviour by executing against the installed version before the
    plan asserts it — the SPIKE step earned its place.
29. **A goal's failure count can be wrong; verify it before planning against
    it.** G3 named "the seven named failures"; the live baseline had **five**.
    The extra two came from adding tool counts *inside* two checks. AC1 as
    written could not be satisfied, and the plan said so as a blocking question
    rather than quietly retargeting.
30. **`/mcp/inspector` is dev-only.** It 404s on the deployment. The hosted
    Inspector at `inspector.manufact.com`, reached from the "Open in Inspector"
    button on the `/mcp` landing page, is what renders a deployed view.
31. **Evaluate before pushing, not after opening the PR.** `verdict` fails
    closed, so a PR with no verdict in its body is red from the moment it
    exists — which is what the operator saw on #18, #19 and #20, with the admin
    bypass as their only lever. Commit, evaluate that commit, then push and
    `gh pr create --body-file` with the verdict already in the body, in one
    step. Do not push the branch early either: GitHub offers a "Compare & pull
    request" banner on any pushed branch. The gate was never the problem.
32. **A guard that has never been attacked has holes you have not met.** The
    guard PR took seven evaluation rounds, five of them BLOCK. Every defect was
    found by executing the guard; reading found none of them, and three were
    introduced by a previous round's fix. Budget for that shape of work: a
    change to a comparison rather than to a rule wants an old-vs-new side-by-side
    on identical input.
33. **Do not mutate the switch you are testing.** `tests-guard.test.sh` parked
    the repository's real `.tests-locked` and wrote a fake over it. Three
    incidents followed, and the third — the Stop hook committing the transient
    state, twice, on two branches — cannot be fixed by a `trap`, because the
    process that commits is not the process that dies. Remove the window rather
    than guarding it.

## Corrections added by G4

34. **`details` names the cause on a failing check. Read it.** Correction 4 and
    G3's plan both say `hint` and `details` are untyped (`anyOf: [{}, null]`),
    which is true and was the right reason not to assume they were strings. But
    refusing to assume the *type* turned into never reading the *contents*, and
    G3 spent a goal inferring which tool tripped `tool-hints-present` while the
    audit was naming it outright:

        {"label": "get_audit.annotations.openWorldHint",
         "value": "cannot be true when readOnlyHint is true because reads do
                   not change external state"}

    G3's plan states "the tool is inferred, not named by the audit." That was
    wrong. Bounded by the data: across 96 check-records (32 checks × 3 audits),
    `details` is 15 `null`, 77 empty, **4 populated — every one a failing
    check**. It is not an attribution field in general; a failing check may name
    its own cause. The five `null` checks are the same five in all three
    captures, so that set is structural.
35. **Severity gates readiness, and one error check is enough.** G3 established
    that warnings do not gate (correction 27). G4 measured the converse, which
    G3 explicitly could not: with `tool-hints-present` the *only* error-severity
    failure, `isReadyForChatgpt` went false while `isReadyForClaudeai` stayed
    true, matching the check's `platforms: ["chatgpt"]`.
36. **A squash-merge would have silently invalidated the demo.** If the break PR
    had been squashed or rebased, its commit would not be an ancestor of main,
    the revert branch's merge base would stay behind, and `index.ts` would
    resolve in main's favour — **the revert PR merges green while production
    stays red**. Found by an evaluator before the break was pushed. When a later
    PR must undo an earlier one, the earlier one is merged with a merge commit.
37. **A revert PR is not a way back until it has a verdict.** `verdict` fails
    closed and a revert of source is not docs-only, so an open revert PR with no
    verdict in its body is a red required check. Author the break and its revert
    together, evaluate both before either is pushed, and open both PRs before
    merging the break. Under `strict_required_status_checks_policy` the revert
    still goes out of date once the break lands, so budget the admin bypass
    rather than waiting on a re-evaluation while production is red.
38. **A guard can freeze a proposal it was never meant to cover.** With
    `.tests-locked` on main, a test file locks the moment it is *committed on any
    branch* — `ls-files ∪ ls-tree HEAD`. The proposal rule from PR #21 permits
    creating an unapproved test, not revising one, so an evaluator's findings
    about a proposed test could not be applied. Do not commit a proposed test
    file until its evaluation returns; re-authoring on a branch cut fresh from
    `origin/main` is the escape if you already have.
39. **State a bound at one scope, and recompute it.** The paragraph bounding
    correction 34 declared "96 check-records" and then gave per-capture counts,
    so "populated on the rest" resolved to 65 of 96 against a true figure of 4 —
    sixteen-fold, in the exact direction the paragraph existed to rule out. It
    was wrong twice the same way. A bound that states its components and their
    total makes drift visible as arithmetic instead of asking the reader to
    trust a summary.
40. **`git revert` is refused here; prove exactness instead.** The command is
    blocked by machine-level settings outside this repository. The property it
    was chosen for is exactness, and identical tree SHAs prove that more directly
    — a `git revert` with a hand-resolved conflict is not guaranteed exact, a
    matching tree hash is.

## Corrections added by G5

41. **Autofix is a coding agent, and it declined to invent a fix.** POSTing
    autofix against green audit `a8c78006` returned **200**, not the documented
    `422 "audit not fixable"` — the prediction recorded before the call was
    wrong about the mechanism. A real agent then ran 6m48s over a clone of the
    repo, made **zero** `Edit`/`Write` calls and **zero** mutating git commands,
    and concluded from the code that "neither `widgetMetadata` nor
    `openai/widgetDescription` appears in the mcp-use package". That is
    correction 26, derived independently. The job then failed on a GitHub
    PR-creation error (`field: head, code: invalid`) because there was no branch
    to open a PR from. Full record: `docs/demo/autofix-probe.md`.
42. **CI asserted nothing for the project's whole life, and a staged break is
    what proved it.** `fast-checks` ran `typecheck` and `build` only. G4's
    deliberate defect passed both. When a job is named for speed, read what it
    executes before treating it as a gate — the name is not the contract.
43. **Coverage claims must be measured per claim, not summarized.** One
    mistake-log entry about CI coverage took six evaluation rounds, and every
    error ran the same direction: toward implying more coverage than exists.
    The fourth was introduced *by the sentence fixing the third*; the sixth was
    claiming "four of five errors were caught by an evaluator" when all six
    were. An entry written to stop a reader trusting a green check kept
    overstating what the checks assert. Count against the artifact rather than
    describing it.
44. **A goal can name a defect that is not there.** G5's S1 specified a
    `stop_hook_active` fix to a Stop hook. The repo's only Stop hook exits 0 on
    every path and cannot block; the five hooks that can block are user-global
    and already contained that exact guard; and the hook that actually looped
    was the harness's own `/goal` evaluator, which is not a file in either
    location. Writing the plausible edit would have produced a PR, an
    evaluation and a merge that fixed nothing. Verify the defect exists before
    fixing it, and say so plainly when it does not.

## Invariants

- Secrets never enter the repository.
- The widget performs no network calls.
- `outputSchema` and returned `structuredContent` stay in lockstep.
- Every stage leaves `main` deployable.

## Corrections added by G6

45. **A guard that reads a file as text will be defeated by that file's own
    grammar.** Assertion 4 of `test:check` — "does CI still run the discovery
    check" — went through six versions, five of them rewrites. Every version that scanned `ci.yml` for
    `run:` values fell to YAML that Actions interprets differently from a
    scanner: a second job under `if: ${{ false }}`, a step-level `if:`,
    `continue-on-error: true`, then those two keys quoted, `${{ true }}` and
    `True` as values, a four-space job body, and `run: … || true` whose failure
    the shell swallows. Each fix pinned the spelling the last evaluation
    reported rather than the class behind it. The end state pins the whole job
    verbatim and digests the file, because an exact comparison has no grammar to
    be wrong about. Reading YAML correctly needs a parser, and a parser is a new
    dependency a human approves.
46. **The first fail-open blind spot is the one that matters.** Everything
    disclosed about that assertion's limits was fail-closed — the required check
    never reports, the pull request stays blocked. Then an evaluation found
    `defaults: run: shell: cat {0}` above `jobs:`, which makes every step in the
    pinned job print its script and exit 0 with all 21 pinned lines
    byte-identical. Listing only fail-closed limits had implied that a green
    check meant the steps ran. Sort a blind-spot list by which way it fails, not
    by how likely it looks.
47. **A test that passes for the wrong reason is worse than one that fails.**
    Three separate assertions in `tests/submission.test.ts` were vacuous:
    `new RegExp` built inside a template literal has its backslashes eaten, and
    `|\s*checks\s*\|\s*32\s*\|` becomes `|s*checkss*|s*32s*|`, an
    alternation with empty branches that matches any string including `""`. A
    line-based bullet scanner silently dropped the one entry that wraps, with
    its `>= 5` floor set to exactly the broken count. And an autofix check
    skipped any figure the README changed, so editing a number deleted its own
    test. Prove an assertion by mutating what it guards; thirty-three mutations
    caught is the evidence, not a green suite.
48. **A count recalled is a count wrong.** The BLOCK figure was stated as four
    across eleven rounds; it was six across thirteen. PR #34's merged body
    undercounts its own chain twice, as "Nine rounds. Three BLOCKs." and "Ten
    evaluation rounds: 4 BLOCK, 6 APPROVE-WITH-NOTES", where the ledger shows
    ten and five. Both were written from memory. `docs/evaluations.md` exists so
    the number is read off a table, and the README states the ledger is
    author-written — evidence that an evaluation happened, never that it was
    honest.
49. **The flattering error survives the act of correcting itself.** The PR
    census was measured four times and wrong three: a fabricated verdict counted
    as a real BLOCK, `APPROVE-WITH-NOTES` dropped from an approving count,
    figures taken before a merge landed, and a red-then-green count that asked
    "more than one run" instead of "first failed, last passed". Separately, an
    exculpatory "bootstrap exemption" was invented for #10 and #11 — and #10 had
    merged over a live evaluator BLOCK, recorded in #11's own body. There are
    two such merges, not one.
50. **Provenance is a claim like any other.** The README credited Phase 0, before
    any feature, with the required verdict check and a frozen test list. Neither
    existed then: `verdict.yml` arrived in #10 *after* #8 merged 72 seconds ahead
    of its BLOCK, and `.tests-locked` arrived in #19, two features later. One
    `git log --diff-filter=A` falsifies each. The sentence claimed foresight
    where the record shows reaction, at the head of the section whose purpose is
    the opposite.
51. **Evaluate, then push — and then do not edit.** Correction 31 says evaluate
    before opening the pull request. G6 obeyed that and still put the operator in
    front of a red required check, by fixing the final round's findings *after*
    the verdict was issued: the head moved, no verdict named it, and the gate
    refused. A verdict binds to a commit at both ends. Editing after it is the
    same failure as pushing before it.

## Out of scope

mcplint integration, E2E checks, the submission pack, preview-branch demos, and
custom domains. Each needs its own plan, and the last three need the Hobby tier.

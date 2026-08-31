# Plan: staged-failure demo (G4)

Written by the orchestrator, approved by the human at **Gate A** — the merge of
this PR. The lock marker is already on main from G3; this PR does not add or
change it, and its frozen list still names only G3's tests (see Q6).

The demo is the process, not a screenshot. A break ships through the normal
gates, the deployed app catches it, a revert ships through the same gates, and
the audit returns to the recorded baseline. The PR trail is itself the artifact.

---

## Uncertainty protocol

### Q1 — the break's effect is an INFERENCE, not a measurement. Confidence 0.70.

An earlier draft of this plan claimed the effect was "proven … not an inference"
by a single-variable experiment. **That was false, and an evaluation caught it.**
`git diff 41f910b^1 41f910b` — the G3 merge — is 8 files, +201/−1059: it deleted
the `show-app` and `say-hello` tools and all of `views/my-view/`, added
`_meta["openai/toolInvocation"]`, added `view.domain`, rewrote the server
description and instructions, and added `humanError`. Four checks flipped
fail→pass in that interval. Three of those edits could plausibly move
`tool-hints-present`, because two whole tools disappeared from the set it counts.

This project's own G3 plan says so outright, and this plan contradicted it:

> **Q4.** The audit does not name which tool trips `tool-hints-present` … the
> tool is inferred, not named by the audit.

It even set the falsification test — *"if the count is still 1 at S5, the
hypothesis was wrong"* — and the count went to 0 while three candidate causes
changed together. That is confirmation, not discrimination.

**What actually grounds the choice**, at 0.70: the check's own hint says
*"openWorldHint is true for writes that change publicly visible internet state
or send/submit to third parties, and false for closed/private workflows"*, and
in the four-tool table recorded at G3 Q4, `get_audit` was the **uniquely**
inconsistent row — read-only and open-world at once. The message counted exactly
one issue. One inconsistent row, one counted issue, and the issue went away when
that row was corrected.

**The branch this plan must carry:** if the red audit comes back with
`tool-hints-present` still passing, the inference was wrong. S3 stops, the revert
ships immediately (Q5), and the decide record is reopened with the measurement
in hand. That outcome is a finding, not a failure — it would be the first direct
evidence of how the check actually attributes.

### Q2 — BLOCKING if wrong. A `warning` break cannot satisfy AC1.

AC1 requires "both flags false or the relevant one false". STAGE-PLAN correction
27: **severity gates readiness; warnings do not** — the app ships today with
`tool-resource-metadata-complete` failing at `warning` and both flags `true`.

Removing `openai/toolInvocation`, the goal's first-named candidate, trips
`tool-invocation-metadata-present`, a **warning**. The audit would go red on a
row the readiness verdict ignores. That rules it out.

### Q3 — carried, and the converse of correction 27 is NOT measured.

Correction 27 establishes that warnings do not gate. It does **not** establish
that one failing `error` check turns a flag false. The only observation of an
error-severity failure against a flag is baseline `523f56dc`, where **two**
error/`["chatgpt"]` checks were failing at once. A single one failing alone has
never been seen on this server.

So AC1's red state is a prediction with two ways to be wrong: the check might
not fail (Q1), or it might fail without moving the flag (this question). Expected
red state: `isReadyForChatgpt: false`, `isReadyForClaudeai: true`, since the
check carries `platforms: ["chatgpt"]`.

**What happens if either prediction is wrong**, and why it needs a human. By the
time S3 measures, this test file is merged at Gate A and therefore tracked and
locked — so T2 asserts a red state no agent can then revise. The same exposure
sits on T3 and T4 if Manufact's check set moves off 32 checks / 31 pass between
`f4022c88` and the green capture. The revert ships first regardless (Q5), and
then:

> **YOUR ACTION (if the red audit does not match T2):** the staged break did not
> produce the predicted state, so T2 is asserting something untrue and no agent
> may edit it while `.tests-locked` is in force. Remove the marker, or edit
> `tests/staged-failure-demo.test.ts` yourself to match what the audit actually
> reported, then restore the marker. The measurement is a finding worth keeping —
> it would be the first direct evidence of how this check attributes.

Recording the measurement and correcting the test are separate acts, and only the
second needs you.

### Q4 — carried. The break must not disturb the SDK-gap check.

AC3 requires `tool-resource-metadata-complete` identical on both sides. The break
edits a tool's `annotations`; that check reads **resource** metadata. Measured at
S3 by diffing that check across the two captures — a difference is a stop.

This is also why `view-domain-present` is not the break, despite being a better
evidential fit (Q7).

### Q5 — BLOCKING. The recovery path in the earlier draft did not work.

That draft said "the revert PR is opened before the red capture begins". An
evaluation showed that is not a way back. A revert of `index.ts` is **not**
documentation-only, so it claims no exemption; `verdict` is a required check that
fails closed (correction 18); and an open PR with no verdict in its body is a
**red required check**, not a merge button. That is precisely what the operator
hit on #18, #19 and #20, and it contradicts binding correction 31.

**The sequencing that actually works**, per correction 31 — evaluate before
pushing:

1. Author the break commit **and** its `git revert` commit locally, on separate
   branches, before anything is pushed.
2. Get an evaluator verdict for **both**, naming both head SHAs.
3. Push both branches and open **both** PRs, each carrying its verdict, each
   green on its first check run. The revert PR is open and mergeable **before**
   the break is merged.
4. Post the recovery line below, naming the revert PR's real URL.
5. Merge the break at Gate B. Deploy. Capture red.
6. Merge the revert at Gate B. Deploy. Capture green.

An earlier draft of this list opened the revert PR *after* the red capture, which
contradicted the recovery paragraph below it and was caught in evaluation.
Followed literally, a session dying between the break's merge and that step would
leave production at `isReadyForChatgpt: false` with the evaluated revert commit
unpushed on one machine — the way back existing only in a place nobody else can
reach. The revert PR is open before the break merges, or the break does not
merge.

The revert is therefore *mergeable the moment it is opened*, which is the only
form of "way back" that means anything under a fail-closed required check.

**If a session dies between step 3 and step 6**, the operator holds a production
server at `isReadyForChatgpt: false`. What they need, and what S3 must print
before step 3 begins:

> **YOUR ACTION (recovery):** merge the revert PR `<url>`, then confirm the
> deploy at `https://manufact.com/cloud/.../deployments`. Its verdict is already
> in the body, so its checks are green. Nothing else is required.

That line, with the real URL filled in, is posted before the break is merged —
not after the break is live.

### Q6 — carried. The lock marker's inventory is stale, and no agent can fix it.

`.tests-locked` is on main from G3 and its list names only G3's tests. The guard
refuses every agent edit to the marker — correctly, since rewriting the lock is
the thing it exists to prevent. The lock is functional (existence-based); only
its inventory is out of date. Updating it is a human edit or it stays stale.

### Q7 — carried. `view-domain-present` is the better evidence, and still wrong.

An earlier draft claimed the chosen break was "the only candidate whose
audit-visibility is proven". False. `view-domain-present` is also `error` /
`["chatgpt"]`, also flipped in the same deploy, and its attribution is
**tighter**: "2 ChatGPT UI domain issue(s)" against exactly 2 views that carried
no `domain` at all. It belongs in the option table and was missing from it.

It is excluded on **AC3** grounds, not evidential ones: `domain` is the same
field that `tool-resource-metadata-complete` reads, so breaking it risks moving
the SDK-gap check, which AC3 forbids. The choice survives; the claim of
uniqueness does not.

---

## Verified facts

Each row states what was actually measured, and by what.

| Claim | Status | How |
|---|---|---|
| `tool-hints-present` is `error` / `["chatgpt"]`, message "1 behavior annotation issue(s) found" | **measured** | Read from baseline `523f56dc` via the API during this planning session |
| Its `hint` is an **object** with a `text` field, not a string | **measured** | Same read: `{"text":"On each tool, declare all three booleans accurately…"}` |
| A `warning` does not gate readiness | **measured** | `f4022c88`: `tool-resource-metadata-complete` fails, both flags `true` |
| A single failing `error` check turns a flag false | **NOT measured** | Only ever seen with two failing at once (Q3) |
| Flipping `openWorldHint` alone moves `tool-hints-present` | **NOT measured** | Inference at 0.70 from the hint's wording and the one-inconsistent-row count (Q1) |
| The audit reads tool annotations off the deployment | **measured** | Baseline `523f56dc` reported "1 behavior annotation issue(s)" against the deployed server — the check demonstrably reads annotations, whatever it attributes them to |
| The green baseline reproduces | **measured, not committed** | A second audit after two unrelated merges matched `f4022c88`. Its id is recorded in the gitignored PROGRESS.md and therefore is not repo-verifiable; treated as supporting, not as evidence |

An earlier draft cited "G3 drove a real `initialize` + `tools/list` against the
deployed endpoint" for the annotations row. That run proved `_meta` passthrough
in-process; the deployed `tools/list` read recorded visibility and view. The
substance holds by the route now cited; the original citation did not.

## Goal

Show the app catching a broken deployment of itself and confirming the fix.
Done means: a red audit from the live deployment naming the broken check, a green
audit after the revert whose check set matches `f4022c88` exactly, and
`docs/demo/` holding both with a README linking both PRs and both audits.

## Design decisions

**D1 — the break is `get_audit.annotations.openWorldHint: false → true`.**

| Option | Audit-visible | Turns a flag false | Touches the SDK gap | Score |
|---|---|---|---|---|
| `openWorldHint` on `get_audit` | inferred, 0.70 (Q1) | expected — `error` (Q3) | no | **74** |
| remove `view.domain` | inferred, **tighter** (Q7) | expected — `error` | **yes, plausibly** — AC3 risk | 41 |
| remove `openai/toolInvocation` | likely | **no** — `warning` (Q2) | no | 34 |
| break a CSP domain | unproven | unknown | CSP is resource metadata | 28 |

Confidence **0.70**, down from an earlier draft's 0.88, which rested on an
evidential claim that did not survive review. The margin over `view.domain` is
AC3 compliance, not evidence quality.

It is the most faithful break available: it re-introduces a defect this project
actually shipped and an evaluator actually caught — a tool declaring itself
read-only while reaching a third party.

**D2 — the break is caught twice, and the first catch is a locked test.**

Verified by execution during review: with the break applied,
`get_audit.annotations` becomes `{readOnlyHint: true, destructiveHint: false,
openWorldHint: true}`, which **fails T1 of `tests/self-audit-green.test.ts`** —
*"get_audit is read-only yet claims openWorldHint"*. That file is tracked and
frozen, so no agent can touch it.

This is the design, not an obstacle:

- The break branch ships with `npm test` **red**, and that redness is the point.
  The locked suite catches the defect at commit time; the live audit catches it
  again after deploy. The demo shows two independent layers refusing it.
- **No test is edited to accommodate the break.** Not the locked suite, not this
  one. An agent quieting a test to make a break look clean is the exact failure
  `.tests-locked` exists to prevent.
- CI stays green throughout, because `fast-checks` runs typecheck and build only
  and never `npm test`. That gap is worth naming: **CI would not have caught this
  break.** Only the locked suite and the live audit do.

**D3 — capture is audit JSON committed to the repo, plus Inspector screenshots.**

The JSON is machine-diffable evidence; the screenshots are the human-legible
half, referenced by path from the README. Every capture comes from the deployed
endpoint through `start_audit` / `get_audit` — AC4 — and each carries its own
`targetUrl`, which the tests check.

**D4 — the revert is `git revert` of the break commit, evaluated before it is
opened.** Not a hand-written inverse patch: `git revert` produces a provably
exact inverse, which is what makes AC2 checkable rather than asserted. Its
verdict is obtained in step 2 of Q5's sequence, so the PR is green on its first
check run.

**D5 — the criterion for evaluating the break PR.** S3 asks an evaluator to
approve a PR whose entire content is a defect. A standard rubric returns BLOCK,
and the demo stalls. The break PR's evaluation is therefore scoped explicitly,
in its launch prompt:

> This PR intentionally re-introduces a known defect as a staged demo failure,
> under plan `docs/plans/staged-failure-demo.md` decide D1. Do **not** judge
> whether the change is desirable. Judge only: (a) the diff is exactly the one
> line named in D1 and nothing else; (b) `git revert` of it restores the parent
> tree byte-for-byte; (c) no test file is modified; (d) nothing under `.claude/`
> is touched; (e) a `git revert` commit of it exists locally, is included in this
> evaluation, and is being approved in the same pass. Approve if all five hold.

Point (e) is phrased against the *commit*, not against a pull request. An earlier
draft asked the evaluator to confirm "the revert PR exists … and is mergeable",
which is unverifiable at the moment the criterion is applied: correction 31
requires the evaluation to precede any push, so no PR exists yet. What can be
checked then is that the revert commit exists and is in scope.

Without that scoping, the gate that protects the repo would block the demo of
the gate protecting the repo.

## Acceptance criteria

Default-FAIL: `docs/demo/` does not exist, and no capture has been taken.

1. **Given** the break is deployed, **when** an audit runs through the deployed
   tools, **then** `tool-hints-present` reports `fail` and `isReadyForChatgpt`
   is `false`.
2. **Given** the revert is deployed, **when** an audit runs, **then** its check
   set diffs clean against `f4022c88` — every `checkId` at the same status.
3. **Given** the red and green captures, **when**
   `tool-resource-metadata-complete` is compared, **then** its status, severity
   and message are identical.
4. **Given** any committed capture, **when** its `targetUrl` is read, **then**
   it is `https://mcp-readycheck.run.mcp-use.com/mcp`.
5. **Given** `docs/demo/README.md`, **when** it is read, **then** it links the
   break PR, the revert PR, and both audit ids, and narrates break → caught →
   revert → green.
6. **Given** `docs/ci/verdict-cases.md`, **when** case 3 is read, **then** it is
   recorded as exercised with its run URL. *(Already satisfied — PR #25.)*

## Phased TDD steps

1. **Assets contract.** T1–T7 fail because `docs/demo/` is absent. → this plan,
   the test file.
2. **Author both commits locally.** The break (one line in `index.ts`) and its
   `git revert`, on separate branches, nothing pushed. Confirm `npm test` is red
   on the break branch with exactly T1 of `self-audit-green` failing, and green
   again on the revert branch.
3. **Evaluate both**, per Q5 step 2 and the D5 criterion. Push and open both PRs,
   each carrying its verdict.
4. **Post the recovery line** (Q5), then merge the break at Gate B, deploy.
5. **Capture red** → `docs/demo/audit-red.json`, screenshot. → AC1, AC4.
6. **Merge the revert** at Gate B, deploy. **Capture green** →
   `docs/demo/audit-green.json`, screenshot, diffed against `f4022c88`.
   → AC2, AC3.
7. **The narrative.** `docs/demo/README.md` and `check-diff.md`. → AC5.

## Test list — frozen by the marker already on main

`tests/staged-failure-demo.test.ts`, run by `npm test`.

| # | Test | AC |
|---|---|---|
| T1 | both captures parse and carry `auditId`, `status: "completed"`, `targetUrl`, and a non-empty `checks` array | AC1, AC2 |
| T2 | the red capture has `tool-hints-present` at `fail` with `severity: "error"`, and `isReadyForChatgpt: false` | AC1 |
| T3 | the green capture has both flags `true` and no check failing except the SDK gap | AC2 |
| T4 | the baseline file **is** audit `f4022c88` — id prefix, 32 checks, 31 pass, its one failure the SDK gap — and every `checkId` in the green capture matches it at the same status | AC2 |
| T5 | the SDK gap is identical in status, severity and message across red and green | AC3 |
| T6 | both captures' `targetUrl` is the production endpoint, and neither is localhost | AC4 |
| T7 | the README carries both audit ids and links two distinct PRs | AC5 |

### Q8 — carried, and it cost this plan a restart.

An evaluation found T4 circular: it compared the green capture against
`baseline-f4022c88.json` without checking that the file **is** that audit, so
copying `audit-green.json` over the name would pass with zero deviations. T4 now
asserts the id prefix, the check counts, and that the baseline is not the green
capture, before comparing anything.

Applying that fix was blocked at first. `.tests-locked` has been on main since
G3, and the guard reads `ls-files ∪ ls-tree HEAD`, so a test file locks the
moment it is **committed on any branch**. The proposal rule from PR #21 permits
*creating* an unapproved test; it does not permit *revising* one after commit. So
an evaluator's findings about a proposed test could not be applied by the agent
that proposed them — with G4's Gate A not yet reached, G3's lock was freezing
G4's proposals.

The way through needed no human and no guard change: cut a fresh branch from
`origin/main`, where the file has never existed, and author it once, corrected.
It is a proposal again there.

**The rule that follows:** while the marker is on main, do not commit a proposed
test file until its evaluation has returned. A commit is what freezes it.

Recorded, not acted on — the guard layer is frozen under ADR-0003:

- The structural fix is for the proposal rule to key on `origin/main` rather than
  the current branch's HEAD. A file committed only to a feature branch is still a
  proposal; Gate A is what approves it.
- `tests-guard.sh` refuses `Edit`/`Write` to a locked test and refuses shell
  *redirection* into one, but does not refuse `rm` or `git rm` of one. Deleting a
  locked test is not currently blocked. Noted for a future guard goal.

## Files to touch

| Path | Why |
|---|---|
| `index.ts` | the break (one line), and its revert |
| `tests/staged-failure-demo.test.ts` | the seven tests, pending Q8 |
| `docs/demo/audit-red.json` | red capture |
| `docs/demo/audit-green.json` | green capture |
| `docs/demo/baseline-f4022c88.json` | the recorded baseline, for T4 |
| `docs/demo/check-diff.md` | red vs green vs baseline, check by check |
| `docs/demo/README.md` | the narrative |

`.tests-locked` is **not** touched — it is already on main and no agent may edit
it. Nothing under `.claude/`; the guard layer is frozen (ADR-0003).

## Symbol anchors

`getAuditDefinition` in `index.ts`, specifically its `annotations` object.
`startAuditHandler` and `getAuditHandler` unchanged. Never line numbers.

## Invariants

- Production is never left red at rest, and the revert is mergeable — verdict in
  body — before the break is merged.
- The break touches exactly one boolean.
- **No test file is edited for the duration of the break.** The locked suite
  going red is the intended signal.
- No capture is edited by hand after it is written.
- `tool-resource-metadata-complete` is neither target nor casualty.
- No new dependency. Nothing under `.claude/`.

## Out of scope

Autofix (G5). Submission text (G6). Any second staged failure. Any change to the
guard layer. Making `tool-resource-metadata-complete` pass — it has no code path
in mcp-use 2.3.3.

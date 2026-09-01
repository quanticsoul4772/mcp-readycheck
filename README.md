# mcp-readycheck

An MCP App that runs Manufact's publishing checks against its own deployed URL
and renders the result by category. It is its own test case: the server you audit
with it is the server serving it. Every number below is asserted by the test
suite against a committed capture or against this repository, not typed.

## The self-audit

Audit [`f4022c88`](docs/demo/baseline-f4022c88.json), the current baseline:

| | |
|---|---|
| checks | 32 |
| passing | 31 |
| failing | 1, severity `warning` |
| `isReadyForChatgpt` | **true** |
| `isReadyForClaudeai` | **true** |

Severity gates readiness and warnings do not, so both flags are true with one
check red.

### The one red check, and why it stays red

`tool-resource-metadata-complete` — "1 resource(s) have incomplete metadata",
scope `view`, on `ui://views/audit-report.html`. Its hint says to set the widget
description in `widgetMetadata`, or `_meta.ui.widgetDescription`.

Neither string appears in any file of mcp-use 2.3.3. `buildResourceUiMeta` emits
exactly `csp`, `permissions`, `domain` and `prefersBorder`. There is no code path
in this repository that can satisfy the check.

That is this repository's conclusion. It is also **Manufact's own conclusion**.
[The autofix probe](docs/demo/autofix-probe.md) POSTed Manufact's autofix at this
exact failure. It returned 200, ran a real coding agent with repository access
for 6 minutes 48 seconds over 200 events, called `Bash` 87 times and `Read`
twice, made **zero** `Edit`/`Write` calls and **zero** git mutations, and
recorded, in its own words:

> neither `widgetMetadata` nor `openai/widgetDescription` appears in the mcp-use
> package. This means the mcp-use 2.3.3 framework doesn't have first-class
> support for `openai/widgetDescription`.

A different agent, reasoning from the code, reached the finding this project had
recorded two goals before the probe ran, in G3. What the probe does **not** show is autofix fixing
something and opening a merged pull request; producing that would have meant
breaking production on purpose to create a defect it could fix.

## The staged-failure demo

[`docs/demo/README.md`](docs/demo/README.md) — a one-line defect was shipped to
production deliberately, the app's own audit caught it, and the revert restored
the baseline. Both audits are captured.

| | audit | `isReadyForChatgpt` |
|---|---|---|
| broken | [`5309c70b`](docs/demo/audit-red.json) | **false** |
| reverted | [`a8c78006`](docs/demo/audit-green.json) | true |

`isReadyForClaudeai` stayed `true` on both. The break moved one flag, not both.

Break: [#27](https://github.com/quanticsoul4772/mcp-readycheck/pull/27) ·
revert: [#28](https://github.com/quanticsoul4772/mcp-readycheck/pull/28)

## The endpoint

    https://mcp-readycheck.run.mcp-use.com/mcp

Two tools. `start_audit` POSTs an audit for a server id and returns the audit id;
`get_audit` fetches one and renders it by category. Views are pure-render — every
network call happens server-side in the handler, or the app trips its own CSP
check.

## The process, and what it cost

Phase 0 built a floor before any feature, and it was smaller than the floor
standing today. What it actually contained is
[stage 7 of the plan](docs/plans/STAGE-PLAN.md): PreToolUse guards, agent
definitions, settings, and AGENTS.md — plus an evaluator that reviews every diff
in fresh context against a Default-FAIL rubric.

The two pieces most often mistaken for foundations were reactions:

- the **required verdict check** was added in
  [#10](https://github.com/quanticsoul4772/mcp-readycheck/pull/10) on 2026-08-31,
  after [#8](https://github.com/quanticsoul4772/mcp-readycheck/pull/8) — the first
  feature — had already merged 72 seconds ahead of its BLOCK the night before;
- the **frozen test list** did not exist until
  [#19](https://github.com/quanticsoul4772/mcp-readycheck/pull/19), two features
  later. `tests-guard.sh` shipped in Phase 0 but its first line is
  `[ -f "$MARKER" ] || exit 0`, so with no `.tests-locked` on disk it returned
  success on every call.

Both are verifiable in one command each
(`git log --diff-filter=A -- .github/workflows/verdict.yml`), and an earlier
draft of this section claimed both as pre-feature foresight. An evaluation caught
it.

It did not work smoothly. The record, as of this commit and computed from
[`docs/pr-census.json`](docs/pr-census.json), which the command in that file
regenerates:

| | |
|---|---|
| goals recorded in the stage plan | 6 |
| pull requests opened | 37 |
| merged | 36 |
| merged over a red required check | 5 — #10, #11, #21, #28, #32 |
| merged over a live evaluator BLOCK | **2** — #8 and #10 (see below) |
| merged before the gate existed | 9 |
| passed the gate carrying a verdict | 16 |
| passed by the `[docs]` exemption, carrying none | 6 |
| went red, then green once the verdict was added | 8 |
| corrections in the stage plan | 51 |
| entries in the mistake log | 57 |

Where those rows come from, since they do not all come from one place:

- the pull-request rows are computed by `scripts/pr-census.mjs` from the GitHub
  API into `docs/pr-census.json`, and the suite compares this table to that file;
- the goal count is scanned out of `docs/plans/STAGE-PLAN.md`, and the correction
  and mistake-log counts out of that file and `AGENTS.md`;
- **one row is not computed at all.** A BLOCK that was overridden leaves nothing
  the API can be asked for: #8's verdict arrived after the merge, and #10's is
  recorded in prose in
  [#11](https://github.com/quanticsoul4772/mcp-readycheck/pull/11)'s body. That
  row is a claim with its evidence linked, and the fixture says so where it is
  set.

Six goals produced that record — G1 through G6, each named in the
stage plan, each ending at a human merge. This submission is the last of them.

**[PR #8](https://github.com/quanticsoul4772/mcp-readycheck/pull/8) merged 72
seconds before its BLOCK arrived**, shipping three defects. **[PR
#10](https://github.com/quanticsoul4772/mcp-readycheck/pull/10) merged over a
BLOCK on its head commit**, recorded in
[#11](https://github.com/quanticsoul4772/mcp-readycheck/pull/11)'s own body. The
gate exists because of the first; it did not stop the second.

Eight merges went red before going green, for two reasons rather than one. Most
were opened before their evaluation finished, and the fix is ordering: evaluate,
then push and open with the verdict already in the body. But PR #12 and PR #14
went red for a different reason — a verdict binds to a head commit, and merging
main into the branch moves that head, so a valid approval stops applying. On #12
the approval named `399fa5a` and the head had become `815d866`. Ordering does not
prevent that one; budgeting a re-evaluation after any merge into the branch does.
And #37 — the pull request carrying this README — went red for a third reason:
its final evaluation returned BLOCK, the findings were fixed, and fixing them
moved the head past the commit the verdict named. Evaluating before pushing is
not sufficient; the commit must also stop moving afterwards. All three are in the
mistake log as separate entries.

### The guard marathon

One file — `.claude/hooks/tests-guard.sh`, the hook that refuses edits to frozen
tests — accounts for an unbroken run of the mistake log:

| | |
|---|---|
| consecutive entries correcting one guard file | 36–53 |
| entries in that run | 18 |

Most were found by executing the guard rather than reading it, several by
tripping it while writing it. Not all: entry 52 records a write
surface the guard does not cover and leaves it open, without saying how it was
noticed. A sample of the run:

- *A guard scoped to a convenient token refuses the whole machine.*
- *A backslash continuation is not a command boundary.*
- *Lower-case before classifying, not only before looking up.*
- *A verb enumeration is only as complete as the last person's shell.*
- *Git Bash rewrites a POSIX path passed as argv to a native binary.*
- *A test must not mutate the thing it is testing when that thing is a global
  switch.*

The last one describes the guard's test suite disabling the guard three separate
times, twice committed by a Stop hook.

### Defects found by evaluation versus by the author

Recorded per round in [`docs/evaluations.md`](docs/evaluations.md). The ledger is
written by this project, not by an independent party — treat it as evidence that
an evaluation happened, never as evidence that it was honest, which is the same
caution AGENTS.md gives about the verdicts in pull request bodies.

| | |
|---|---|
| evaluation rounds recorded | 19 |
| of which the evaluator returned BLOCK | 9 |
| rounds that produced at least one finding | 17 |
| defects the author noticed first | 2 |

The two: the first check's tautology, noticed before round 1's verdict returned
— though that evaluation found it independently and proved it over 512
constructed inputs, so the credit is shared — and a mis-built test harness that
reported a bypass which did not exist. Everything else in the ledger came from an
evaluation.

The count of evaluator BLOCKs **cannot** be derived from this repository. Exactly
one `BLOCK` verdict object appears in any pull request body, and it is a
hand-written fixture in
[#24](https://github.com/quanticsoul4772/mcp-readycheck/pull/24), a closed pull
request titled "FABRICATED FOR GATE TEST". Zero real BLOCK verdict objects
survive — for a project that overrode two BLOCKs — because the process requires
resolving a BLOCK locally before the pull request exists.

The pull request bodies are not merely silent, they are wrong. [PR
#34](https://github.com/quanticsoul4772/mcp-readycheck/pull/34) undercounts its
own chain twice — "Nine rounds. Three BLOCKs." in one section and "Ten evaluation
rounds: 4 BLOCK, 6 APPROVE-WITH-NOTES" at the close — where the ledger records
ten rounds, five BLOCK and five APPROVE-WITH-NOTES. It is merged and cannot be
edited. Both figures were recalled rather than read off a table, which is the
failure this section exists to document, committed inside the documents
describing it.

AGENTS.md's coverage entry is the same shape and says so in its own words: five
successive errors about what the test suite covers, every one in the reassuring
direction, closing with **"All five were caught by an evaluator, not by me."**

## Known residuals

- [ADR-0003](docs/decisions/ADR-0003-guard-residuals.md) — five accepted
  residuals in the write-guard and `integrity.sh` layer. An attester cannot
  attest itself; that limit ends at a human reading the diff.
- CI coverage has holes, enumerated in AGENTS.md with the units named. Some code
  is executed by no suite at all.
- `views/audit-report/view.tsx` is covered by nothing — there is no DOM harness.
- `test:check`'s blind spots are listed in `scripts/run-tests.mjs`, including one
  it cannot close from inside the file.

## Development

    npm install
    npm run dev          # /mcp on :3000, Inspector at /mcp/inspector
    npm run typecheck
    npm run test:check   # discovery matches the index, CI, and the npm scripts
    npm run test:pure    # no network, no key — what CI runs
    npm run test:live    # POSTs real audits; needs MANUFACT_API_KEY

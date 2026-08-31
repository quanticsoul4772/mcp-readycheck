# verdict.yml — the case list

`.github/workflows/verdict.yml` is a required status check on `main` (ruleset
`21871580`, alongside `fast-checks`). It fails a PR unless the body carries a
fenced JSON object with **both** an approving `verdict` and an
`evaluated_commit` naming the head SHA.

**Correction to an earlier version of this line:** it said
`bypass_actors: []`. That was true when written and is no longer. The ruleset
now carries `{actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "always"}`
— an admin override — because an empty bypass list left the repository owner
with no lever at all when a stalled evaluator held a PR closed, and froze the
repo. Confirmed against the API on 2026-08-31.

This file is the list of cases the workflow must pass and fail. It exists
because the workflow has no automated test — there is no harness that runs it
in CI — so this is the record of what has actually been exercised, and against
which PR. **"Not yet exercised" means not yet exercised.** It does not mean
"probably fine".

Six defects were found in this workflow across four adversarial evaluations,
every one by *executing* the script rather than reading it (STAGE-PLAN
correction 19). Two of the six were introduced by tightening it. Treat a case
marked below as unexercised with that history in mind.

## Cases

| # | Case | Expected | Exercised |
|---|---|---|---|
| 1 | Valid `APPROVE` naming the head commit | **pass** | **Yes** — PR #13 (`406b9ce`), PR #16 (`4cdf982`), PR #21 (`437f6ad`), PR #22 (`353cc9f`) |
| 2 | Valid `APPROVE-WITH-NOTES` naming the head commit | **pass** | **Yes** — PR #14 (`c14d255`), PR #19 (`fc331a1`), PR #20 (`b05843a`) |
| 3 | `BLOCK` verdict naming the head commit | **fail** | **Still no.** Six more BLOCKs arrived during G3 (guard rounds 1, 2, 5, 6, 8, 9) and every one was acted on before the body was updated, so no BLOCK body has ever reached the workflow. Verified only by executing the extracted script against a constructed body. |
| 4 | No verdict anywhere in the body | **fail** | **Yes** — PR #10 on its own first run, `body: none`; PR #16 before its verdict landed; PR #19 and PR #20, both opened before their evaluator returned |
| 5 | `[plan]` title, documentation-only diff | **pass, exempt** | **Still no.** Every `[plan]` PR has carried tests, including PR #19. A plan PR without tests may not be a real shape in this workflow — the plan and its Default-FAIL suite ship together by design. |
| 6 | `[docs]` title, documentation-only diff | **pass, exempt** | **Yes** — PR #15, PR #17, PR #23. Passes with no evaluator round. |
| 7 | `[plan]` title, diff carrying tests | **fail — not exempt** | **Yes** — PR #12 (`tests/audit-report-view.test.ts`), PR #19 (`.tests-locked` and `tests/self-audit-green.test.ts`) |
| 8 | Fenced block that mentions `verdict` but does not parse | **ignored as prose** | **Yes** — PR #11's own body quotes the contract line, which is not valid JSON, and the check passed. This is the case an earlier revision got *wrong*, hard-failing valid PRs. |

## Cases beyond the eight, exercised anyway

| Case | Expected | Exercised |
|---|---|---|
| Approval naming an **earlier** commit after the head moved | **fail** | **Yes** — PR #12 after main was merged in: `APPROVE@399fa5a` found, head `815d866`, refused |
| `evaluated_commit` empty string or one character | **fail** | **No** — script-level only. `headSha.startsWith("")` is `true` in JavaScript, which is why the value must match `/^[0-9a-f]{7,40}$/` before comparison |
| Rename of a non-doc file onto a `docs/**.md` path under a `[docs]` title | **fail** | **No** — script-level only. `pulls.listFiles` reports only the destination, so `previous_filename` is checked too |
| `merge_group` event | **n/a** | **No merge queue exists.** The trigger is deliberately absent: gating a step on the event type made a merge-group run report success having evaluated nothing. Without the trigger a queue stalls, which is a stop |

## Operating the gate

Two things learned by getting them wrong across PRs #18–#23.

**Evaluate before pushing.** The check fails closed, so a PR whose body has no
verdict is red the moment it exists. Opening the PR and evaluating afterwards
put a red required check in front of the operator three times, with the admin
bypass as their only lever. The order that never shows a red run: commit
locally → evaluate that commit → push and `gh pr create --body-file` with the
verdict already in the body, in one step. Do not push the branch early either —
GitHub offers a "Compare & pull request" banner on any pushed branch, and acting
on it is the reasonable thing for a human to do. PRs #21, #22 and #23 were each
green on their first run this way.

**`gh pr edit --body-file` can silently fail here.** On this repository it errors
with `GraphQL: Projects (classic) is being deprecated … (repository.pullRequest.projectCards)`
and leaves the body unchanged — as a *warning*, exiting zero, so it reads as
success. Use `gh api repos/{owner}/{repo}/pulls/{n} -X PATCH -F body=@file` and
read the body back to confirm. This cost one false "the verdict is posted"
claim.

## What this list does not cover

The body is author-written, so a verdict string typed by the PR author
satisfies the check. That is not closed in code and cannot be — it rests on a
human clicking merge. The gate is evidence that a verdict exists, never that it
is honest.

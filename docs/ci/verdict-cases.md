# verdict.yml — the case list

`.github/workflows/verdict.yml` is a required status check on `main` (ruleset
`21871580`, alongside `fast-checks`, `bypass_actors: []`). It fails a PR unless
the body carries a fenced JSON object with **both** an approving `verdict` and
an `evaluated_commit` naming the head SHA.

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
| 1 | Valid `APPROVE` naming the head commit | **pass** | **Yes** — PR #13 (`406b9ce`), PR #16 (`4cdf982`) |
| 2 | Valid `APPROVE-WITH-NOTES` naming the head commit | **pass** | **Yes** — PR #14 (`c14d255`) |
| 3 | `BLOCK` verdict naming the head commit | **fail** | **No.** Every BLOCK so far was acted on before the body was updated, so no BLOCK body has reached the workflow. Verified only by executing the extracted script against a constructed body. |
| 4 | No verdict anywhere in the body | **fail** | **Yes** — PR #10 on its own first run, `body: none`; PR #16 before its verdict landed |
| 5 | `[plan]` title, documentation-only diff | **pass, exempt** | **No.** Every `[plan]` PR so far has carried tests (case 7). The exemption path has only been exercised by `[docs]` (case 6). |
| 6 | `[docs]` title, documentation-only diff | **pass, exempt** | **Yes** — PR #15, PR #17. Passed in ~4 s with no evaluator. |
| 7 | `[plan]` title, diff carrying tests | **fail — not exempt** | **Yes** — PR #12. Named `tests/audit-report-view.test.ts` as the disqualifying file. |
| 8 | Fenced block that mentions `verdict` but does not parse | **ignored as prose** | **Yes** — PR #11's own body quotes the contract line, which is not valid JSON, and the check passed. This is the case an earlier revision got *wrong*, hard-failing valid PRs. |

## Cases beyond the eight, exercised anyway

| Case | Expected | Exercised |
|---|---|---|
| Approval naming an **earlier** commit after the head moved | **fail** | **Yes** — PR #12 after main was merged in: `APPROVE@399fa5a` found, head `815d866`, refused |
| `evaluated_commit` empty string or one character | **fail** | **No** — script-level only. `headSha.startsWith("")` is `true` in JavaScript, which is why the value must match `/^[0-9a-f]{7,40}$/` before comparison |
| Rename of a non-doc file onto a `docs/**.md` path under a `[docs]` title | **fail** | **No** — script-level only. `pulls.listFiles` reports only the destination, so `previous_filename` is checked too |
| `merge_group` event | **n/a** | **No merge queue exists.** The trigger is deliberately absent: gating a step on the event type made a merge-group run report success having evaluated nothing. Without the trigger a queue stalls, which is a stop |

## What this list does not cover

The body is author-written, so a verdict string typed by the PR author
satisfies the check. That is not closed in code and cannot be — it rests on a
human clicking merge. The gate is evidence that a verdict exists, never that it
is honest.

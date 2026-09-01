# Plan — submission package (G6)

Status: proposed. Gate A is a human merging this PR.

The repo's landing page presents mcp-readycheck to a Manufact reviewer: what it
is, the self-audit, the staged-failure demo, the autofix probe, and the process
that produced it — with the failure record foregrounded rather than hidden.

The README today is 30 lines of `create-mcp-use-app` scaffold that never names
the project. It is replaced entirely.

## Decide — one document or two

**README alone** (82), over README + `docs/SUBMISSION.md` (55) and a split where
the README duplicates headline facts (38). Confidence 0.635.

Deciding factors: the landing page is the reviewer's first and often only read;
every numeric claim must be asserted by the suite, so each document added is
test surface added; a failure record one click off the landing page is not
foregrounded; nothing known requires a separate document; duplicated numbers
across two files drift.

The existing `docs/` tree already carries the detail a reviewer may want to
follow — `docs/demo/README.md`, `docs/demo/autofix-probe.md`,
`docs/decisions/ADR-0003-guard-residuals.md`, `docs/plans/STAGE-PLAN.md`. The
README links to them rather than restating them.

## Decide — README structure

**Evidence-first** (88), over product-first (62), process-first (55), and a
claim/evidence table up front (45). Confidence 0.63.

    what it is (three sentences)
    the self-audit result, with the one red check named immediately
    the staged-failure demo and the autofix probe, as proof
    the live endpoint and how to call it
    the process, and the failure record
    known residuals

Product-first loses because it pushes the failure record to the end.
Process-first loses because the failure record lands before the reader knows
what the thing is, and so before it can mean anything. The table loses because
compressing the process into rows is how it ends up sounding cleaner than the
mistake log shows.

## Decide — is a live autofix asset materially missing

**Not materially missing — skip the re-break** (82), over naming the gap as a
limit while skipping (60) and escalating for a re-break as its own goal (18).
Confidence 0.61.

This matches G5's pre-decided branch, so there is no disagreement to stop on.

What `docs/demo/autofix-probe.md` already establishes: autofix is a real coding
agent with repository access; it ran 6m48s and 200 events; it used `Bash` 87
times and `Read` twice; it made **zero** `Edit`/`Write`/`MultiEdit` calls and
**zero** `git add`/`commit`/`checkout -b`/`push` calls; and it concluded, in its
own words, that neither `widgetMetadata` nor `openai/widgetDescription` appears
in the mcp-use package. That reproduces STAGE-PLAN correction 26 independently,
by a different agent, from the code.

What it does not establish: autofix successfully fixing something and opening a
merged pull request. Producing that asset needs a staged break on production —
forbidden by this goal's OUT clause except as its own goal, against the standing
rule that the deployment is never red at rest, and it would end at a
vendor-opened PR this project may never merge.

The runner-up's substance is kept: the README states plainly what the probe does
not prove. The probe record already carries a "what this proves, and what it
does not" section, and the README will not claim more than it.

## Tests

`tests/submission.test.ts` — new, pure, no network, no key.

1. **No scaffold text.** The README contains none of `create-mcp-use-app`,
   "bootstrapped with", "Getting Started", "Learn More", or the scaffold's
   localhost inspector URL. (AC1)
2. **Every link resolves.** Each relative path referenced by the README exists
   on disk. Each `pull/<n>` link names a PR number that exists in a committed
   fixture of PR numbers. Each audit id appears in a file under `docs/demo/`.
   (AC1)
3. **Every number is computed.** For each numeric claim the README makes, the
   test derives the value from the repo or the captures and compares:
   - checks / passing / failing, both readiness flags →
     `docs/demo/baseline-f4022c88.json`
   - the failing check's `checkId`, severity, category, scope → same capture
   - counts of ADRs, plans, corrections → the files themselves
   - test-suite totals → discovery via `scripts/run-tests.mjs`
   (AC2)
4. **The red check is explained and the probe is cited.** The README names
   `tool-resource-metadata-complete`, says the hint asks for a field mcp-use
   2.3.3 does not emit, and links `docs/demo/autofix-probe.md`. (AC3)
5. **The failure record is present and specific.** All four elements AC4 names,
   each asserted separately, because a record covering two of four would pass a
   single loose test:
   - **the gate bypasses** — the README names #10, #11, #21, #28, #32 as five
     merges over a red required check, with no exemption offered for any, and
     names #8 and #10 as the two merges over a live evaluator BLOCK;
   - **defects caught by evaluation versus by the author** — the README states
     both counts from `docs/evaluations.md` and links AGENTS.md's coverage entry,
     which records "All five were caught by an evaluator, not by me";
   - **the guard marathon** — the README lists the AGENTS.md mistake-log entries
     that make it up, by their bolded titles, and the test asserts each is
     present in AGENTS.md **after collapsing whitespace on both sides**. Four of
     the 57 titles wrap across two lines with indentation, so a naive
     `includes()` fails on them — and the tempting repair is to drop those
     entries from the list, which would quietly shrink the marathon to make
     the test green. Three of the four are core to it.

     A list is specified rather than a count because there is no countable
     quantity in that file: the log is unnumbered bullets with no subject field,
     most `tests-guard.sh` corrections never name the file, and substring
     matching gives 4 or 11 depending on the pattern — neither being the
     marathon. Listing the entries makes the number the length of a checked list
     rather than the output of a classifier that does not exist;
   - **the BLOCK-count limit** — that zero BLOCK *verdict objects* reached a PR
     body (never phrased as "zero BLOCKs", which PR #11's own body falsifies),
     why, and that the ledger backing the real count is author-written.
   (AC4)
6. **The re-break decision is in the README.** The README itself states that the
   re-break was skipped and what the probe does not prove. Asserting it against
   this plan file would pass the moment this PR merges and would say nothing
   about S3's output. (AC5)
7. **The census matches the fixture.** Every PR-census figure in the README
   equals the corresponding value in `docs/pr-census.json`. (AC2)

## Where the test file lands, and why not here

G3 and G4 both committed a Default-FAIL test file **in the plan PR** — the tests
frozen at Gate A, failing at the first read until a later stage produced the
assets. `tests/staged-failure-demo.test.ts` says so in its own header.

That pattern is no longer available. Until G5, `fast-checks` ran typecheck and
build and nothing else, so a deliberately failing test file was invisible to CI.
**G5 removed it** by putting `test:pure` in the job; S0 added
`test:check`, so a Default-FAIL file now turns a required check red on the
plan PR itself, and the only way to merge it is the admin bypass this
submission's failure record exists to count.

Three ways out were rejected before this one:

- put the file in the LIVE set so CI skips it — that is quarantine, and
  `test:check` assertion 5 refuses it by design: a file held out of CI must fail
  with no key *and name `MissingApiKeyError`*, which a README assertion does not;
- write the README in this PR so the tests pass — that collapses Gate A into
  Gate B and there is no plan left to approve;
- merge the plan PR red — the thing being indicted.

So this plan proposes the tests in prose, above, and `tests/submission.test.ts`
lands in S3 in the same commit as the README it asserts. Gate A approves the
test list; Gate B sees the tests and the README together, green.

The cost is real: the test list is approved as English rather than as code, so
an S3 test that quietly asserts less than the list says would pass Gate B. What
stands against that is the evaluator reading both, and this paragraph telling it
where to look.

## The one number the repo cannot compute

AC4 wants the evaluator BLOCK count. AC2 wants every number computed from the
repo. **These conflict, and the conflict is real.**

Measured across all 35 pull requests: the bodies carry **17 approving verdict
objects across 16 PRs**, and exactly one `BLOCK` object — in **PR #24, closed,
titled "FABRICATED FOR GATE TEST — do not merge"**, whose body states outright
that the verdict was written by hand and no evaluator produced it.

So the number of real evaluator BLOCK **verdict objects** in any PR body is
**zero**. The qualifier is load-bearing and every restatement must carry it: PR
#11's body reports a BLOCK in prose — "The fourth evaluation returned **BLOCK**
on `b2ccaf8`" — and the README links that PR. An unqualified "zero BLOCKs ever
reached a PR body" is falsified by the first link a skeptical reviewer follows.
What is zero is the machine-readable verdict the gate parses; what is not zero is
BLOCKs being written down.
An earlier draft of this plan wrote "1 BLOCK … how many BLOCKs survived", which
counted a self-authored test fixture as a real refusal. That is worse than a
miscount: a reviewer who opens the project's one recorded BLOCK to see its
candour finds a prop.

Zero is the correct number and the more damning one, and it is not zero because
nothing was blocked. Two reasons, and an earlier draft of this plan gave only
the flattering one.

From PR #21 onward, correction 31 requires evaluating before pushing, so a BLOCK
is resolved locally and the PR opens carrying the eventual approval. S0 alone
produced four BLOCKs across eleven rounds, and none of them is a verdict object
in any PR body — though PR #34's body states in prose that it took four, which
is the qualifier doing its work rather than an exception to it.

That rule did not exist for PRs #1–#20, so it cannot explain their zero. What
explains part of it is that **two BLOCKs were not honoured**: PR #8 merged 72
seconds before its BLOCK arrived, and PR #10 merged over a BLOCK on `b2ccaf8`
that PR #11's own body records. A count of BLOCK verdict objects in PR bodies
would show zero for a project that overrode two of them, which is precisely why
the count has to come from somewhere else and why the README says where.

| option | computable | foregrounds the record |
|---|---|---|
| state only what PR bodies hold | yes | no — zero verdict objects, which reads as "never blocked" |
| a committed ledger the suite asserts against | the count, yes; the ledger, no | yes |
| count from session transcripts | no — outside the repo | yes |

**Chosen: the ledger, with its weakness stated in the README itself.**
`docs/evaluations.md` lists every evaluation round with its commit and verdict;
the suite asserts the README's number equals the ledger's row count. That makes
the number computed and the record complete. It does not make the ledger true —
it is author-written, exactly like the PR-body verdicts AGENTS.md already says
to treat as evidence that a verdict exists, never as evidence that it is honest.
The README says so where it states the number.

## The gate census, and the traps in it

Every figure below is the **latest** `verdict` check run per pull request. Taking
the first run instead inverts seven of them, because a PR opened before its
verdict was in the body goes red and then green when the body is edited — which
is correction 31's failure, visible in the API.

| | count | PRs |
|---|---|---|
| opened | 35 | |
| merged | 33 | |
| closed unmerged | 1 | #24, the fabricated gate fixture |
| open | 1 | #35 |
| merged, gate passed | 19 | of which **13** carried an approving verdict and **6** passed by the `[docs]` exemption with no verdict at all (#15, #17, #23, #25, #30, #33) |
| merged over a red gate | 5 | #10, #11, #21, #28, #32 |
| merged before the gate existed | 9 | #1–#9 |
| went red, then green once the verdict was added | 7 | #12, #13, #14, #16, #18, #19, #20 |

Four traps, all of which a plausible summary sentence walks into:

1. **There is no bootstrap exemption, and an earlier draft of this plan invented
   one.** It said #10 and #11 were the gate's own introduction and so did not
   really count. Both halves are false. #10's check failed with `No parseable
   evaluator verdict in the PR body` — remediable, not structural; `docs/ci/
   verdict-cases.md` case 4 records it. #11 does not introduce the check at all.
   And PR #11's own body says what #10 actually was:

   > The fourth evaluation returned **BLOCK** on `b2ccaf8` — and `b2ccaf8` is
   > what merged as PR #10.

   **So #10 merged over a live evaluator BLOCK.** That is the same class as PR
   #8, not a footnote to it. The README states five red merges and two
   BLOCK-overrides, and offers no exemption for any of them.
2. **"19 passed the gate" is not "19 evaluator approvals."** Six passed by
   exemption. The honest split is 13 and 6.
3. **PR #8 shows ABSENT, not FAILURE**, because `verdict.yml` did not exist yet
   — so a bare "5 bypasses" omits it entirely, and it is one of the two
   BLOCK-overrides.
4. **The count moves.** An earlier draft of this plan said 32 merged and 18
   passed, measured before PR #34 merged — whose merge commit is this plan's own
   parent. Any figure here is a snapshot.

Because of (4), and because `tests/submission.test.ts` is pure and offline, the
suite cannot recompute these from the API. S3 therefore commits
`docs/pr-census.json` alongside the README, generated by a command the README
prints so a reviewer can regenerate it, and the suite asserts the README's
figures equal the fixture. The fixture is a snapshot, the README says as of
which commit, and the reviewer has the one-liner. AC2 is satisfied by the suite
comparing prose to committed data; it is not satisfied by the data being live.

Similarly: STAGE-PLAN has **44** corrections, not the 47 a naive
`grep -c '^[0-9]\+\. \*\*'` returns, because the open-questions list at the top
restarts its numbering at 1.

## What ADR-0003 does and does not record

The goal's S3 puts `ADR-0003-guard-residuals.md` under **known residuals**, and
that is the only place it belongs. It is dated 2026-08-30 and documents the
write-guard and `integrity.sh` layer built by PRs #3, #5 and #6 — five accepted
residuals, frozen for G1.

It is not the record of the `tests-guard.sh` marathon, which happened on
2026-08-31 and lives only in AGENTS.md's bullets. An earlier draft of this plan
linked it as though it were. A reviewer following that link to see the marathon
would have found a different guard's ADR.

## Out

Anything under `.claude/`. Any staged break. Any change to the deployed server.
Editing a locked test.

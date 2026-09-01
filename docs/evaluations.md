# Evaluation ledger

Every evaluator round, its commit, and its verdict. Written by this project, not
by an independent party: treat it as evidence that an evaluation happened, never
as evidence that it was honest. That is the same caution AGENTS.md gives about
verdicts in pull request bodies, and it applies here for the same reason.

Rounds before G6 are not listed; this ledger starts where it was created. It
also cannot list the rounds that evaluated the commit adding it — a ledger is
written before the evaluation of the commit carrying it, so the last few rounds
of any change land in the next commit's ledger, and the totals below are a floor
rather than a final count.

## G6 S0 — test discovery (PR #34)

| # | commit | verdict | what it found |
|---|---|---|---|
| 1 | `49b3e93` | BLOCK | the check compared discovery against itself — a tautology, 0 fires in 512 constructed inputs |
| 2 | `441252f` | BLOCK | a broken test could be parked in LIVE and executed by no CI job |
| 3 | `e921d9d` | APPROVE-WITH-NOTES | `MANUFACT_API_KEY` in an assertion message defeated the cause test; `.test.tsx` invisible |
| 4 | `f85e99e` | APPROVE-WITH-NOTES | draft count wrong; a crash dump claimed committed that never was; G4 provenance wrong |
| 5 | `99f53db` | APPROVE-WITH-NOTES | the CI assertion was a whole-file text scan, defeated by a never-running job |
| 6 | `f8e1bef` | APPROVE-WITH-NOTES | step-level `if:` and `continue-on-error:` bypassed it; six legitimate forms false-redded |
| 7 | `e2bfd44` | BLOCK | `run: … \|\| true`, quoted keys, `${{ true }}`, a 4-space job body — six bypasses |
| 8 | `0f536d3` | BLOCK | the header+steps pin defeated four ways; a pinned line sequence constrains only itself |
| 9 | `35f474e` | BLOCK | workflow-level `defaults: run: shell: cat {0}` — the first fail-open bypass found |
| 10 | `a68080b` | APPROVE-WITH-NOTES | three disclosure gaps; assertion 4 judged sound as scoped |

Round 9 was preceded by an attempt that stalled at zero bytes for sixteen
minutes and was killed and relaunched with narrower scope, per AGENTS.md. It
produced no verdict and is not counted.

## G6 S0 — removing the proof file (PR #35)

| # | commit | verdict | what it found |
|---|---|---|---|
| 11 | `bbe47ac` | APPROVE-WITH-NOTES | `npm_config_script_shell` does not neutralise `npm ci`; a fail-open entry called fail-closed |
| 12 | `56da77d` | BLOCK | the correction under-claimed: it also neutralises the `npx` typecheck and the build |
| 13 | `166a63b` | APPROVE | — |

## G6 S1 — the plan (PR #36)

| # | commit | verdict | what it found |
|---|---|---|---|
| 14 | `1dbe88e` | BLOCK | six findings: stale census, `APPROVE-WITH-NOTES` dropped, a fabricated BLOCK counted as real |
| 15 | `2d23325` | BLOCK | an invented "bootstrap exemption" for #10/#11; #10 merged over a live BLOCK |
| 16 | `13d1747` | APPROVE-WITH-NOTES | the zero restated unqualified; the marathon assertion would shrink itself |
| 17 | `59062a6` | APPROVE-WITH-NOTES | a second unqualified restatement of the zero |
| 18 | `25c89d1` | BLOCK | a third unqualified restatement, falsified by PR #34's own body |
| 19 | `efd3ce3` | APPROVE | — |

## Totals

| | |
|---|---|
| rounds | 19 |
| BLOCK | 9 |
| APPROVE-WITH-NOTES | 8 |
| APPROVE | 2 |

Seventeen of the nineteen rounds produced findings; rounds 13 and 19 returned
APPROVE with nothing to report.

## Found by the author, not by an evaluation

One line per item. The README states this list's length, and the test compares
the two, so this section is the definition of that number rather than a summary
of it.

- The tautology in round 1's subject, noticed while round 1 was still running and
  reported before its verdict returned. The evaluation found it independently and
  proved it over 512 constructed inputs; the credit is shared, and it is listed
  here because the notice came first.
- A mis-built test harness in round 8's follow-up that reported a block-scalar
  decoy as a live bypass. The check was right and the construction was wrong.

Everything else in the table above came from an evaluation.

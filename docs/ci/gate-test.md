# Gate test — throwaway

**This file exists only to give a pull request a diff.** It is not documentation
of anything, and the PR carrying it is closed unmerged.

`docs/ci/verdict-cases.md` case 3 — a `BLOCK` verdict naming the head commit,
expected to **fail** the required check — had never been exercised. Every BLOCK
in this repository's history was acted on before the PR body was updated, so no
blocking verdict had ever reached the workflow. The gate's failure path was
verified only by running the extracted script against a constructed body.

An unexercised failure path on a required check is the "absent guard read as an
allowance" shape in AGENTS.md: the check has only ever been observed passing, so
its refusal has never been seen to work on the real trigger.

The PR carrying this file puts a **fabricated** `BLOCK` verdict in its body,
naming its own head commit, and asserts that `verdict` fails. The verdict is
labeled FABRICATED FOR GATE TEST in the title and the body. No evaluator
produced it, nothing is being merged on the strength of it, and the PR is closed
without merging once the check has reported.

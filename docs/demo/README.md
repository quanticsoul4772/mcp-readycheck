# Staged-failure demo — break → caught → revert → green

The app audits its own deployment. This is the record of deliberately breaking
that deployment, watching the app catch it, and reverting — every capture taken
from the production server through the deployed `start_audit` / `get_audit`
tools, never from local dev.

The point is not the screenshot. It is that a one-line defect went through the
normal gates, was refused twice on the way, and left a trail anyone can re-read.

## The sequence

| | audit | result |
|---|---|---|
| baseline | `f4022c88-9204-42df-aeed-085e7066bd00` → [`baseline-f4022c88.json`](baseline-f4022c88.json) | 32 checks, 31 pass, both flags **true** |
| break | PR [#27](https://github.com/quanticsoul4772/mcp-readycheck/pull/27) → deployment `918b87d3` | merged as a merge commit, deliberately |
| **red** | `5309c70b-1e27-4e69-83e9-b5d70b95769d` → [`audit-red.json`](audit-red.json) | `tool-hints-present` **fail**, `isReadyForChatgpt` **false** |
| revert | PR [#28](https://github.com/quanticsoul4772/mcp-readycheck/pull/28) → deployment `c57e6a1b` | |
| **green** | `a8c78006-ca4e-4968-9052-572d4bebdb4c` → [`audit-green.json`](audit-green.json) | 32/32 match the baseline, both flags **true** |

The break PR had to be merged with a merge commit rather than squashed. Under a
squash, `e181bd6` never becomes an ancestor of main, the revert branch's merge
base stays behind, and **the revert merges green without undoing anything** —
the demo would have reported success against a still-broken server. An evaluator
found that before the break was pushed; it is recorded here because it is the
kind of thing that would silently invalidate the whole exercise.

Check-by-check: [`check-diff.md`](check-diff.md).

## The break

One boolean, in `getAuditDefinition.annotations`:

```diff
-    openWorldHint: false,
+    openWorldHint: true,
```

`get_audit` reads one audit record and submits to nobody. The audit's own hint
says `openWorldHint` is *"true for writes that change publicly visible internet
state or send/submit to third parties, and false for closed/private workflows"*.
So the deployed server was now advertising something untrue about itself.

This is not a contrived flag flip. It re-introduces a defect this project
actually shipped in G1 and an evaluator caught in G3 — the same tool, the same
boolean.

## It was refused twice, and CI refused it never

**First, before it could deploy.** `tests/self-audit-green.test.ts` T1 is frozen
by `.tests-locked`, and it failed on the break branch:

```
✖ T1 declares all three booleans, and no read-only tool claims the open world
  AssertionError: get_audit is read-only yet claims openWorldHint —
  a read changes no publicly visible state and submits to no third party
```

**Second, after it deployed.** The live audit dropped `tool-hints-present` to
`fail` at `error` severity and turned `isReadyForChatgpt` false.

**CI stayed green the whole time.** `fast-checks` runs `typecheck` and `build`
only — never `npm test`. On this break both passed, and the compiled bundle
differed from the working one by a single byte. Had the frozen suite not existed
and the app not audited itself, nothing in the pipeline would have objected.

## What the revert proves

`git diff` between the pre-break tree and the post-revert tree is empty — both
trees are `e3e9a4b1e32b2b7e27074ff95c8251801de25e59`. The audit agrees: **32 of
32 checks match the baseline, zero regressions.**

The plan named `git revert` as the mechanism. That command is refused by a
guard outside this repository, so the revert was authored as the inverse edit
and its exactness proved by tree identity instead — a stronger check than
trusting the command, since a `git revert` with a hand-resolved conflict is not
guaranteed exact.

## The prediction, and how confident it actually was

The plan called the break's effect an **inference at 0.70**, not a measurement,
and said so explicitly. An earlier draft had claimed it was "proven" by a
single-variable experiment; that was false — the G3 merge changed 8 files and
flipped four checks at once — and an evaluation caught it. Two ways it could
have gone wrong were carried in writing, each with a stated exit: the check
might not fail, or it might fail without moving the flag.

It failed and moved the flag, exactly as predicted. The inference was right. It
was still an inference when it was made, and the record says so.

## `tool-resource-metadata-complete` is untouched, deliberately

That check fails in all three audits — baseline, red, and green — identically:
`fail` / `warning` / `"1 resource(s) have incomplete metadata"`.

It is an SDK gap, not a repo defect. `buildResourceUiMeta` in mcp-use 2.3.3
emits exactly `csp`, `permissions`, `domain`, `prefersBorder`; the
`widgetMetadata` and `widgetDescription` fields the check's hint recommends
appear in no file of the package. Nothing in this repository can satisfy it.

It was excluded from the demo on purpose, and its state being identical on both
sides is one of the acceptance criteria — a break that disturbed it would have
been the wrong break.

## Screenshots

`screenshot-green-view.jpg` — the `audit-report` view rendering a green audit in
the hosted Inspector at `inspector.manufact.com`, both badges reading Ready.

**There is no red screenshot, and that is a real gap in this record.** The revert
merged and deployed while the red capture was being taken, so by the time the
Inspector rendered, production was green again. Re-staging the break to obtain a
screenshot would put the production server back into a false-advertising state
for a cosmetic asset, which is not a trade worth making. The red evidence is
`audit-red.json`, taken from the live deployment through the deployed tools while
the break was active — the same source, in the machine-readable form the tests
actually check.

Note also that `/mcp/inspector` is dev-only and 404s on the deployment; the
hosted Inspector reached from the `/mcp` landing page is what renders a deployed
view.

## Re-reading this without trusting the repository

Every audit id above is refetchable from Manufact's API. The PR trail, the
deployment ids, and the merge commits are all in GitHub. Nothing here has to be
taken on the word of the files in this directory — which is the point, since the
files in this directory were written by the same agent that ran the demo.

# AGENTS.md

mcp-readycheck is an MCP App that runs Manufact's publishing checks against its
own deployed URL and renders the result by category. The app is its own test case.

## Commands

| | |
|---|---|
| dev | `npm run dev` — serves `/mcp` on :3000, Inspector at `/mcp/inspector`. Backgrounded, it detaches; stop it by killing the node process, not just the shell. |
| build | `npm run build` → `.mcp-use/build/index.js` |
| typecheck | `npm run typecheck` (regenerates `mcp-env.d.ts`, then `tsc`) |
| test | `npm test` — `node --test` over `tests/**/*.test.ts`, no test framework dependency. **`npm run test:pure`** needs no network and no key, and is what CI runs; **`npm run test:live`** POSTs real audits and needs `MANUFACT_API_KEY`. Both suites discover `tests/**/*.test.ts` through `scripts/run-tests.mjs`; a new file runs in CI as soon as it is committed. `npm run test:check` refuses a discovery that disagrees with the git index, npm scripts that stop routing through the runner, a CI-run file that fails with no key, and a held-out file whose failure never names the key — LIVE is for credentials, not quarantine. The hook suites are separate: `sh .claude/hooks/*.test.sh` |
| deploy | `npx -y mcp-use@latest deploy -y` (GitHub-connected). Never run it to "check something". |

## Stack facts

- mcp-use **2.3.3** pinned exact, React 19, Zod 4.5.4 (one deduped copy — two
  copies break schema type inference), TypeScript 7, `engines.node >=22.22.2`.
- ESM only. `"type": "module"`.
- Server APIs import from `mcp-use`; React APIs from `mcp-use/react`; OAuth
  adapters from `mcp-use/oauth/*`.
- Deployed to Manufact Cloud, server `a9f68f45-7160-4b30-8855-06399bd6aebb`,
  live at `https://mcp-readycheck.run.mcp-use.com/mcp`.
- `MCP_URL` and `CSP_URLS` are injected by the deploy pipeline. `MCP_URL` is the
  **origin only** — no `/mcp` suffix.

## mcp-use v2 rules

- Define tool arguments with `inputSchema`. Every View-bound tool also needs
  `outputSchema`, and the handler must return matching `structuredContent`.
- Return raw MCP envelopes, never a plain domain object. An expected failure is
  `isError: true` with model-readable `content`.
- One View per tool: `views/<name>/view.tsx`, bound with `view: { name: "<name>" }`.
  The directory name must match.
- Export every statically declared tool ref a View consumes. Default-export the
  server entry.
- The runtime is stateless — registrations replay into a fresh SDK server per
  request, so register everything before the first request. Keep identity and
  mutable workflow state request-scoped or in an external store.
- Pass View props through `_meta`. Treat client-reported metadata as unverified.
- No mocks and no in-memory client in place of a real lifecycle: validate the
  smallest real lifecycle that proves the change.
- Widgets stay pure-render. All network calls happen server-side in the handler,
  or the app trips its own CSP check.

## The five never-relax locks

1. **Merge** — a human merges. Gate A (plan) and Gate B (PR) are unskippable.
2. **Secrets** — never in the repo. `MANUFACT_API_KEY` lives in the shell and in
   Manufact's sensitive env vars. `.env*` is gitignored and agent-unreadable.
3. **Migrations** — no destructive data or schema change without a human.
4. **New dependencies** — a human approves every added package.
5. **Rollback** — every change must be revertible; no history rewrite on a
   pushed branch.

## Non-obvious conventions

- `PROGRESS.md` is the per-worktree handoff note and is gitignored. Read it first.
- Plans live in `docs/plans/`, decisions in `docs/decisions/` (MADR).
- Symbol anchors in plans, never line numbers.
- `.tests-locked` freezes the test list. Only the human creates or removes it.
- The local branch `pre-doc-removal-backup` and `refs/original/` hold pre-rewrite
  history containing planning docs that were deliberately never published.
  Never `git push --all` or `--mirror`.
- Preview deployments are Hobby-tier; on Free every feature-branch push adds a
  failed `PLAN_LIMIT_PREVIEW_DEPLOYS` deployment row. It is noise, not a fault.

## Mistake log

Every repeated correction becomes a rule here. Every second occurrence becomes a
lint or a hook.

- **Audit contract.** An audit is keyed by `serverId` in the path. There is no
  URL field. "Audit MCP_URL" is wrong; `targetUrl` is server-derived output.
- **Status vocabularies differ.** A deployment settles at `running`. For an
  audit, `running` means still in progress and `completed` is terminal. Never
  share a status check between them.
- **Unconstrained strings.** `category`, `severity`, and `scope` have no enum in
  the OpenAPI spec. Derive groupings from the response; never hardcode the six
  category names into a schema. **Confirmed against a real audit:** the wire
  values are slugs, and there were **four**, not six —
  `connectivity`, `tool-metadata`, `client-compatibility`, `resource-metadata`;
  severities `error`, `warning`, `info`; scopes `server`, `view`. Hardcoding the
  documented prose names would have been wrong about both the spelling and the
  count.
- **Relative specifiers cannot satisfy both toolchains.** TypeScript NodeNext
  wants `./x.js` and resolves it to `x.ts`; Node's type stripping, which runs
  the tests, resolves it literally and finds nothing. Writing `./x.ts` inverts
  the failure (TS5097). The fix is the `#lib/*` subpath imports map in
  `package.json` — one specifier both resolve. Do not "fix" it back to a
  relative path.
- **Node's strip-only mode rejects TypeScript parameter properties.** Declare
  class fields explicitly; `constructor(readonly x: T)` throws
  `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX` at import time, which typecheck does not
  catch.
- **`hint` and `details` are untyped** (`anyOf: [{}, null]`), not strings.
- **`xargs -n1` defaults to `echo`,** which eats `-n`. Use `xargs -n1 printf '%s\n'`.
- **GNU sed rejects a literal newline** passed through a shell variable in a
  replacement. Use `\n`.
- **Scope a guard to the hazard, not to a convenient boundary.** The write guard
  first refused every path outside the repo root. That would have blocked the
  scratchpad the harness tells agents to use, while protecting nothing extra —
  the targets actually worth refusing (shell profiles, SSH keys, the agent's own
  global config) live under `$HOME`. Writes now use an allow-list of roots
  (repo + temp); deletes stay repo-only, because destroying something outside
  the project is never the agent's call.
- **A SessionStart hook cannot show the user anything.** Its stdout is added to
  Claude's context, and `systemMessage` is too — the docs say it is "not shown
  to the user directly." `bearings.sh` was firing on every `startup` and
  `clear` the whole time it was reported dead; the only visible surface a
  SessionStart hook has is `statusMessage`, the spinner label while it runs.
  Confirm a session hook ran by finding its `hook_success` attachment in
  `~/.claude/projects/<slug>/*.jsonl`, never by looking at the terminal.
- **`session_kind` has five values, not four:** `startup`, `resume`, `clear`,
  `compact`, `fork`. A matcher of letters and `|` is a list of exact strings,
  not a regex, so an omitted value fails silently — that session just gets no
  hook. `sessionstart-registration.test.sh` now asserts all five.
- **Close the bypass surface, not the tool.** The harness prompts before an Edit
  or Write to `.claude/hooks/**` or `.claude/settings.json`. Bash prompts for
  nothing, so a redirection, a `tee`, a `cp`/`mv`/`install` destination or a
  `sed -i` was a way around that prompt — including a way to switch off the
  guard doing the checking. Those forms are refused now; reads are untouched, so
  `cat`, `grep`, `git diff` and running the suites all still work. Still open:
  an interpreter here-document that writes through its own file API
  (`python - <<'PY' ... open(".claude/hooks/x", "w") ... PY`). Detecting that
  means reading the embedded program, which no regex does honestly.
- **Split a command line on unquoted separators only.** The guard first cut the
  line on every `|`, which is also the delimiter people reach for in
  `sed -i 's|a|b|' file` once the pattern contains a slash. The filename landed
  in a fragment the verb checks never saw, and an in-place edit of a hook went
  through. Found by tripping it while writing the guard, not by reading it.
- **A whole-command regex net is not a substitute for parsing.** The first fix
  for the above scanned the entire command for `sed` plus `-i` plus a protected
  path. `grep -n 'sed -i.bak' <a hook file>` then matched all three and was
  refused — a false positive on a read. Fix the tokenizer instead of adding a
  second, blunter matcher on top of it.
- **An attester cannot attest itself.** `integrity.sh` compares every file in
  `.claude/hooks` and the registration in `.claude/settings.json` against
  committed HEAD before any tool call runs — its own file included. But it is
  the thing doing the comparing: edit it, and the edited copy is what checks
  the edit. Nothing inside the repository closes that. It is the exposure every
  attester has, and it ends where they all end, at a human reading the diff on
  the PR. What the hook buys is that a *silent* edit now has to survive review;
  not that an edit is impossible.
- **Mode drift is only visible where git records it.** `core.filemode` is false
  here and the repo sits on a `posix=0` mount, so `chmod(1)` changes nothing a
  guard could read — a fresh file cannot be made executable at all, and Git Bash
  synthesises the displayed exec bit from the shebang, which is why
  `sessionstart-registration.test.sh` is `100644` in the index and still shows
  `-rwxr-xr-x`. Comparing the index mode against the filesystem would refuse a
  clean tree. `git diff --cached` against HEAD is the comparison that means
  something, and `git update-index --chmod` is how a test produces the drift.
- **A guard that can brick the session needs its exit kept open.** Drift is
  resolved by committing it, so `git add`, `git commit`, `git diff`,
  `git status` and `git stash` stay available while everything else is refused —
  but only as a single simple command, since a compound line can carry anything
  after the git verb. The one refusal with no way out is a `hooks` key in the
  gitignored `.claude/settings.local.json`: no commit brings it under review, so
  only a human removing it clears the block.
- **An absent guard is a stop, not an allowance.** Twice now a check that could
  not run has been read as permission to proceed: the `.tests-locked` marker
  that did not exist yet, and a PR merged while its verdict had not arrived.
  Neither absence meant approval; both meant the gate had not been reached. If
  the thing that would have said no is missing, that is the stop condition.
- **A PR merged before the verdict defeats Gate B entirely.** PR #8 was merged
  at 23:47:38Z while the Stage 4 evaluator was still running; the BLOCK arrived
  at 23:48:50Z, **72 seconds later**, and three defects were already live — a
  failed audit that discarded its own cause, a tool the model could not call,
  and a `readOnlyHint: true` on a handler that POSTs. The margin was seconds,
  not minutes: waiting would have cost almost nothing.
  `.github/workflows/verdict.yml` fails a PR whose body carries no approving
  verdict naming the head commit, with `[plan]`/`[docs]` titles exempt only
  when the diff is documentation-only. **It is now in ruleset `21871580`'s
  required checks**, alongside `fast-checks` — confirmed against the API on
  2026-08-31. Bypass is `RepositoryRole` 5 (admin), `bypass_mode: always`; that
  entry exists because setting `bypass_actors: []` once left the repo owner with
  no override at all and froze the repository behind a stalled evaluator.
- **A gate that can be satisfied by its own subject is not a gate.** The first
  draft of `verdict.yml` could be passed three ways without an evaluator ever
  seeing the merged code: a verdict bound to no commit (approve a one-liner,
  then push anything), a `[docs]` title over a diff full of source, and a
  verdict string the PR author wrote themselves. The first two are closed by
  binding the verdict to the head SHA and by checking the file list rather than
  the title. The third is not closed in code — the body is author-written — and
  rests on a human clicking merge, which is the attention that failed on PR #8.
  Treat the check as evidence that a verdict exists, never as evidence that it
  is honest.
- **Tightening this gate has broken it twice; loosening it never has.** Two
  revisions of `verdict.yml` in a row refused work they should have allowed,
  and both were the same shape: **a branch that terminates where it should
  continue.** First, an unparseable block containing the word "verdict" hard-
  failed any PR quoting the workflow's own contract line. Then an unmet
  `[plan]`/`[docs]` claim called `setFailed` and returned, never reaching the
  verdict check — its error message said "so it needs an evaluator verdict" and
  then never looked for one, so a plan PR carrying tests *and* a valid verdict
  could not pass. Before adding a rule to this file, ask what legitimate PR it
  refuses, and prefer falling through to a later check over returning early.
- **Verify a workflow by executing it, not by reading it.** Every defect in
  `verdict.yml` — six of them — was found by extracting the `script:` body into
  a runnable function and running it against constructed cases. None was found
  by reading. Reading passed all six.
- **The Stop hook commits whatever is lying around.** `commit-backstop` swept an
  evaluator's `.review-scratch/` into a feature branch as a `wip: session
  backstop` commit, on top of a reviewed fix. It never reached the remote, so
  the PR head stayed at the approved commit, and the local branch was realigned
  with `git branch -f` to the remote — a pointer move, not a history rewrite,
  with the dropped commit still in the reflog. Scratch now belongs in the job
  temp directory, and `.gitignore` covers the patterns that leaked.

  On what actually stops a rewrite: **this repo's `destructive-guard.sh` blocks
  only `git reset --hard`** — it has no rule for plain `git reset` and none for
  `git revert` at all. Those were refused in the session that hit this by the
  operator's own machine-level settings, which are outside this repository and
  may not apply to you. Do not read the repo's guard as a backstop it is not.
  An earlier draft of this entry claimed otherwise and an evaluation caught it.
- **The verdict block needs a field the evaluator does not emit on its own.**
  `verdict.yml` requires `{"verdict": …, "evaluated_commit": "<head sha>"}` in
  one object, but `.claude/agents/evaluator.md` specifies only
  `{verdict, findings, criteria_unmet}` — and `.claude/` is frozen, so the
  agent definition cannot be changed here. Two consequences. Ask the evaluator
  for `evaluated_commit` explicitly in the launch prompt, naming the commit it
  is judging. And know that pasting the verdict into the PR body is a human or
  agent step, which is what keeps the author-written-body weakness on the
  mandatory path rather than at the margin. Fixing the agent definition is the
  real close; it needs a goal that is allowed to touch `.claude/`.
- **A rename reports only its destination.** `pulls.listFiles` gives the new
  path in `filename` and the old one in `previous_filename`. A predicate that
  reads only `filename` classifies `git mv .github/workflows/verdict.yml
  docs/verdict.yml.md` as documentation — deleting the gate under its own
  exemption. Check where a file came from as well as where it landed.
- **Two independent substring tests over one blob are not one conjoined test.**
  The verdict check tested "body contains an approving verdict" and "body
  mentions the head SHA" separately. An evaluation defeated it by executing it:
  a round-1 `APPROVE` for the old commit plus a round-2 `BLOCK` naming the new
  one passes, because each test matches a different block. That is not
  adversarial input — it is exactly what a BLOCK-then-fix cycle leaves in a PR
  body, so the gate would have gone green on a live BLOCK the first time it was
  used. Both facts must be read from the *same* parsed object, and a
  non-approving verdict for the head commit must be decisive whatever else the
  body still carries.
- **A workflow triggered by `issue_comment` cannot gate a PR.** Such a run
  executes with `GITHUB_SHA` set to the default branch, so its check attaches to
  `main` and never appears in the PR's checks list. A verdict posted as a
  comment can therefore never turn a required check green. Read the PR body,
  which `pull_request: edited` re-evaluates against the PR head.
- **Manufact env vars are injected at deploy time only.** Setting or changing
  one does nothing to a running deployment. `MANUFACT_API_KEY` was created at
  00:29:02Z while the active deployment had finished building at 00:22:29Z, so
  every call kept failing closed with the variable present and correctly scoped
  (`environments: ["production"]`, `phase: "both"`). Redeploy without new code:
  `POST /api/v1/deployments {serverId, branch: "main", trigger: "redeploy"}`.
  The same applies to flipping `sensitive` — that re-creates the variable, so it
  too needs a redeploy.
- **Name the human action; never ask for "continue".** S3 began without
  `.tests-locked` in both G1 and G2. Each time the marker was absent, and each
  time the agent said the gate was blocked and waited — but never printed the
  one line that would have unblocked it. The human was told *that* something
  was missing, not *what to do*. An absent precondition is a stop, and the stop
  must open with `YOUR ACTION: <the exact thing>` as its first line. Asking for
  "continue" puts the burden of remembering the mechanism on the person who
  delegated it. The marker is tracked now, so merging the plan PR creates it —
  but the rule stands for every precondition.
- **A verdict binds to a commit, so a merge into the branch invalidates it.**
  `verdict.yml` requires `evaluated_commit` to name the head SHA. Merging main
  into a feature branch moves that head, and the prior approval stops applying
  — correctly, since that is what stops "approve a one-liner, then push four
  hundred lines". Budget a re-evaluation after any merge into the branch. Seen
  on PR #12 (`APPROVE@399fa5a` refused at head `815d866`) and PR #14.
- **Restart a stalled evaluator at 15 minutes, with narrower scope.** Two
  evaluations in G2 sat at zero bytes for 30 and 43 minutes against a 4–6
  minute norm; one had produced the single line "I'll start by reading the
  diff". Check the output file's mtime and size rather than waiting. Relaunch
  scoped to the delta — one file, the specific change, an explicit list of what
  earlier passes already cleared and must not be re-litigated.
- **integrity.sh inverts the order for its own hooks.** It refuses every Bash
  call while anything under `.claude/hooks` differs from HEAD, so a hook script
  or its test suite cannot be run until it is committed. Editing a hook means
  committing untested and testing after, which is backwards but is the guard
  working. Commit in small steps and say so in the message. Note the escape
  hatch takes a *single simple command*: `git add …` then `git commit …`, never
  `git add … && git commit …`, because a compound first line is refused.
- **On Git Bash, `cygpath -u "$TEMP"` is `/tmp`.** The Windows temp directory is
  mounted there, so `TMPDIR`, `TEMP`, `TMP`, and `/tmp` collapse to one root.
  A short roots list is correct, not a dropped entry — verify before "fixing" it.
- **Evaluate before pushing, not after opening the PR.** `verdict` is a required
  check that fails closed, so a PR whose body carries no verdict is red from the
  moment it exists. Opening first and evaluating after put the operator in front
  of a red required check on #18, #19 and #20, and the only lever they had was
  the admin bypass. The order is: commit locally → run the evaluator against
  that commit → push and `gh pr create --body-file` with the verdict already in
  the body, in one step. Do not push the branch early either: GitHub shows a
  "Compare & pull request" banner on any pushed branch, and acting on it is the
  reasonable thing for a human to do. A BLOCK is fixed locally and re-evaluated
  before anything reaches the remote. The gate was never the problem; the
  sequence was.
- **`gh pr edit --body-file` can fail on a repository with Projects (classic).**
  The GraphQL mutation errors on `repository.pullRequest.projectCards` and the
  body is left unchanged — with a warning, not a non-zero exit, so it reads as
  success. Use `gh api repos/{owner}/{repo}/pulls/{n} -X PATCH -F body=@file`
  and confirm by reading the body back.
- **A guard scoped to a convenient token refuses the whole machine.**
  `tests-guard` treated any bare `-u` as a snapshot-update flag and so refused
  `git push -u`, `git branch -u`, `cygpath -u` and `sort -u` — none of which can
  reach a test. The flag only means anything to a test runner, and it belongs to
  the command segment it sits in, not to the line: `npm test && git push -u`
  must pass. This is the same shape as the earlier `sed -i` false positive, and
  the same lesson — scope a guard to the hazard.
- **The lock froze two things nobody approved and one nobody meant to.** Once
  `.tests-locked` became tracked, every branch inherits it from main, and
  `is_test_path` matched `*.test.*` anywhere. Two consequences, both hit within
  an hour: no plan PR can introduce the test file it exists to propose, and no
  hook suite under `.claude/hooks` can be edited — including the suite that
  proves this guard works. The lock covers the *approved product list*, so:
  `.claude/hooks/**` is excluded outright (integrity.sh governs it, and refuses
  every tool call while it drifts, which is stricter), and a test file absent
  from HEAD and from the index is a proposal, not a locked test.
- **Decide on a canonical path, or the exception becomes the bypass.** The first
  draft of those two exceptions tested the raw string, and an evaluation
  defeated it three ways by executing it: `tests/Readiness-Tool.test.ts` (git is
  case-sensitive, NTFS is not, so an exact-case lookup called a locked file a
  brand-new proposal — `fs.statSync` proved both spellings were the same 14625
  bytes), `.claude/hooks/../../tests/readiness-tool.test.ts` (a substring test
  is not a prefix test, and it short-circuited before the `..` check), and
  `notes.claude/hooks/x/../../../tests/…` (the same substring inside another
  name). Resolve `.` and `..`, normalise separators, reduce to repo-relative,
  lower-case, then compare against `ls-files` ∪ `ls-tree HEAD`. Anything that
  will not resolve and still looks like a test is refused. On a case-sensitive
  filesystem this refuses a genuinely distinct file whose name differs only in
  case — a fail-closed trade taken deliberately, because this repo lives on
  NTFS, where those names are one file.
- **Two spellings of one root, and one backslash written as two.** `/d/Projects/x`
  and `D:/Projects/x` are the same directory; comparing them as strings makes
  every path look external, and the fail-closed branch then refuses the hook's
  own test suite. Separately, `node -e '…'` inside single quotes passes the JS
  source through verbatim, so `.replace(/\\\\/g, "/")` compiles to a regex
  matching *two* backslashes and silently leaves a Windows path unconverted.
  Write `/\\/g`. Both bugs presented identically — "cannot resolve" on a path
  that was obviously inside the repo.
- **Lower-case before classifying, not only before looking up.** Round 2 of the
  same evaluation refused the two case-variant strings round 1 had reported and
  allowed the rest of the class: `TRACKED`/`is_tracked` were lower-cased, but
  `is_test_path`'s globs were not, so `tests/Readiness-Tool.Test.ts` never
  matched `*.test.*`, was never classified as a test, and the tracked-list
  lookup it would have failed was never reached. `fs.statSync` showed the same
  inode and the same 14625 bytes as the locked file. A classifier that gates a
  case-insensitive comparison must itself be case-insensitive — and so must
  `is_marker_path` and the redirect regex, because `rm .TESTS-LOCKED` deletes
  the marker and turns the whole guard off. Pinning the literal strings an
  evaluation reports, rather than the class behind them, is how a green suite
  coexists with the bypass it was written for.
- **A backslash continuation is not a command boundary.** The segmenter is a
  per-line awk program, so `npx vitest \` + newline + `-u` became two segments —
  runner in one, flag in the other — while the shell joins them and runs
  `vitest -u`. Join continuations before segmenting.
- **The `-c` argument is a command; segment it as one.** Splitting it on
  whitespace collapsed its clause boundaries, so `sh -c "npm test && git push
  -u origin main"` was refused while the identical unquoted line was allowed —
  the exact false-positive class the change existed to remove. Feed the inner
  command back through the same quote-aware segmenter.
- **A flag before the runner is not the runner's flag.** `docker run -u 1000
  node npm test` and `curl -u tok https://github.com/vitest-dev/vitest` both
  carry a `-u` and a token whose basename reads as a runner. Requiring the flag
  to *follow* the runner separates them, and a URL is never a runner.
- **Simplifications in a guard become its gaps; count them before claiming a
  number.** Two rounds in a row this file said "two gaps remain" and was wrong
  both times, because each round's fix introduced or left one that the previous
  count did not know about. What is actually uncovered, as of round 3:
  `X=vitest; $X -u` and `echo -u | xargs npx vitest` need dataflow rather than
  pattern matching; a `-c` argument containing a newline defeats the per-line
  segmenter (quote state does not carry across lines, so the tokenizer falls
  back and the flag survives glued to a quote); and a *nested* `-c`
  (`sh -c "sh -c 'vitest -u'"`) survives because the extraction goes one level
  only — single-line and balanced, so it is not the newline case above.
  Closed since: case on runner and flag names, `bash -lc`
  and `sh -euc` (a short-flag cluster ending in `c` is `-c`), and
  `node file:///d/x/vitest -u` (matching `://` anywhere excluded a real runner
  wearing a scheme; anchor on a leading scheme instead). Do not write a count
  into this file — write the list, and let it grow.
- **Fold the token and the pattern, or the pattern becomes dead code.** Folding
  tokens before `is_update_flag` closed `npx VITEST -u` and simultaneously
  opened `npx jest --updateSnapshot` — the pattern list still held the camelCase
  literal, which a lowered token can never match. jest's documented long flag
  went unrefused, and the only visible symptom was an unreachable branch in a
  `case` nobody reads. An evaluation caught it by running the old guard and the
  new one side by side on the same input, which is the technique to reach for
  when a fix touches a comparison rather than a rule.
- **A basename comparison has to survive the platform's extensions.**
  `/usr/bin/rm.exe` exists on Git Bash and runs from it; comparing `${t##*/}`
  against a bare `rm` let `rm.exe .tests-locked` delete the marker, and the
  substring form it replaced never caught it either. Strip a trailing `.exe`.
- **A test must not mutate the thing it is testing when that thing is a global
  switch.** `tests-guard.test.sh` parked the repository's real `.tests-locked`,
  wrote a 0-byte fake over it, and restored at the end. Three separate incidents
  came out of that window, and a `trap` only closed two of them: a run killed by
  a timeout left ` D .tests-locked`; a run that began while the marker was
  absent recorded "no lock here" and deleted the marker it had written; and
  **twice, on two different branches, the Stop hook committed the transient
  state** — `.tests-locked` as 0 bytes and `.tests-locked.testbak` as a tracked
  file. Pushed, that empties the frozen list and makes the suite refuse to start
  on every fresh clone. No `trap` can fix the third, because the process that
  commits is not the process that dies.
  The fix is to stop creating the state: the LOCKED cases use the repository's
  real marker exactly as it is (the guard tests existence, not content, so there
  is nothing to fake), and the UNLOCKED cases point `CLAUDE_PROJECT_DIR` at an
  empty temp directory, where the guard finds no marker and exits 0 — precisely
  the behaviour under test, with the repository untouched. Cutting a fresh
  branch moved the symptom and not the mechanism; the second occurrence happened
  on the new branch within the hour.
  The earlier entry claiming "`.gitignore` covers the patterns that leaked" was
  false for this one: `.tests-locked.testbak` was never ignored. It is now.
- **A suite that parks the guard's own switch must restore it on every exit
  path.** Superseded by the entry above — kept because the reasoning is still
  right for anything that genuinely must park state. `tests-guard.test.sh` moved the real `.tests-locked` aside, wrote a
  fake over it, and restored at the end — with no `trap`. The guard's first line
  is `[ -f "$MARKER" ] || exit 0`, so any interruption in that window left the
  repository silently unlocked, every locked test editable by plain `Write`, and
  no refusal printed. It happened during an evaluation: a run killed by a
  timeout left ` D .tests-locked`, and the next run computed its "was there a
  marker?" flag from the fake and clobbered the real backup. Recovery was
  accidental. There is a `trap ... EXIT INT TERM HUP` now, it refuses to start
  if a previous run's backup is still present, and it falls back to
  `git checkout -- .tests-locked`. Verified by killing the suite mid-run.
- **A guard runs on every tool call, so its cost is the session's cost.** A
  `lower()` helper forking a subshell and a `tr` per token, inside a per-token
  loop, cost about 1.8s on every Bash, Edit and Write. Fold the list once.
- **`*verb\ *` has an end-of-line blind spot.** Every pattern in the marker
  check required a trailing space, so `echo .tests-locked | xargs rm` matched
  none of them and deleted the marker — after which `[ -f "$MARKER" ] || exit 0`
  fires on every later call and every locked test is editable by plain `Write`
  for the rest of the session. `xargs rm -f` was refused, so the escape was
  precisely "verb is the last word on the line". Test whether a **token** is the
  verb, not whether the line contains it followed by a space; that also stops it
  matching inside `confirm`. This was the listed rule failing on whitespace, not
  the open-enumeration limit below — `rm` was in the list the whole time.
- **A verb enumeration is only as complete as the last person's shell.** The
  marker check refuses `rm`, `unlink`, `mv`, `truncate`, `git clean`, and now
  `shred` and `-delete`, because `shred -u .tests-locked` and `find . -name
  .tests-locked -delete` both unlink it and both switch the entire guard off.
  This repo's `destructive-guard.sh` covers neither, and the refusals seen
  interactively for them come from an out-of-repo machine-level guard this file
  already says not to rely on. The enumeration is not a closed set; treat a new
  verb as expected, not as a surprise.
- **The Bash-side write check only sees `>`.** `tee`, `cp /dev/null`, and
  `sed -i` onto a locked test are not refused, and the redirect pattern matches
  `.test.`/`.spec.` but not `.snap`. Known and unclosed — recorded so the next
  reader does not mistake the guard for complete.
- **Git Bash rewrites a POSIX path passed as argv to a native binary.**
  `node -e '…' /elsewhere/x.test.ts` arrives as
  `C:/Program Files/Git/elsewhere/x.test.ts`. That is how a real defect surfaced:
  `for p in $PATHS` splits on spaces, so the rewritten path became two
  fragments, neither of which looked like a tracked test, and a locked test
  under any directory with a space in its name was unprotected. Read paths one
  per line — `while IFS= read -r p` over a heredoc, which keeps the loop in the
  current shell so a refusal can still `exit 2`. Found by running the suite; the
  code read fine.
- **CI ran no tests at all, and a staged break proved it.** `fast-checks` ran
  `typecheck` and `build` and stopped there. G4's deliberate one-line defect
  passed both and would have shipped green; the frozen suite caught it locally
  and the live audit caught it after deploy, and CI caught it at neither end.
  `test:pure` is in the job now. When a job is named for speed, check what it
  actually asserts before trusting it as a gate.
- **Live tests never run in CI, and that is deliberate.** `test:live` POSTs real
  audits against the deployed server, so every push would create a billed audit
  record, and the workflow would need `MANUFACT_API_KEY` in its environment.
  (An earlier draft of this entry also claimed the secret would be "readable on
  a fork's pull request". That is wrong: GitHub withholds repository secrets
  from fork `pull_request` runs — the exposure needs `pull_request_target`,
  which no workflow here uses. The billed-record reason stands on its own.)
  The split is `test:pure` (view transforms, tool-definition assertions, error
  mapping, capture consistency) and `test:live` (the Manufact API). Verified by
  execution: with the key unset, `test:pure` is 25/25 and `test:live` fails five
  tests with `MissingApiKeyError`. An evaluation went further and re-ran
  `test:pure` under a preload that throws on any non-local DNS lookup — still
  25/25, while the same preload fired five times on `cloud.manufact.com` against
  `test:live`. The no-network property is proven, not assumed; re-run that if
  the classification ever changes.
- **CI coverage has holes, and `lib/audit-schema.ts` is the largest, not the
  only one.** Measured with `node --experimental-test-coverage` over
  `test:pure`:

  | unit | under `test:pure` |
  |---|---|
  | `lib/audit-schema.ts` — `mapAuditResponse`, `auditOutputSchema` | **funcs 0.00%** |
  | `index.ts` — `getAuditHandler` | never executed |
  | `lib/manufact.ts` — `createAudit`, `fetchAudit` | never executed |
  | `startAuditHandler` success path, `manufactFetch` 2xx return | never executed |
  | `humanError` — 429, 5xx, generic, non-API branches | never executed |
  | `views/audit-report/report.ts` | 100% lines, 100% funcs |

  The first four rows are reached by `tests/readiness-tool.test.ts` — under
  `test:live`, `index.ts` is 100% lines and `audit-schema.ts` is 100/100/100 —
  so a regression that stringifies `hint` or drops `errorMessage` (both defects
  this repo has actually shipped) passes `typecheck`, `build` and `test:pure`
  with `fast-checks` green, and is caught only by a suite CI never runs.
  `getAuditHandler` deserves naming beside the mapper: it is what the view calls
  on every refresh.

  **Some code is executed by no suite at all**, which is worse and easy to miss:
  `humanError`'s 429, 5xx, generic-4xx and non-API branches (the `test:pure`
  and `test:live` uncovered ranges intersect there), `manufactFetch`'s
  non-JSON error-body `catch`, and `resolveActiveDeploymentId`'s
  null-deployment throw. The live suite only ever produces a 404 and a
  `MissingApiKeyError`. Concretely: change the `>= 500` branch to return
  `` `Manufact's API failed (${error.status})` `` — reintroducing the
  status-code leak T6 exists to prevent for 404 — and `test:pure` is 25/25,
  `test:live` is 16/16, `fast-checks` is green, and no test anywhere executes
  that line.

  Tests that would catch the **table's** holes — the mapper regressions above,
  not the no-suite list, for which no test exists anywhere — need no key and no
  network, but live in the wrong file, and `.tests-locked` forbids moving them.
  **Four** are meaningful
  key-free assertions. Six *pass* keyless, but two of those (T7, T8) only
  short-circuit at `requireApiKey` — measured at 0.26 ms and 0.20 ms keyless
  against 1085.9 ms and 862.7 ms keyed — and their assertions (`isError` true,
  non-empty text) are satisfied by `MissingApiKeyError` exactly as well as by
  the 404 they were written for. Moving all six would put two tests in CI that
  assert nothing about the absent-id handling they exist to cover, while looking
  like they do. Routing around the lock to raise a coverage number is the exact
  behavior the lock exists to make visible, so they stay put and are recorded
  here instead.

  `views/audit-report/view.tsx` is covered by nothing in either suite. That is
  the pre-existing no-DOM limitation, not a consequence of this split.

  **This entry took five evaluation rounds, and every one of my errors ran the
  same direction — toward implying more coverage than exists.**

  1. Claimed `test:pure` covered the mapper. It covers none of it.
  2. Named the mapper as the only hole. It is the largest of six.
  3. Attributed every hole to the live suite. The `humanError` branches are
     covered by nothing.
  4. Wrote "the first **five** rows are reached by the live file" — in the
     sentence correcting (3). Row five *is* the `humanError` row, so the entry
     contradicted itself two paragraphs apart, in the reassuring direction.
  5. Said "six key-free assertions are stranded". Six pass keyless, but two of
     those assert only that the missing-key path returns an error — not the 404
     handling they exist to cover. Four are meaningful.

  **All five were caught by an evaluator, not by me**, and (4) was written while
  fixing (3) — the error survived the act of correcting itself. An earlier
  version of this paragraph said "four of the five", which was wrong in the one
  direction that flattered the author, and was itself caught by the evaluator.
  An entry whose whole purpose is to stop a reader trusting a green check kept
  overstating what the checks assert.

  When writing about coverage: measure each claim separately and count against
  the artifact rather than summarizing it. The plausible sentence is the
  reassuring one, and it is the one that will be wrong.
  Two residuals of the same shape were recorded here — the scripts enumerated
  files explicitly, and no CI job ran the full glob, so a PR adding
  `tests/foo.test.ts` went green with that file never executed, which
  `tests-guard.sh` makes reachable by design since it permits creating a new
  unapproved test file. **Both are closed**: `scripts/run-tests.mjs` discovers
  by default-include and `test:check` runs in CI. Not by the `tests/live/`
  layout suggested here, which needs a write to a locked test file; by a named
  LIVE list whose membership `check` verifies against each file's keyless
  behavior. Every draft of that check was defeated by executing it, never by
  reading it, and the list is the point rather than its length. Draft 1 asserted
  that `pure` and `live` partition the discovered list — complementary filters
  over it, so the branch was unreachable; 512 constructed inputs fired it zero
  times. Draft 2 required a LIVE file to fail without a key but not to fail
  *because* of one, so a test asserting `1 + 1 === 3` was named in LIVE and ran
  in no CI job with the check green. Draft 3 matched the string
  `MANUFACT_API_KEY` anywhere in the output, which a failing assertion message
  can simply contain. Draft 4 matches the thrown `MissingApiKeyError` instead;
  writing *that* into an assertion message still defeats it, and nothing here
  closes that. The commit that adds `scripts/run-tests.mjs` carries the same
  list in its message, with what each evaluation did to break it.
- **A revert branch cut from a squash-merged commit is a no-op merge.** If the
  commit being undone was squashed or rebased onto the default branch, it is not
  an ancestor of it. The revert branch's merge base stays behind, the three-way
  merge resolves the file in the default branch's favour, and the revert PR
  merges **green while changing nothing** — reporting success against a state it
  did not fix. When a later PR must undo an earlier one, merge the earlier one
  with a merge commit, and check `git merge-base --is-ancestor <commit> main`
  before relying on the revert. The mechanism was derived and confirmed, not
  observed: STAGE-PLAN correction 36 records a **near-miss**, caught by an
  evaluator before the break was pushed, and `git merge-base --is-ancestor
  e181bd6 main` returns true because PR #27 was merged with a merge commit. No
  no-op merge ever occurred here. The rule is preventive.

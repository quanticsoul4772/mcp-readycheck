# AGENTS.md

mcp-readycheck is an MCP App that runs Manufact's publishing checks against its
own deployed URL and renders the result by category. The app is its own test case.

## Commands

| | |
|---|---|
| dev | `npm run dev` — serves `/mcp` on :3000, Inspector at `/mcp/inspector`. Backgrounded, it detaches; stop it by killing the node process, not just the shell. |
| build | `npm run build` → `.mcp-use/build/index.js` |
| typecheck | `npm run typecheck` (regenerates `mcp-env.d.ts`, then `tsc`) |
| test | `npm test` — `node --test` over `tests/**/*.test.ts`, no test framework dependency. The hook suites are separate: `sh .claude/hooks/*.test.sh` |
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
  when the diff is documentation-only. **It is not yet in ruleset `21871580`'s
  required checks** — until it is, a red `verdict` is advisory, and that gap is
  itself the "absent guard read as an allowance" failure described above.
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
- **On Git Bash, `cygpath -u "$TEMP"` is `/tmp`.** The Windows temp directory is
  mounted there, so `TMPDIR`, `TEMP`, `TMP`, and `/tmp` collapse to one root.
  A short roots list is correct, not a dropped entry — verify before "fixing" it.

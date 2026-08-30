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
- **On Git Bash, `cygpath -u "$TEMP"` is `/tmp`.** The Windows temp directory is
  mounted there, so `TMPDIR`, `TEMP`, `TMP`, and `/tmp` collapse to one root.
  A short roots list is correct, not a dropped entry — verify before "fixing" it.

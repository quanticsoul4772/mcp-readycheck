# AGENTS.md

mcp-readycheck is an MCP App that runs Manufact's publishing checks against its
own deployed URL and renders the result by category. The app is its own test case.

## Commands

| | |
|---|---|
| dev | `npm run dev` — serves `/mcp` on :3000, Inspector at `/mcp/inspector`. Backgrounded, it detaches; stop it by killing the node process, not just the shell. |
| build | `npm run build` → `.mcp-use/build/index.js` |
| typecheck | `npm run typecheck` (regenerates `mcp-env.d.ts`, then `tsc`) |
| test | no suite yet — the hook suites are `sh .claude/hooks/*.test.sh` |
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
  category names into a schema.
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
- **On Git Bash, `cygpath -u "$TEMP"` is `/tmp`.** The Windows temp directory is
  mounted there, so `TMPDIR`, `TEMP`, `TMP`, and `/tmp` collapse to one root.
  A short roots list is correct, not a dropped entry — verify before "fixing" it.

# ADR-0003: Accept the guard layer's known residuals and freeze it for G1

- Status: accepted
- Date: 2026-08-30
- Deciders: repository owner

## Context

Three merged PRs built the guard layer that now runs on every tool call:

- **PR #3** scoped the write guard to an allow-list of writable roots
  (repository + temp) rather than refusing everything outside the repository
  root, after the first version would have blocked the scratchpad the harness
  itself tells agents to use.
- **PR #5** closed the Bash-mediated write surface into `.claude/hooks/**` and
  `.claude/settings.json`: redirection, here-documents, `tee`, `cp`, `mv`,
  `install` and `sed -i`.
- **PR #6** added `integrity.sh`, which compares every file in `.claude/hooks`
  and the registration in `.claude/settings.json` against committed HEAD before
  any Bash, Edit, Write or MultiEdit call, and refuses the call on drift.

Each closed a real hole. None is airtight, and G1 is the first goal to write
feature code under them. The residuals need to be written down before they are
discovered by tripping over them mid-implementation.

### Residual 1 — an interpreter here-document still writes hooks

PR #5's guard refuses the enumerated shell forms. It does not see this:

```
python - <<'PY'
open(".claude/hooks/bearings.sh", "w").write("...")
PY
```

The here-document body is stripped before the redirect scan (deliberately, so a
document that *quotes* a dangerous command is not itself refused), and `python`
is not one of the checked write verbs. This is not theoretical: it is the
mechanism that authored PR #5 and PR #6, because those PRs' own guard blocked
every other route into `.claude/hooks/`.

Closing it means reading the embedded program to decide whether it writes. A
regex cannot do that without refusing scripts that merely *read* a hook path,
which is a common and legitimate operation.

`integrity.sh` does not close this hole either, but it does change its
character: a hook written this way is drift, and the very next tool call is
refused until the change is committed. The write still succeeds; it can no
longer be *silent*.

### Residual 2 — an attester cannot attest itself

`integrity.sh` compares its own file against HEAD, but it is the thing doing the
comparing. Edit it and the edited copy is what checks the edit. Nothing inside
the repository closes this; it is the exposure every attester has.

### Residual 3 — `integrity.sh` is mode 100644, and that is inert

```
$ git ls-tree main -- .claude/hooks/
100755 .claude/hooks/bearings.sh
...
100644 .claude/hooks/integrity.sh
100644 .claude/hooks/integrity.test.sh
100644 .claude/hooks/sessionstart-registration.test.sh
100755 .claude/hooks/tests-guard.sh
```

Three files are non-executable where the rest are executable. This has no
runtime effect, for two independent reasons:

1. Every hook is registered as `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>"`.
   The file is an *argument* to an interpreter, never an executed image, so its
   executable bit is never consulted.
2. `core.filemode` is `false` in this repository and the working tree sits on a
   `posix=0` mount, where `chmod(1)` changes nothing git can observe — a fresh
   file cannot be made executable at all, and Git Bash synthesises the displayed
   executable bit from the shebang. `sessionstart-registration.test.sh` is
   `100644` in the index and still displays as `-rwxr-xr-x`.

The inconsistency is cosmetic. Normalising it would need
`git update-index --chmod=+x`, which `integrity.sh` itself refuses as a non-escape
-hatch command while any drift exists — a small ordering annoyance, not a defect.

### Residual 4 — the drift escape hatch rejects compound git commands

`integrity.sh` allows `git add`, `git commit`, `git diff`, `git status` and
`git stash` while drift exists, but only as a single simple command: a first
line containing `;`, `&`, `|`, a backtick or `$(` is refused, because a compound
line can carry anything after the git verb. The practical cost is that
`git commit -m "a && b"` must be reworded. `git update-index` is outside the
hatch entirely.

### Residual 5 — a `hooks` key in local settings has no automated remedy

`integrity.sh` refuses unconditionally when the gitignored
`.claude/settings.local.json` contains a `hooks` key, including for git
commands, because no commit brings a gitignored file under review. Only a human
removing the key clears it. A `settings.local.json` that fails to parse is
treated as having no `hooks` key, matching what the harness itself would do.

## Decision

Accept all five residuals as known and documented, and freeze the guard layer
for the duration of G1: no change under `.claude/` is in scope for the readiness
tool, and none of these residuals is closed as part of it.

Residual 1 is accepted specifically on the ground that `integrity.sh` converts
it from a silent modification into a visible one — the write still succeeds, but
the session is refused until a human sees the diff. That is the property worth
having, and it is the property the layer was built to provide.

## Consequences

**Easier.** G1 proceeds without guard work competing for the same PRs. The
implementation knows in advance which operations will be refused and why, so a
refusal mid-implementation is a recognised constraint rather than a puzzle.

**Harder.** Writing any file under `.claude/hooks/` during G1 requires the Write
tool or an interpreter here-document, and every such change makes the tree
drifted until committed. This is intended friction, but it is friction.

**If the assumption underneath is wrong.** The load-bearing assumption is that a
human actually reads the diff. If hook changes start being merged unread, the
layer degrades to a speed bump: residual 2 means a compromised `integrity.sh`
reports itself clean, and residual 1 means the write that compromised it left no
other trace. The guard buys review, not immunity, and it is worth exactly as
much as the review it forces.

A second assumption is that mode bits stay irrelevant. That holds only while
hooks are invoked through `bash <path>`. A future registration that executes a
hook directly would make residual 3 live, and `integrity.sh` at `100644` would
then fail to run — silently, since a hook that cannot execute cannot report.

## Alternatives considered

**Close residual 1 with a heuristic** — refuse an interpreter here-document
whose body mentions a protected path. Rejected: it refuses reads as well as
writes. The first attempt at exactly this pattern during PR #5 refused
`grep -n 'sed -i.bak' <a hook file>`, a pure read, which is why the guard was
fixed at the tokenizer instead of by stacking a blunter matcher on top.

**Normalise the file modes now.** Rejected as unnecessary work with no runtime
effect on this platform, and it cannot be done through the escape hatch while
drift exists. Revisit if hooks are ever invoked directly.

**Sign the hooks rather than compare them to HEAD.** Rejected for G1: it moves
the trust anchor to a key that has to live somewhere, which is a larger design
question than the one being solved, and it does not close residual 2 either.

**Leave the residuals undocumented** and address them when hit. Rejected: two of
the three PRs above found their defects by tripping over them, and each cost a
detour mid-task. Writing them down is cheaper than rediscovering them.

## Revisit when

Any residual is actually exercised during feature work — specifically:

- a hook or `settings.json` is modified by an interpreter here-document during
  G1 or later (residual 1),
- a hook registration ever invokes a hook directly rather than through
  `bash <path>`, which makes residual 3 live,
- the drift escape hatch blocks a command that has no reasonable rewrite
  (residual 4),
- or a `hooks` key appears in `.claude/settings.local.json` in normal use
  (residual 5).

Residual 2 has no in-repository fix and is revisited only if the trust model
itself changes.

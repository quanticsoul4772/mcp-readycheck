#!/bin/sh
# tests-guard.sh — PreToolUse hook.
#
# While a `.tests-locked` marker exists at the repo root, the approved test
# list is frozen: an agent may not edit a test file that is already tracked,
# and may not pass a snapshot-update flag to a test runner. The marker arrives
# with the plan PR the human merges at Gate A, and only the human removes it.
#
# Rationale: a diff that edits its own tests is the signature of reward
# hacking. Freezing the list makes that visible instead of convenient.
#
# What the lock does NOT cover, deliberately:
#   - `.claude/hooks/**`. Those are guard suites, not product tests, and
#     integrity.sh governs them by refusing every tool call while they differ
#     from HEAD — stricter than this, not weaker.
#   - A test file nobody has approved. With the marker tracked on main, every
#     branch inherits it, so refusing unknown paths meant a plan PR could never
#     introduce the test file it exists to propose.
#
# Both exceptions are decided on a CANONICAL repo-relative path. An earlier
# revision tested the raw string and was defeated three ways in evaluation:
# `tests/Readiness-Tool.test.ts` (git is case-sensitive, NTFS is not),
# `.claude/hooks/../../tests/readiness-tool.test.ts` (substring match on an
# unresolved path), and `notes.claude/hooks/x/../../../tests/…` (the same
# substring appearing inside another name). Resolve first, then decide.
#
# Contract: exit 0 allows, exit 2 blocks with the reason on stderr.
set -u

REPO_ROOT=${CLAUDE_PROJECT_DIR:-}
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

MARKER=$REPO_ROOT/.tests-locked
[ -f "$MARKER" ] || exit 0

PAYLOAD=$(cat)

# Node does the JSON parsing and the path canonicalisation together: `..` and
# `.` are resolved, separators normalised, and each path reduced to a
# repo-relative form or reported as outside the repo. Doing this in sh invited
# exactly the traversal bugs above.
HOOK_REPO_ROOT=$REPO_ROOT
export HOOK_REPO_ROOT
FIELDS=$(printf '%s' "$PAYLOAD" | node -e '
let raw = "";
process.stdin.on("data", d => raw += d);
process.stdin.on("end", () => {
  let d = {};
  try { d = JSON.parse(raw); } catch (e) { }
  const ti = d.tool_input || {};
  const b64 = s => Buffer.from(String(s == null ? "" : s), "utf8").toString("base64");

  const norm = (s) => {
    const parts = String(s).replace(/\\\\/g, "/").split("/");
    const out = [];
    for (const seg of parts) {
      if (seg === "" && out.length) continue;
      if (seg === ".") continue;
      if (seg === "..") {
        if (out.length && out[out.length - 1] !== ".." && out[out.length - 1] !== "") out.pop();
        else out.push("..");
        continue;
      }
      out.push(seg);
    }
    return out.join("/");
  };

  // Git Bash and the harness disagree about how to spell a Windows root:
  // "/d/Projects/x" and "D:/Projects/x" are the same directory. Comparing them
  // as strings makes every path look like it is outside the repo, which the
  // fail-closed branch then refuses — including this hook'"'"'s own test suite.
  const winish = (s) => {
    const m = /^\/([A-Za-z])(\/.*)?$/.exec(s);
    return m ? m[1].toUpperCase() + ":" + (m[2] || "/") : s;
  };

  const root = winish(norm(process.env.HOOK_REPO_ROOT || ""));
  const isAbs = (s) => s.startsWith("/") || /^[A-Za-z]:/.test(s);

  // Repo-relative canonical form, or "" when the path leaves the repo. An
  // empty result is "unknown", and every caller treats unknown as refused.
  const rel = (p) => {
    const q = String(p).replace(/\\\\/g, "/");
    const abs = winish(norm(isAbs(q) ? q : root + "/" + q));
    if (abs.toLowerCase() === root.toLowerCase()) return "";
    if (!abs.toLowerCase().startsWith(root.toLowerCase() + "/")) return "";
    return abs.slice(root.length + 1);
  };

  const paths = [ti.file_path, ti.path, ti.notebook_path].filter(Boolean);
  process.stdout.write("TOOL=" + b64(d.tool_name) + "\n");
  process.stdout.write("CMD=" + b64(ti.command) + "\n");
  for (const p of paths) {
    process.stdout.write("PATH=" + b64(p) + " " + b64(rel(p)) + "\n");
  }
});
' 2>/dev/null)

[ -z "$FIELDS" ] && exit 0

d64() { printf '%s' "$1" | base64 -d 2>/dev/null; }

TOOL=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^TOOL=//p')")
CMD=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^CMD=//p')")
PATH_PAIRS=$(printf '%s\n' "$FIELDS" | sed -n 's/^PATH=//p')

block() {
  printf 'BLOCKED by tests-guard: %s\n' "$1" >&2
  printf '  refused: %s\n' "$2" >&2
  printf '  The test list is locked by %s.\n' "$MARKER" >&2
  printf '  Only the human removes that marker. Do not edit tests to make a diff pass.\n' >&2
  exit 2
}

# Every path git knows about, in HEAD or in the index, lower-cased.
#
# Lower-cased because `git cat-file -e HEAD:<p>` and `git ls-files
# --error-unmatch` are case-sensitive while this filesystem is not: writing
# `tests/Readiness-Tool.test.ts` truncates the tracked lower-case file, and an
# exact-case lookup called it a brand-new proposal.
TRACKED=$(
  {
    git -C "$REPO_ROOT" ls-files 2>/dev/null
    git -C "$REPO_ROOT" ls-tree -r --name-only HEAD 2>/dev/null
  } | tr 'A-Z' 'a-z' | sed '/^$/d' | sort -u
)

is_tracked() {
  [ -n "$1" ] || return 1
  printf '%s\n' "$TRACKED" | grep -Fxq "$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
}

# The marker itself is protected while it is in force. Editing it would let an
# agent rewrite the lock; deleting it would let one lift the lock and then edit
# every test freely. Reading it is untouched — S3 must `ls` it.
is_marker_path() {
  case "$1" in
    .tests-locked|*/.tests-locked) return 0 ;;
    *) return 1 ;;
  esac
}

# Decided on the canonical repo-relative path, never on the raw string.
is_test_path() {
  [ -n "$1" ] || return 1
  case "$1" in
    .claude/hooks/*) return 1 ;;
  esac
  case "$1" in
    *.test.*|*.spec.*|__tests__/*|*/__tests__/*|__snapshots__/*|*/__snapshots__/*|*.snap) return 0 ;;
    *) return 1 ;;
  esac
}

# A test file git has never seen is a proposal, not part of the approved list.
# Fails closed: an empty canonical path — anything outside the repo, or that
# the canonicaliser could not resolve — is not a proposal.
is_new_test_file() {
  [ -n "$1" ] || return 1
  is_tracked "$1" && return 1
  return 0
}

case "$TOOL" in
  Edit|Write|NotebookEdit|MultiEdit)
    # One pair per line: base64(raw) SP base64(canonical). Never `for p in
    # $PATHS` — unquoted word splitting cut "C:/Program Files/…/x.test.ts" into
    # two fragments, neither of which looked like a tracked test.
    while IFS= read -r pair; do
      [ -z "$pair" ] && continue
      raw=$(d64 "${pair%% *}")
      rel=$(d64 "${pair#* }")

      if is_marker_path "$rel" || is_marker_path "$raw"; then
        block "edit to the lock marker itself" "$TOOL $raw"
      fi

      # An unresolvable path that still looks like a test is refused: unknown
      # is never "safe". The raw string is checked too, so a path outside the
      # repo cannot slip through on an empty canonical form.
      if [ -z "$rel" ]; then
        case "$(printf '%s' "$raw" | tr '\134' '/')" in
          *.test.*|*.spec.*|*__tests__/*|*__snapshots__/*|*.snap)
            block "edit to a test file the guard cannot resolve" "$TOOL $raw"
            ;;
        esac
        continue
      fi

      if is_test_path "$rel"; then
        if is_new_test_file "$rel"; then
          continue
        fi
        block "edit to a locked test file" "$TOOL $raw"
      fi
    done <<PATH_PAIRS_EOF
$PATH_PAIRS
PATH_PAIRS_EOF
    exit 0
    ;;
  Bash)
    [ -z "$CMD" ] && exit 0

    # Quote-aware segmentation, the same splitter destructive-guard uses. A
    # naive `sed s/|/\n/g` cuts `--testNamePattern='a|b' -u` in half and drops
    # the flag into a fragment with no runner in it — the exact defect already
    # in the mistake log as "split a command line on unquoted separators only",
    # which an evaluation reproduced here by executing it.
    SEGMENTS=$(printf '%s\n' "$CMD" | awk '
      { s=$0; out=""; q="";
        for (i=1; i<=length(s); i++) { c=substr(s,i,1);
          if (q != "") { if (c==q) q=""; out = out c; continue }
          if (c=="\047" || c=="\"") { q=c; out=out c; continue }
          if (c=="|" || c==";" || c=="&") { out = out "\n"; continue }
          out = out c }
        print out }')

    # A runner is recognised by the basename of any token, so
    # `./node_modules/.bin/jest` counts. `sh -c "vitest -u"` is covered because
    # the tokenizer strips the quotes and the inner words become tokens of the
    # same segment.
    #
    # Known gaps, stated rather than papered over: a runner reached through a
    # variable (`X=vitest; $X -u`) or assembled by another process
    # (`echo -u | xargs npx vitest`) is not recognised. Both need dataflow, not
    # pattern matching. The lock exists to make an edit visible, not to make
    # one impossible — an agent doing either is plainly working around it, and
    # that shows in the diff.
    is_runner_token() {
      base=${1##*/}
      case "$base" in
        vitest|jest|mocha|ava|tap|playwright|cypress|karma|nyc|c8) return 0 ;;
      esac
      return 1
    }

    is_update_flag() {
      case "$1" in
        -u|-U|--update-snapshot|--updateSnapshot|--update-snapshots|--ci=false) return 0 ;;
        -u=*|-U=*|--update-snapshot=*|--updateSnapshot=*|--update-snapshots=*) return 0 ;;
      esac
      return 1
    }

    while IFS= read -r seg; do
      [ -z "$seg" ] && continue

      # Quote-stripping tokenizer. `tr ' \t' '\n\n'` was tried and lost it,
      # which let `npx vitest "-u"` through.
      SEG_TOKENS=$(printf '%s\n' "$seg" | xargs -n1 printf '%s\n' 2>/dev/null) ||
        SEG_TOKENS=$(printf '%s\n' "$seg" | tr ' \t' '\n\n')

      # `sh -c "vitest -u"` arrives as three tokens, the last of which is the
      # whole inner command. Expand the argument of a `-c` so the words inside
      # it are scanned too. Only after `-c`: splitting every token on
      # whitespace would make `git commit -m "ran vitest -u"` a refusal, and a
      # guard that refuses commit messages is the false-positive class this
      # repo has already paid for twice.
      SEG_TOKENS=$(printf '%s\n' "$SEG_TOKENS" | awk '
        { if (prev == "-c") { n = split($0, w, /[ \t]+/); for (i = 1; i <= n; i++) if (w[i] != "") print w[i] }
          print; prev = $0 }')

      runner=0
      prev=""
      while IFS= read -r t; do
        [ -z "$t" ] && continue
        if is_runner_token "$t"; then runner=1; fi
        # `npm test`, `npm run test:unit`, `yarn test`, `bun test`,
        # `deno test`, `node --test`.
        case "$prev" in
          npm|pnpm|yarn|bun|deno|run)
            case "$t" in test|test:*|*:test) runner=1 ;; esac
            ;;
        esac
        case "$t" in --test|--test=*) runner=1 ;; esac
        prev=$t
      done <<SEG_TOKENS_EOF
$SEG_TOKENS
SEG_TOKENS_EOF

      [ "$runner" -eq 1 ] || continue

      while IFS= read -r t; do
        [ -z "$t" ] && continue
        if is_update_flag "$t"; then
          block "snapshot-update flag on a test runner while tests are locked" "$CMD"
        fi
      done <<SEG_FLAGS_EOF
$SEG_TOKENS
SEG_FLAGS_EOF
    done <<SEGMENTS_EOF
$SEGMENTS
SEGMENTS_EOF

    # Redirection into a test file is an edit by another name. Kept on the raw
    # command: a redirect target is a shell word, not a tool argument, and the
    # canonicaliser never sees it.
    if printf '%s' "$CMD" | grep -qE '>[[:space:]]*[^[:space:]]*\.(test|spec)\.' ; then
      block "shell redirection into a locked test file" "$CMD"
    fi

    # Removing the marker would lift the lock, after which every test above is
    # editable. Refused by the same guard the marker switches on.
    TOKENS=$(printf '%s\n' "$CMD" | xargs -n1 printf '%s\n' 2>/dev/null) || TOKENS=""
    [ -z "$TOKENS" ] && TOKENS=$(printf '%s\n' "$CMD" | tr ' \t' '\n\n')
    for t in $TOKENS; do
      case "$t" in
        *.tests-locked)
          case "$CMD" in
            *rm\ *|*rm\	*|*unlink\ *|*del\ *|*erase\ *|*mv\ *|*"git clean"*|*truncate\ *)
              block "removal or move of the lock marker" "$CMD"
              ;;
          esac
          ;;
      esac
    done
    if printf '%s' "$CMD" | grep -qE '>[[:space:]]*[^[:space:]]*\.tests-locked' ; then
      block "shell redirection into the lock marker" "$CMD"
    fi
    exit 0
    ;;
esac

exit 0

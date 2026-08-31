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
# Every path decision is made on a CANONICAL, LOWER-CASED repo-relative path.
# Three evaluation rounds took three tries to get that right:
#   1. raw-string matching: `.claude/hooks/../../tests/x.test.ts` walked out of
#      the exclusion, and `notes.claude/hooks/…` matched the substring.
#   2. canonical path, lower-cased only for the tracked-list lookup: the
#      classifier globs stayed case-sensitive, so `tests/Readiness-Tool.Test.ts`
#      was never classified as a test at all and the lookup never ran. Same
#      inode, same 14625 bytes, and a Write would have truncated it.
#   3. lower-case before classifying, which is this file.
# On a case-sensitive filesystem this refuses a genuinely distinct file whose
# name differs only in case. That is a fail-closed trade, taken deliberately:
# this repo lives on NTFS, where those names are the same file.
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

# Node does the JSON parsing and the path canonicalisation together: `.` and
# `..` are resolved, separators normalised, and each path reduced to a
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
    const parts = String(s).replace(/\\/g, "/").split("/");
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
  // as strings makes every path look external, and the fail-closed branch then
  // refuses this hook s own test suite.
  const winish = (s) => {
    const m = /^\/([A-Za-z])(\/.*)?$/.exec(s);
    return m ? m[1].toUpperCase() + ":" + (m[2] || "/") : s;
  };

  const root = winish(norm(process.env.HOOK_REPO_ROOT || ""));
  const isAbs = (s) => s.startsWith("/") || /^[A-Za-z]:/.test(s);

  // Repo-relative canonical form, or "" when the path leaves the repo. An
  // empty result is "unknown", and every caller treats unknown as refused.
  const rel = (p) => {
    const q = String(p).replace(/\\/g, "/");
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
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

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

# Every path git knows about, in HEAD or in the index, lower-cased. `git
# cat-file` and `git ls-files` are case-sensitive and this filesystem is not.
TRACKED=$(
  {
    git -C "$REPO_ROOT" ls-files 2>/dev/null
    git -C "$REPO_ROOT" ls-tree -r --name-only HEAD 2>/dev/null
  } | tr 'A-Z' 'a-z' | sed '/^$/d' | sort -u
)

# Callers pass an already-lower-cased path.
is_tracked() {
  [ -n "$1" ] || return 1
  printf '%s\n' "$TRACKED" | grep -Fxq "$1"
}

# The marker itself is protected while it is in force. Editing it would let an
# agent rewrite the lock; deleting it would let one lift the lock and then edit
# every test freely. `.TESTS-LOCKED` names the same file on this volume — an
# evaluation deleted it that way — so this too matches on the lower-cased form.
is_marker_path() {
  case "$1" in
    .tests-locked|*/.tests-locked) return 0 ;;
    *) return 1 ;;
  esac
}

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

case "$TOOL" in
  Edit|Write|NotebookEdit|MultiEdit)
    # One pair per line: base64(raw) SP base64(canonical). Never `for p in
    # $PATHS` — unquoted word splitting cut "C:/Program Files/…/x.test.ts" into
    # two fragments, neither of which looked like a tracked test.
    while IFS= read -r pair; do
      [ -z "$pair" ] && continue
      raw=$(d64 "${pair%% *}")
      rel=$(d64 "${pair#* }")
      rel_l=$(lower "$rel")
      raw_l=$(lower "$(printf '%s' "$raw" | tr '\134' '/')")

      if is_marker_path "$rel_l" || is_marker_path "$raw_l"; then
        block "edit to the lock marker itself" "$TOOL $raw"
      fi

      # An unresolvable path that still looks like a test is refused: unknown
      # is never "safe". The raw string is checked too, so a path outside the
      # repo cannot slip through on an empty canonical form.
      if [ -z "$rel" ]; then
        case "$raw_l" in
          *.test.*|*.spec.*|*__tests__/*|*__snapshots__/*|*.snap)
            block "edit to a test file the guard cannot resolve" "$TOOL $raw"
            ;;
        esac
        continue
      fi

      if is_test_path "$rel_l"; then
        # A test file git has never seen is a proposal, not part of the
        # approved list.
        if is_tracked "$rel_l"; then
          block "edit to a locked test file" "$TOOL $raw"
        fi
        continue
      fi
    done <<PATH_PAIRS_EOF
$PATH_PAIRS
PATH_PAIRS_EOF
    exit 0
    ;;
  Bash)
    [ -z "$CMD" ] && exit 0

    # A backslash continuation is not a command boundary. The segmenter below
    # is a per-line awk program, so `npx vitest \` + newline + `-u` became two
    # segments — runner in one, flag in the other — while the shell joins them
    # and runs `vitest -u`. Join first.
    CMD_JOINED=$(printf '%s\n' "$CMD" | awk '
      { line = $0
        if (buf != "") { line = buf line; buf = "" }
        if (sub(/\\$/, "", line)) { buf = line; next }
        print line }
      END { if (buf != "") print buf }')

    # The argument of a `-c` is a command, and it is segmented as one. An
    # earlier revision split it on whitespace instead, which collapsed its
    # clause boundaries: `sh -c "npm test && git push -u origin main"` was
    # refused while the identical unquoted line was allowed — the exact
    # false-positive class this change exists to remove.
    # `-c`, and also a short-flag cluster ending in it: `bash -lc "vitest -u"`
    # and `sh -euc "vitest -u"` are the same construct and were walking past a
    # test for the exact string.
    INNER=$(printf '%s\n' "$CMD_JOINED" | xargs -n1 printf '%s\n' 2>/dev/null | awk '
      { if (prev ~ /^-[A-Za-z]*c$/) print; prev = $0 }')

    # Quote-aware segmentation, the same splitter destructive-guard uses. A
    # naive `sed s/|/\n/g` cuts `--testNamePattern='a|b' -u` in half and drops
    # the flag into a fragment with no runner in it — the defect already in the
    # mistake log as "split a command line on unquoted separators only".
    SEGMENTS=$(printf '%s\n%s\n' "$CMD_JOINED" "$INNER" | awk '
      { s=$0; out=""; q="";
        for (i=1; i<=length(s); i++) { c=substr(s,i,1);
          if (q != "") { if (c==q) q=""; out = out c; continue }
          if (c=="\047" || c=="\"") { q=c; out=out c; continue }
          if (c=="|" || c==";" || c=="&") { out = out "\n"; continue }
          out = out c }
        print out }')

    # A runner is recognised by the basename of any token, so
    # `./node_modules/.bin/jest` counts. A URL is never a runner: `curl -u tok
    # https://github.com/vitest-dev/vitest` ends in a basename that looks like
    # one.
    is_runner_token() {
      # A URL is not a runner: `curl -u tok https://github.com/vitest-dev/vitest`
      # ends in a basename that reads like one. Anchored on a LEADING scheme —
      # matching `://` anywhere let `node file:///d/x/vitest -u` through, which
      # is a real runner invocation wearing a scheme.
      case "$(lower "$1")" in
        http://*|https://*|git://*|ssh://*|ftp://*|git+ssh://*) return 1 ;;
      esac
      base=${1##*/}
      case "$base" in
        vitest|jest|mocha|ava|tap|playwright|cypress|karma|nyc|c8) return 0 ;;
      esac
      return 1
    }

    # Callers pass an already-lower-cased token, so every pattern here must be
    # lower-case too. Folding the token while leaving `--updateSnapshot` in
    # camelCase made that pattern unreachable and silently un-refused jest's
    # documented long flag — a hole opened by the fix for a different one, and
    # visible only as dead code in a `case` nobody reads.
    is_update_flag() {
      case "$1" in
        -u|--update-snapshot|--updatesnapshot|--update-snapshots|--ci=false) return 0 ;;
        -u=*|--update-snapshot=*|--updatesnapshot=*|--update-snapshots=*) return 0 ;;
      esac
      return 1
    }

    # Known gaps, stated rather than papered over: a runner reached through a
    # variable (`X=vitest; $X -u`) or assembled by another process
    # (`echo -u | xargs npx vitest`) is not recognised. Both need dataflow, not
    # pattern matching. The lock exists to make an edit visible, not impossible.
    while IFS= read -r seg; do
      [ -z "$seg" ] && continue

      # Quote-stripping tokenizer. `tr ' \t' '\n\n'` was tried and lost it,
      # which let `npx vitest "-u"` through.
      SEG_TOKENS=$(printf '%s\n' "$seg" | xargs -n1 printf '%s\n' 2>/dev/null) ||
        SEG_TOKENS=$(printf '%s\n' "$seg" | tr ' \t' '\n\n')

      # The flag must come AFTER the runner, because that is how a flag reaches
      # a runner. Order is what separates `npx vitest -u` from
      # `docker run -u 1000 node npm test`, where the `-u` belongs to docker.
      runner=0
      prev=""
      while IFS= read -r t; do
        [ -z "$t" ] && continue
        # Folded, like the paths, the marker and the scheme. `npx VITEST -u` and
        # `npx vitest --UPDATE-SNAPSHOT` name the same binary and the same flag
        # on this filesystem; the runner and flag lists were the last two
        # comparisons that still cared about case.
        t=$(lower "$t")
        if [ "$runner" -eq 1 ] && is_update_flag "$t"; then
          block "snapshot-update flag on a test runner while tests are locked" "$CMD"
        fi
        if is_runner_token "$t"; then runner=1; fi
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
    done <<SEGMENTS_EOF
$SEGMENTS
SEGMENTS_EOF

    # Redirection into a test file is an edit by another name. Kept on the raw
    # command: a redirect target is a shell word, not a tool argument, and the
    # canonicaliser never sees it. Case-insensitive for the same reason the
    # path checks are.
    if printf '%s' "$CMD" | grep -qiE '>[[:space:]]*[^[:space:]]*\.(test|spec)\.' ; then
      block "shell redirection into a locked test file" "$CMD"
    fi

    # Removing the marker would lift the lock, after which every test above is
    # editable. Refused by the same guard the marker switches on.
    TOKENS=$(printf '%s\n' "$CMD" | xargs -n1 printf '%s\n' 2>/dev/null) || TOKENS=""
    [ -z "$TOKENS" ] && TOKENS=$(printf '%s\n' "$CMD" | tr ' \t' '\n\n')
    # Whether any token IS a removal verb, rather than whether the command
    # CONTAINS one followed by a space. `echo .tests-locked | xargs rm` deleted
    # the marker and was allowed, because every pattern here ended in `\ *` and
    # the verb was the last word on the line. A token test has no end-of-line
    # blind spot, and it stops matching inside words as a bonus.
    REMOVAL_VERB=0
    for tl in $TOKENS_L; do
      base=${tl##*/}
      # `/usr/bin/rm.exe` exists on Git Bash and runs from it. Comparing the
      # basename against a bare `rm` let the `.exe` suffix walk past — and the
      # substring form this replaced never caught it either.
      case "$base" in *.exe) base=${base%.exe} ;; esac
      case "$base" in
        rm|rmdir|unlink|del|erase|mv|shred|truncate) REMOVAL_VERB=1 ;;
      esac
    done
    case "$(lower "$CMD")" in
      *"git clean"*) REMOVAL_VERB=1 ;;
    esac

    for t in $TOKENS; do
      case "$(lower "$t")" in
        *.tests-locked)
          if [ "$REMOVAL_VERB" -eq 1 ]; then
            block "removal or move of the lock marker" "$CMD"
          fi
          # `-delete` only means deletion when something is walking the tree.
          # As a bare substring it refused `grep -n '-delete' .tests-locked`,
          # which is a read — the false-positive shape already in the mistake
          # log as "a whole-command regex net is not a substitute for parsing".
          case "$(lower "$CMD")" in
            *find\ *|*fd\ *|*rsync\ *)
              case "$(lower "$CMD")" in
                *-delete*|*--delete*)
                  block "removal of the lock marker by a tree walk" "$CMD"
                  ;;
              esac
              ;;
          esac
          ;;
      esac
    done
    if printf '%s' "$CMD" | grep -qiE '>[[:space:]]*[^[:space:]]*\.tests-locked' ; then
      block "shell redirection into the lock marker" "$CMD"
    fi
    exit 0
    ;;
esac

exit 0

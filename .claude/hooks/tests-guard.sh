#!/bin/sh
# tests-guard.sh — PreToolUse hook.
#
# While a `.tests-locked` marker exists at the repo root, the approved test
# list is frozen: an agent may not edit test files and may not pass
# snapshot-update flags. The marker is created by the human at test-list
# approval (step 3 of the operating cycle) and removed by the human.
#
# Rationale: a diff that edits its own tests is the signature of reward
# hacking. Freezing the list makes that visible instead of convenient.
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

FIELDS=$(printf '%s' "$PAYLOAD" | node -e '
let raw = "";
process.stdin.on("data", d => raw += d);
process.stdin.on("end", () => {
  let d = {};
  try { d = JSON.parse(raw); } catch (e) { }
  const ti = d.tool_input || {};
  const b64 = s => Buffer.from(String(s == null ? "" : s), "utf8").toString("base64");
  const paths = [ti.file_path, ti.path, ti.notebook_path].filter(Boolean).join("\n");
  process.stdout.write("TOOL=" + b64(d.tool_name) + "\n");
  process.stdout.write("CMD=" + b64(ti.command) + "\n");
  process.stdout.write("PATHS=" + b64(paths) + "\n");
});
' 2>/dev/null)

[ -z "$FIELDS" ] && exit 0

d64() { printf '%s' "$1" | base64 -d 2>/dev/null; }

TOOL=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^TOOL=//p')")
CMD=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^CMD=//p')")
PATHS=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^PATHS=//p')")

block() {
  printf 'BLOCKED by tests-guard: %s\n' "$1" >&2
  printf '  refused: %s\n' "$2" >&2
  printf '  The test list is locked by %s.\n' "$MARKER" >&2
  printf '  Only the human removes that marker. Do not edit tests to make a diff pass.\n' >&2
  exit 2
}

# The marker itself is protected while it is in force. Editing it would let an
# agent rewrite the lock; deleting it would let one lift the lock and then edit
# the tests freely. Reading it is untouched — S3 is required to `ls` it.
is_marker_path() {
  case "$1" in
    *.tests-locked|.tests-locked) return 0 ;;
    *) return 1 ;;
  esac
}

is_test_path() {
  # The guard suites under .claude/hooks are not product tests, and freezing
  # them froze the wrong thing: with the marker on main every branch inherits
  # it, so `tests-guard.test.sh` — the file that proves this guard works —
  # became unopenable, and so did every other hook suite. They have their own
  # guard: integrity.sh refuses any tool call while .claude/hooks differs from
  # HEAD, which is a stronger constraint than this one, not a weaker one.
  case "$1" in
    *.claude/hooks/*|.claude/hooks/*) return 1 ;;
  esac
  case "$1" in
    *.test.*|*.spec.*|*/__tests__/*|*/__snapshots__/*|*.snap) return 0 ;;
    *) return 1 ;;
  esac
}

# Repo-relative form of a path, or the input unchanged when it cannot be
# resolved. Callers must treat "unchanged" as "unknown", never as "safe".
repo_relative() {
  p=$(printf '%s' "$1" | tr '\134' '/')
  root=$(printf '%s' "$REPO_ROOT" | tr '\134' '/')
  case "$p" in
    "$root"/*) printf '%s' "${p#"$root"/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

# A test file that does not exist in HEAD and is not tracked is a *proposal*,
# not part of the approved list — the marker freezes what a human approved, and
# nobody has seen this one yet. Without this, a plan PR could never introduce
# the very test file it exists to propose, because the marker it inherits from
# main forbids writing one.
#
# Fails closed everywhere: an unresolvable path, an absolute path, a Windows
# drive-letter path, or any git failure all return "not new", and the caller
# refuses.
is_new_test_file() {
  rel=$(repo_relative "$1")
  case "$rel" in
    /*|?:*|*..*|"") return 1 ;;
  esac
  git -C "$REPO_ROOT" rev-parse --verify --quiet HEAD >/dev/null 2>&1 || return 1
  git -C "$REPO_ROOT" cat-file -e "HEAD:$rel" 2>/dev/null && return 1
  git -C "$REPO_ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1 && return 1
  return 0
}

case "$TOOL" in
  Edit|Write|NotebookEdit|MultiEdit)
    for p in $PATHS; do
      [ -z "$p" ] && continue
      if is_marker_path "$p"; then
        block "edit to the lock marker itself" "$TOOL $p"
      fi
      if is_test_path "$p"; then
        # A file nobody has approved yet is a proposal, not part of the list.
        if is_new_test_file "$p"; then
          continue
        fi
        block "edit to a locked test file" "$TOOL $p"
      fi
    done
    exit 0
    ;;
  Bash)
    [ -z "$CMD" ] && exit 0
    # Explicit printf: bare `xargs -n1` defaults to echo, which consumes -n.
    TOKENS=$(printf '%s\n' "$CMD" | xargs -n1 printf '%s\n' 2>/dev/null) || TOKENS=""
    [ -z "$TOKENS" ] && TOKENS=$(printf '%s\n' "$CMD" | tr ' \t' '\n\n')

    # A snapshot-update flag only means anything to a test runner. Scoping the
    # check to runner invocations is not a loosening: `-u` is also `git push -u`
    # and `cygpath -u`, and both were refused here — neither can rewrite a test.
    # A whole-command scan bought nothing and cost the session two commands.
    #
    # Segments split on `&&`, `;` and `|` so `npm test && git push -u` refuses
    # nothing. The split is not quote-aware, and deliberately so: a mis-split
    # can only lose a match, never invent one, and losing one here means a flag
    # reaching a runner it was never attached to.
    is_test_runner() {
      printf '%s' "$1" | grep -qE '(^|[[:space:]])((npm|pnpm|yarn|bun)([[:space:]]+run)?[[:space:]]+test([[:space:]]|$)|npx[[:space:]]+(vitest|jest|playwright|mocha|ava|tap)([[:space:]]|$)|(vitest|jest|playwright|mocha|ava)([[:space:]]|$)|node([[:space:]]+[^[:space:]]+)*[[:space:]]+--test([[:space:]]|$|=))'
    }

    while IFS= read -r seg; do
      [ -z "$seg" ] && continue
      is_test_runner "$seg" || continue
      SEG_TOKENS=$(printf '%s\n' "$seg" | tr ' \t' '\n\n')
      for t in $SEG_TOKENS; do
        case "$t" in
          -u|--update-snapshot|--updateSnapshot|--update-snapshots|--ci=false|-U)
            block "snapshot-update flag on a test runner while tests are locked" "$CMD"
            ;;
        esac
      done
    done <<SEGMENTS_EOF
$(printf '%s\n' "$CMD" | sed 's/&&/\n/g; s/;/\n/g; s/|/\n/g')
SEGMENTS_EOF
    # Redirection into a test file is an edit by another name.
    if printf '%s' "$CMD" | grep -qE '>[[:space:]]*[^[:space:]]*\.(test|spec)\.' ; then
      block "shell redirection into a locked test file" "$CMD"
    fi

    # Removing the marker would lift the lock, after which every test above is
    # editable. Refused by the same guard the marker switches on.
    for t in $TOKENS; do
      if is_marker_path "$t"; then
        case "$CMD" in
          *rm\ *|*rm\	*|*unlink\ *|*del\ *|*erase\ *|*mv\ *|*"git clean"*|*truncate\ *)
            block "removal or move of the lock marker" "$CMD"
            ;;
        esac
      fi
    done
    if printf '%s' "$CMD" | grep -qE '>[[:space:]]*[^[:space:]]*\.tests-locked' ; then
      block "shell redirection into the lock marker" "$CMD"
    fi
    exit 0
    ;;
esac

exit 0

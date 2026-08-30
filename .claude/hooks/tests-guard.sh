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

is_test_path() {
  case "$1" in
    *.test.*|*.spec.*|*/__tests__/*|*/__snapshots__/*|*.snap) return 0 ;;
    *) return 1 ;;
  esac
}

case "$TOOL" in
  Edit|Write|NotebookEdit|MultiEdit)
    for p in $PATHS; do
      [ -z "$p" ] && continue
      if is_test_path "$p"; then
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
    for t in $TOKENS; do
      case "$t" in
        -u|--update-snapshot|--updateSnapshot|--update-snapshots|--ci=false|-U)
          block "snapshot-update flag while tests are locked" "$CMD"
          ;;
      esac
    done
    # Redirection into a test file is an edit by another name.
    if printf '%s' "$CMD" | grep -qE '>[[:space:]]*[^[:space:]]*\.(test|spec)\.' ; then
      block "shell redirection into a locked test file" "$CMD"
    fi
    exit 0
    ;;
esac

exit 0

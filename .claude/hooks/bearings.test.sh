#!/bin/sh
# bearings.test.sh
#
# Proves a fresh session prints the bearings block: the header, the branch,
# recent history, the PROGRESS.md handoff, and the working-tree state — and
# that it does not re-read CLAUDE.md, which is already in context.
#
# Run: sh .claude/hooks/bearings.test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
HOOK=$HERE/bearings.sh
CLAUDE_PROJECT_DIR=$REPO_ROOT
export CLAUDE_PROJECT_DIR

PASS=0
FAIL=0

OUT=$(printf '{"hook_event_name":"SessionStart","source":"startup"}' | sh "$HOOK" 2>&1)

check() {
  desc=$1
  pattern=$2
  if printf '%s' "$OUT" | grep -q -- "$pattern"; then
    PASS=$((PASS + 1))
    printf 'ok    %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s (no match for: %s)\n' "$desc" "$pattern"
  fi
}

refute() {
  desc=$1
  pattern=$2
  if printf '%s' "$OUT" | grep -q -- "$pattern"; then
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s (unexpected match: %s)\n' "$desc" "$pattern"
  else
    PASS=$((PASS + 1))
    printf 'ok    %s\n' "$desc"
  fi
}

printf '=== BEARINGS OUTPUT ===\n'
printf '%s\n' "$OUT"

printf '\n=== ASSERTIONS ===\n'
check  "prints the opening marker"        "=== BEARINGS ==="
check  "prints the closing marker"        "=== END BEARINGS ==="
check  "prints the branch section"        -- "--- branch ---"
check  "prints the git log section"       "git log --oneline -20"
check  "prints the PROGRESS.md section"   -- "--- PROGRESS.md ---"
check  "prints the status section"        "git status --short"
refute "does not re-read CLAUDE.md"       "@AGENTS.md"

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

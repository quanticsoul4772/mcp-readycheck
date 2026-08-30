#!/bin/sh
# bearings.sh — SessionStart hook (matchers: startup, resume, clear, compact).
#
# Prints where the work stands so a fresh or compacted session does not have to
# rediscover it: current branch, recent history, the session handoff note, and
# the working tree state.
#
# Deliberately never reads CLAUDE.md or AGENTS.md — those are already in
# context by the time this runs, and re-printing them wastes the window this
# hook exists to protect.
set -u

REPO_ROOT=${CLAUDE_PROJECT_DIR:-}
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
cd "$REPO_ROOT" 2>/dev/null || exit 0

# Drain stdin so the caller never blocks on a full pipe.
cat >/dev/null 2>&1 || true

printf '=== BEARINGS ===\n'

printf '\n--- branch ---\n'
git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '(not a git repository)\n'

printf '\n--- git log --oneline -20 ---\n'
git log --oneline -20 2>/dev/null || printf '(no commits)\n'

printf '\n--- PROGRESS.md ---\n'
if [ -f PROGRESS.md ]; then
  cat PROGRESS.md
else
  printf '(no PROGRESS.md — this worktree has no handoff note yet)\n'
fi

printf '\n--- git status --short ---\n'
status=$(git status --short 2>/dev/null)
if [ -n "$status" ]; then
  printf '%s\n' "$status"
else
  printf '(working tree matches HEAD)\n'
fi

if [ -f .tests-locked ]; then
  printf '\n--- TEST LIST LOCKED ---\n'
  printf '.tests-locked is present: test files are frozen until the human removes it.\n'
fi

printf '\n=== END BEARINGS ===\n'
exit 0

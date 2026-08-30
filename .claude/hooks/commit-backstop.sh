#!/bin/sh
# commit-backstop.sh — Stop hook.
#
# A session that ends with uncommitted work leaves nothing to review and
# nothing to roll back to. This commits whatever is in the worktree so the
# state is recoverable, and stops there.
#
# It never pushes. It never commits on the default branch — work belongs on a
# feature branch, and a backstop commit is not a reason to break that rule.
# The commit is ordinary and expected to be amended, reworded, or reverted by
# the next session.
set -u

REPO_ROOT=${CLAUDE_PROJECT_DIR:-}
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
cd "$REPO_ROOT" 2>/dev/null || exit 0

cat >/dev/null 2>&1 || true

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
case "$BRANCH" in
  main|master|HEAD)
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      printf 'commit-backstop: uncommitted work on %s — not committing to the default branch.\n' "$BRANCH" >&2
      printf 'commit-backstop: move it to a feature branch.\n' >&2
    fi
    exit 0
    ;;
esac

[ -n "$(git status --porcelain 2>/dev/null)" ] || exit 0

git add -A || exit 0

# Nothing staged after add (e.g. everything was ignored) — nothing to do.
git diff --cached --quiet && exit 0

SUMMARY=$(git diff --cached --shortstat 2>/dev/null | sed 's/^ *//')
STAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)

git commit --quiet --message "wip: session backstop ${STAMP}

Automatic commit from the Stop hook so the session's work is recoverable.
${SUMMARY}

Not reviewed, not pushed. Amend, reword, or revert this in the next session." \
  || exit 0

printf 'commit-backstop: committed uncommitted work on %s as %s\n' \
  "$BRANCH" "$(git rev-parse --short HEAD 2>/dev/null)" >&2
exit 0

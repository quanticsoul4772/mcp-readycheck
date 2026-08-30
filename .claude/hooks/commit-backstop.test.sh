#!/bin/sh
# commit-backstop.test.sh
#
# Runs against a throwaway repository so the suite is deterministic and safe
# to run in CI. It proves four things:
#   1. a dirty exit on a feature branch leaves a backstop commit
#   2. a clean tree produces no commit
#   3. the default branch is never committed to
#   4. nothing is ever pushed
#
# Run: sh .claude/hooks/commit-backstop.test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK=$HERE/commit-backstop.sh

PASS=0
FAIL=0

assert() {
  desc=$1
  cond=$2
  if [ "$cond" = "yes" ]; then
    PASS=$((PASS + 1))
    printf 'ok    %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s\n' "$desc"
  fi
}

SANDBOX=$(mktemp -d 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/backstop-$$")
mkdir -p "$SANDBOX"
cd "$SANDBOX" || exit 1

git init -q -b main .
git config user.email test@example.invalid
git config user.name "Backstop Test"
printf 'seed\n' > seed.txt
git add seed.txt
git commit -q -m "seed"

CLAUDE_PROJECT_DIR=$SANDBOX
export CLAUDE_PROJECT_DIR

printf '=== 1. dirty exit on a feature branch ===\n'
git checkout -q -b feature/x
printf 'work in progress\n' > wip.txt
BEFORE=$(git rev-parse HEAD)
printf '{"hook_event_name":"Stop"}' | sh "$HOOK" 2>&1 | sed 's/^/  hook: /'
AFTER=$(git rev-parse HEAD)
[ "$BEFORE" != "$AFTER" ] && r=yes || r=no
assert "a backstop commit was created" "$r"
git log --oneline -1 | sed 's/^/  /'
git show --stat --oneline HEAD | sed 's/^/  /' | head -5
git status --porcelain | grep -q . && r=no || r=yes
assert "the worktree is no longer dirty" "$r"
printf '%s' "$(git log -1 --pretty=%s)" | grep -q '^wip: session backstop' && r=yes || r=no
assert "the message marks it as a backstop" "$r"

printf '\n=== 2. clean tree makes no commit ===\n'
BEFORE=$(git rev-parse HEAD)
printf '{"hook_event_name":"Stop"}' | sh "$HOOK" >/dev/null 2>&1
AFTER=$(git rev-parse HEAD)
[ "$BEFORE" = "$AFTER" ] && r=yes || r=no
assert "no commit on a clean tree" "$r"

printf '\n=== 3. the default branch is never committed to ===\n'
git checkout -q main
printf 'loose change\n' > loose.txt
BEFORE=$(git rev-parse HEAD)
printf '{"hook_event_name":"Stop"}' | sh "$HOOK" 2>&1 | sed 's/^/  hook: /'
AFTER=$(git rev-parse HEAD)
[ "$BEFORE" = "$AFTER" ] && r=yes || r=no
assert "main was left alone" "$r"
git status --porcelain | grep -q 'loose.txt' && r=yes || r=no
assert "the change is still there, uncommitted" "$r"

printf '\n=== 4. nothing is pushed ===\n'
grep -q 'git push' "$HOOK" && r=no || r=yes
assert "the hook contains no push" "$r"

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

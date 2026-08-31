#!/bin/sh
# tests-guard.test.sh
#
# The guard is inert until the human locks the test list. These cases prove
# both halves: silent when unlocked, refusing when locked.
#
# Run: sh .claude/hooks/tests-guard.test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
GUARD=$HERE/tests-guard.sh
MARKER=$REPO_ROOT/.tests-locked
CLAUDE_PROJECT_DIR=$REPO_ROOT
export CLAUDE_PROJECT_DIR

PASS=0
FAIL=0
MARKER_PREEXISTING=0
[ -f "$MARKER" ] && MARKER_PREEXISTING=1

payload() {
  node -e '
const [tool, key, value] = process.argv.slice(1);
const ti = {};
ti[key] = value;
process.stdout.write(JSON.stringify({ tool_name: tool, tool_input: ti }));
' "$1" "$2" "$3"
}

expect() {
  want=$1
  desc=$2
  tool=$3
  key=$4
  val=$5
  payload "$tool" "$key" "$val" | sh "$GUARD" 2>/tmp/tg.err
  got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
    printf 'ok    %-38s | %s\n' "$desc" "$val"
    [ "$want" = "2" ] && sed 's/^/               /' /tmp/tg.err
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %-38s | %s (exit %s, expected %s)\n' "$desc" "$val" "$got" "$want"
  fi
}

printf '=== UNLOCKED: guard is inert ===\n'
[ "$MARKER_PREEXISTING" -eq 0 ] || : > /dev/null
if [ "$MARKER_PREEXISTING" -eq 1 ]; then
  mv "$MARKER" "$MARKER.testbak"
fi
expect 0 "edit a test file while unlocked"   Edit file_path "src/audit.test.ts"
expect 0 "snapshot update while unlocked"    Bash command "npx vitest -u"

printf '\n=== LOCKED: guard refuses ===\n'
: > "$MARKER"
# Every path here is tracked in HEAD. That is the point: the marker freezes the
# list a human approved, and "approved" here means "already committed".
expect 2 "edit a tracked test"               Edit file_path "tests/self-audit-green.test.ts"
expect 2 "write a tracked test"              Write file_path "tests/readiness-tool.test.ts"
expect 2 "edit the other tracked suite"      Edit file_path "tests/audit-report-view.test.ts"
expect 2 "vitest -u"                         Bash command "npx vitest -u"
expect 2 "jest --update-snapshot"            Bash command "npx jest --update-snapshot"
expect 2 "redirect into a test file"         Bash command "echo x > src/audit.test.ts"

# The marker protects the tests; something has to protect the marker. An agent
# that can edit it rewrites the lock, and one that can delete it lifts the lock
# and then edits every test above freely.
expect 2 "edit the marker"                   Edit file_path ".tests-locked"
expect 2 "write the marker"                  Write file_path ".tests-locked"
expect 2 "rm the marker"                     Bash command "rm .tests-locked"
expect 2 "rm -f the marker"                  Bash command "rm -f .tests-locked"
expect 2 "mv the marker away"                Bash command "mv .tests-locked /tmp/parked"
expect 2 "unlink the marker"                 Bash command "unlink .tests-locked"
expect 2 "truncate the marker"               Bash command "truncate -s 0 .tests-locked"
expect 2 "redirect into the marker"          Bash command "echo x > .tests-locked"

# A snapshot-update flag is only a snapshot-update flag when a test runner is
# reading it. The first version of this check scanned the whole command for a
# bare `-u` and refused `git push -u` and `cygpath -u` in a single session —
# neither of which can reach a test. `sort -u` was refused too, inside a read.
printf '\n=== LOCKED: -u only counts on a test runner ===\n'
expect 2 "npm test -- -u"                    Bash command "npm test -- -u"
expect 2 "yarn test -U"                      Bash command "yarn test -U"
expect 0 "git push -u"                       Bash command "git push -u origin feature"
expect 0 "cygpath -u"                        Bash command "cygpath -u /tmp"
expect 0 "sort -u in a pipeline"             Bash command "grep -rn foo . | sort -u"
expect 0 "git branch -u"                     Bash command "git branch -u origin/main"
# The flag belongs to the segment it sits in, not to the line.
expect 0 "test run, then a push with -u"     Bash command "npm test && git push -u origin feature"
expect 2 "push, then a test run with -u"     Bash command "git push origin feature && npm test -- -u"

# The marker freezes the approved list. A file nobody has approved is not on it,
# and a plan PR exists precisely to propose one — with the marker inherited from
# main, refusing new test files meant no plan PR could ever be written again.
# The guard suites are excluded outright: integrity.sh governs .claude/hooks,
# and it is the stricter guard, refusing every tool call while they drift.
printf '\n=== LOCKED: proposals and guard suites are not the frozen list ===\n'
expect 0 "write a brand-new test file"       Write file_path "tests/not-yet-proposed.test.ts"
expect 0 "edit a hook suite"                 Edit file_path ".claude/hooks/tests-guard.test.sh"
expect 0 "hook suite, absolute + backslash"  Edit file_path "$REPO_ROOT\\.claude\\hooks\\integrity.test.sh"
# Fails closed: a path it cannot resolve to a repo-relative one is not "new".
# Git Bash rewrites a POSIX argv path for node.exe, so this arrives as
# "C:/Program Files/Git/elsewhere/mystery.test.ts" — which is also the case
# that caught the guard splitting one path into two on the space.
expect 2 "unresolvable absolute test path"   Edit file_path "/elsewhere/mystery.test.ts"
expect 2 "spaced path ending in a test file" Edit file_path "/some dir/tests/x.test.ts"
expect 2 "path escaping the repo"            Edit file_path "../outside/other.test.ts"

printf '\n=== LOCKED: non-test work still flows ===\n'
# S3 is required to read the marker before its first edit, so reading must work.
expect 0 "ls the marker"                     Bash command "ls -la .tests-locked"
expect 0 "cat the marker"                    Bash command "cat .tests-locked"
expect 0 "test -f the marker"                Bash command "test -f .tests-locked"
expect 0 "edit production source"            Edit file_path "index.ts"
expect 0 "run the suite without -u"          Bash command "npx vitest run"
expect 0 "ordinary build"                    Bash command "npm run build"

# Restore whatever marker state we found.
rm -f "$MARKER"
if [ "$MARKER_PREEXISTING" -eq 1 ]; then
  mv "$MARKER.testbak" "$MARKER"
fi

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

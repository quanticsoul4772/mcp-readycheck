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
expect 2 "edit *.test.*"                     Edit file_path "src/audit.test.ts"
expect 2 "edit *.spec.*"                     Write file_path "src/widget.spec.tsx"
expect 2 "edit a snapshot"                   Edit file_path "src/__snapshots__/view.snap"
expect 2 "edit under __tests__/"             Edit file_path "src/__tests__/helper.ts"
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

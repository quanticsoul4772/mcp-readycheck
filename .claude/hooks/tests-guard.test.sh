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

# This suite parks the real marker, writes a fake over it, and restores at the
# end. Between those two points the repository has no lock: the guard's very
# first line is `[ -f "$MARKER" ] || exit 0`, so an interrupted run leaves every
# locked test editable by plain Write, silently, with no refusal printed.
#
# That is not hypothetical. An evaluation's run was killed by a timeout,
# `git status` showed ` D .tests-locked`, and a second run then computed
# MARKER_PREEXISTING from the fake and clobbered the real backup. Recovery was
# accidental. The window was about two and a half minutes wide, and AGENTS.md
# tells agents to run these suites.
#
# Restore on every exit path, not just the happy one. Refuse to start if a
# previous run left its backup behind, rather than overwriting it.
if [ -f "$MARKER.testbak" ]; then
  printf 'A previous run left %s behind.\n' "$MARKER.testbak" >&2
  printf 'Restore it first: mv "%s" "%s"\n' "$MARKER.testbak" "$MARKER" >&2
  exit 1
fi

restore_marker() {
  status=$?
  if [ -f "$MARKER.testbak" ]; then
    mv -f "$MARKER.testbak" "$MARKER"
  elif [ "$MARKER_PREEXISTING" -eq 1 ] && [ ! -f "$MARKER" ]; then
    # The backup is gone and the real marker is not back: recover from git
    # rather than leaving the repository unlocked.
    git -C "$REPO_ROOT" checkout -- .tests-locked 2>/dev/null || :
  elif [ "$MARKER_PREEXISTING" -eq 0 ]; then
    [ -f "$MARKER" ] && command rm -f "$MARKER"
  fi
  exit $status
}
trap restore_marker EXIT INT TERM HUP

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

# Every case below was ALLOWED by the first draft of the proposal rule and
# refused by the guard before it. An evaluation found them by executing the
# guard; reading it found none of them. git is case-sensitive and this
# filesystem is not, and a substring test on an unresolved path is not a
# prefix test.
printf '\n=== LOCKED: canonicalisation, not string matching ===\n'
expect 2 "case variant of a tracked test"    Write file_path "tests/Readiness-Tool.test.ts"
expect 2 "upper-case directory"              Write file_path "TESTS/readiness-tool.test.ts"
expect 2 "traversal out of .claude/hooks"    Write file_path ".claude/hooks/../../tests/readiness-tool.test.ts"
expect 2 "hooks substring inside a name"     Write file_path "notes.claude/hooks/x/../../../tests/readiness-tool.test.ts"
expect 2 "dot-slash prefix"                  Edit file_path "./tests/readiness-tool.test.ts"
expect 2 "windows separators"                Edit file_path "tests\\readiness-tool.test.ts"
# Round 2 refused the two strings round 1 reported and allowed the rest of the
# class: the classifier globs were still case-sensitive, so `.Test.` never
# matched `*.test.*` and the tracked-list lookup was never reached. Same inode,
# same bytes — a Write would have truncated the locked file.
expect 2 "capital extension"                 Write file_path "tests/Readiness-Tool.Test.ts"
expect 2 "capital extension only"            Write file_path "tests/readiness-tool.Test.ts"
expect 2 "all caps"                          Write file_path "tests/READINESS-TOOL.TEST.TS"
expect 2 "the other tracked suite, mixed"    Write file_path "tests/audit-report-view.Test.ts"
expect 2 "redirect, upper case"              Bash command "echo x > tests/READINESS-TOOL.TEST.TS"
# The marker names the same file whatever the case, and deleting it turns the
# whole guard off.
expect 2 "rm the marker, upper case"         Bash command "rm .TESTS-LOCKED"
expect 2 "mv the marker, mixed case"         Bash command "mv .Tests-Locked /tmp/x"
expect 2 "write the marker, upper case"      Write file_path ".TESTS-LOCKED"

printf '\n=== LOCKED: the flag reaches the runner however it is written ===\n'
expect 2 "pipe inside a quoted argument"     Bash command "npx vitest --testNamePattern='a|b' -u"
expect 2 "&& inside a quoted argument"       Bash command "npx vitest -t \"a && b\" -u"
expect 2 "quoted flag"                       Bash command "npx vitest \"-u\""
expect 2 "path-prefixed runner"              Bash command "./node_modules/.bin/jest -u"
expect 2 "runner under sh -c"                Bash command "sh -c \"vitest -u\""
expect 2 "runner under bash -c"              Bash command "bash -c \"npx jest --update-snapshot\""
expect 2 "npm run with a test script"        Bash command "npm run test:unit -- -u"
expect 2 "deno test"                         Bash command "deno test -- -u"
expect 2 "tap"                               Bash command "tap -u"
expect 2 "flag with an = value"              Bash command "npx vitest --update-snapshot=true"
# The boundary: expanding every token on whitespace would refuse this, and a
# guard that refuses commit messages is the false-positive class this repo has
# already paid for twice.
expect 0 "runner named in a commit message"  Bash command "git commit -m \"ran vitest -u earlier\""
# A backslash continuation is not a command boundary. The per-line segmenter
# put the runner in one segment and the flag in the next, while the shell joins
# them and runs `vitest -u`. Not a dataflow problem — pure pattern work.
expect 2 "backslash continuation"            Bash command "npx vitest \\
  -u"
# The -c argument is a command, so it is segmented as one. Splitting it on
# whitespace collapsed its clause boundaries and refused these two while the
# identical unquoted lines were allowed.
expect 0 "quoted compound under sh -c"       Bash command "sh -c \"npm test && git push -u origin main\""
expect 0 "quoted pipeline under sh -c"       Bash command "sh -c \"npm test | sort -u\""
# A URL is never a runner, and a flag that precedes the runner is not the
# runner's flag.
expect 0 "curl against a vitest repo"        Bash command "curl -u tok https://github.com/vitest-dev/vitest"
expect 0 "docker run -u before the runner"   Bash command "docker run -u 1000 node npm test"
# Round 3 found these by generalising past the strings round 2 reported. A
# scheme anywhere in a token is not a URL; `-lc` and `-euc` are `-c`; and the
# marker check is a verb list, so every verb that unlinks has to be in it.
expect 2 "scheme-prefixed runner path"       Bash command "node file:///d/x/vitest -u"
expect 0 "an actual https URL"               Bash command "curl -u tok https://github.com/vitest-dev/vitest"
expect 2 "bash -lc"                          Bash command "bash -lc \"vitest -u\""
expect 2 "sh -euc"                           Bash command "sh -euc \"vitest -u\""
expect 2 "shred the marker"                  Bash command "shred -u .tests-locked"
expect 2 "find the marker and unlink it"     Bash command "find . -name .tests-locked -delete"
# Class coverage for the two fixes above, not just their reported spellings.
expect 2 "directory case variant"            Write file_path "TeStS/Self-Audit-Green.Test.TS"
expect 2 "absolute upper-case marker"        Bash command "rm $REPO_ROOT/.TESTS-LOCKED"
expect 2 "two continuations"                 Bash command "npx vitest \\
  --run \\
  -u"
# Round 4: the widened `-c` pattern must not treat an ordinary c-ending flag as
# introducing a command, and a deletion flag is only a deletion when something
# is walking the tree. Both are reads, and refusing a read is the shape already
# in the mistake log.
expect 0 "grep -c on a source file"          Bash command "grep -c TODO index.ts"
expect 0 "gcc -c"                            Bash command "gcc -c main.c"
expect 0 "grep for the word in the marker"   Bash command "grep -n '\-delete' .tests-locked"
expect 0 "upper-case scheme is still a URL"  Bash command "curl HTTPS://github.com/vitest-dev/vitest -u tok"
expect 2 "rsync --delete onto the marker"    Bash command "rsync -a --delete src/ .tests-locked"
# Round 5: every verb pattern ended in a trailing space, so a verb that was the
# last word on the line matched none of them. One command removed the marker,
# and a removed marker turns the entire guard off for the rest of the session.
expect 2 "verb at end of line"               Bash command "echo .tests-locked | xargs rm"
expect 2 "verb at end, with a path"          Bash command "echo .tests-locked | xargs /bin/rm"
expect 2 "xargs unlink"                      Bash command "printf .tests-locked | xargs unlink"
expect 2 "exec form"                         Bash command "find . -name .tests-locked -exec rm {} ;"
# The runner and flag lists were the last comparisons that still cared about
# case, while paths, the marker and the scheme had all been folded.
expect 2 "upper-case runner"                 Bash command "npx VITEST -u"
expect 2 "mixed-case runner"                 Bash command "npx Vitest -u"
expect 2 "upper-case flag"                   Bash command "npx vitest --UPDATE-SNAPSHOT"
expect 2 "upper-case npm test"               Bash command "npm TEST -- --update-snapshot"
expect 2 "path escaping the repo"            Edit file_path "../outside/other.test.ts"

printf '\n=== LOCKED: non-test work still flows ===\n'
# S3 is required to read the marker before its first edit, so reading must work.
expect 0 "ls the marker"                     Bash command "ls -la .tests-locked"
expect 0 "cat the marker"                    Bash command "cat .tests-locked"
expect 0 "test -f the marker"                Bash command "test -f .tests-locked"
expect 0 "edit production source"            Edit file_path "index.ts"
expect 0 "run the suite without -u"          Bash command "npx vitest run"
expect 0 "ordinary build"                    Bash command "npm run build"

# The fake goes; the trap above puts the real one back on every exit path,
# including the ones that never reach this line.
command rm -f "$MARKER"

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

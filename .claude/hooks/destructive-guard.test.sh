#!/bin/sh
# destructive-guard.test.sh
#
# Every MUST REFUSE case is one concrete instance of a pattern the guard
# claims to block. Every MUST PASS case is a command that merely *mentions* a
# destructive word — the false-positive direction, which is what makes a guard
# usable rather than something people route around.
#
# Run: sh .claude/hooks/destructive-guard.test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
GUARD=$HERE/destructive-guard.sh
CLAUDE_PROJECT_DIR=$REPO_ROOT
export CLAUDE_PROJECT_DIR

PASS=0
FAIL=0

payload() {
  node -e '
const [tool, key, value] = process.argv.slice(1);
const ti = {};
ti[key] = value;
process.stdout.write(JSON.stringify({ tool_name: tool, tool_input: ti }));
' "$1" "$2" "$3"
}

run_guard() {
  payload "$1" "$2" "$3" | sh "$GUARD" 2>/tmp/dg.err
  printf '%s' $?
}

must_refuse() {
  desc=$1
  tool=$2
  key=$3
  val=$4
  code=$(run_guard "$tool" "$key" "$val")
  if [ "$code" = "2" ]; then
    PASS=$((PASS + 1))
    printf 'REFUSED  ok    %-34s | %s\n' "$desc" "$val"
    sed 's/^/                       /' /tmp/dg.err
  else
    FAIL=$((FAIL + 1))
    printf 'REFUSED  FAIL  %-34s | %s (exit %s, expected 2)\n' "$desc" "$val" "$code"
  fi
}

must_pass() {
  desc=$1
  tool=$2
  key=$3
  val=$4
  code=$(run_guard "$tool" "$key" "$val")
  if [ "$code" = "0" ]; then
    PASS=$((PASS + 1))
    printf 'ALLOWED  ok    %-34s | %s\n' "$desc" "$val"
  else
    FAIL=$((FAIL + 1))
    printf 'ALLOWED  FAIL  %-34s | %s (exit %s, expected 0)\n' "$desc" "$val" "$code"
    sed 's/^/                       /' /tmp/dg.err
  fi
}

printf '=== MUST REFUSE ===\n'
must_refuse "rm -rf on a scratch dir"      Bash command "rm -rf ./scratch"
must_refuse "rm -r"                        Bash command "rm -r build"
must_refuse "rm -fr combined short flag"   Bash command "rm -fr node_modules"
must_refuse "rmdir /s"                     Bash command "rmdir /s scratch"
must_refuse "del /s /q"                    Bash command "del /s /q scratch"
must_refuse "git clean"                    Bash command "git clean -fd"
must_refuse "git push --force"             Bash command "git push --force origin main"
must_refuse "git push --force-with-lease"  Bash command "git push --force-with-lease origin main"
must_refuse "git push --all"               Bash command "git push --all origin"
must_refuse "git push --mirror"            Bash command "git push --mirror origin"
must_refuse "git branch -D"                Bash command "git branch -D phase0-floor"
must_refuse "git checkout -- <path>"       Bash command "git checkout -- index.ts"
must_refuse "git restore <path>"           Bash command "git restore index.ts"
must_refuse "git reset --hard"             Bash command "git reset --hard HEAD~1"
must_refuse "git commit --no-verify"       Bash command "git commit --no-verify -m wip"
must_refuse "git commit -n"                Bash command "git commit -n -m wip"
must_refuse "git filter-branch"            Bash command "git filter-branch -f --index-filter x main"
must_refuse "rm outside the repo root"     Bash command "rm -rf /c/Users/rbsmi/AppData/Local/Temp/scratch"
must_refuse "mv outside the repo root"     Bash command "mv README.md ../elsewhere/README.md"
must_refuse "destructive op after &&"      Bash command "npm ci && rm -rf dist"
must_refuse "Write outside the repo root"  Write file_path "/c/Users/rbsmi/evil.txt"

printf '\n=== MUST PASS (false-positive direction) ===\n'
must_pass "the word clean in a string"     Bash command 'echo "time to clean up"'
must_pass "the word force in a message"    Bash command 'git commit -m "force the issue"'
must_pass "grep for a pattern"             Bash command 'grep "rm -rf" docs/decisions/ADR-0002-pr720-transitive-dep.md'
must_pass "a directory named cleanroom"    Bash command "ls cleanroom/"
must_pass "git status"                     Bash command "git status --short"
must_pass "git restore --staged only"      Bash command "git restore --staged index.ts"
must_pass "switching branches"             Bash command "git checkout main"
must_pass "ordinary commit"                Bash command 'git commit -m "ci: add workflow"'
must_pass "npm ci"                         Bash command "npm ci"
must_pass "non-recursive rm in repo"       Bash command "rm .tests-locked"
must_pass "Write inside the repo"          Write file_path "docs/plans/STAGE-PLAN.md"

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

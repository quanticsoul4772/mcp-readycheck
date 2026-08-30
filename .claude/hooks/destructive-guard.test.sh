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
must_refuse "Write to a home dotfile"      Write file_path "$HOME/.bashrc"
must_refuse "Write to the agent's config"  Write file_path "$HOME/.claude/settings.json"
must_refuse "Write to a sibling project"   Write file_path "/d/Projects/other-project/index.ts"

printf '\n=== MUST REFUSE (self-protection) ===\n'
must_refuse "truncating redirect to a hook"   Bash command "echo x > .claude/hooks/bearings.sh"
must_refuse "appending redirect to a hook"    Bash command "echo x >> .claude/hooks/bearings.sh"
must_refuse "redirect with no space"          Bash command "echo x >.claude/hooks/bearings.sh"
must_refuse "redirect to settings.json"       Bash command "echo {} > .claude/settings.json"
must_refuse "redirect via CLAUDE_PROJECT_DIR" Bash command 'echo x > "$CLAUDE_PROJECT_DIR/.claude/hooks/bearings.sh"'
must_refuse "redirect to an absolute hook"    Bash command "echo x > $REPO_ROOT/.claude/hooks/bearings.sh"
must_refuse "fd-qualified redirect"           Bash command "prog 1> .claude/hooks/bearings.sh"
must_refuse "redirect after a pipe"           Bash command "cat src | sed s/a/b/ > .claude/hooks/bearings.sh"
must_refuse "redirect after &&"               Bash command "npm ci && echo x > .claude/settings.json"
must_refuse "backslashed Windows hook path"   Bash command 'echo x > .claude\hooks\bearings.sh'
must_refuse "heredoc, target before the tag"  Bash command "cat > .claude/hooks/bearings.sh <<'EOF'
x
EOF"
must_refuse "heredoc, target after the tag"   Bash command "cat <<'EOF' > .claude/hooks/new.sh
x
EOF"
must_refuse "heredoc, double-quoted tag"      Bash command "cat <<\"EOF\" >> .claude/settings.json
x
EOF"
must_refuse "tee to a hook"                   Bash command "echo x | tee .claude/hooks/bearings.sh"
must_refuse "tee -a to settings.json"         Bash command "echo x | tee -a .claude/settings.json"
must_refuse "cp over a hook"                  Bash command "cp /tmp/evil.sh .claude/hooks/bearings.sh"
must_refuse "cp into the hooks directory"     Bash command "cp /tmp/evil.sh .claude/hooks/"
must_refuse "mv over a hook"                  Bash command "mv /tmp/evil.sh .claude/hooks/bearings.sh"
must_refuse "mv a hook away"                  Bash command "mv .claude/hooks/bearings.sh /tmp/parked.sh"
must_refuse "install over a hook"             Bash command "install -m 755 /tmp/evil.sh .claude/hooks/bearings.sh"
must_refuse "sed -i on a hook"                Bash command "sed -i 's/exit 2/exit 0/' .claude/hooks/destructive-guard.sh"
must_refuse "sed --in-place on settings"      Bash command "sed --in-place 's/a/b/' .claude/settings.json"
must_refuse "sed -i.bak on a hook"            Bash command "sed -i.bak 's/a/b/' .claude/hooks/tests-guard.sh"
must_refuse "sed -i with a pipe delimiter"    Bash command "sed -i 's|exit 2|exit 0|' .claude/hooks/destructive-guard.sh"
must_refuse "sed -i, pipe delim, settings"    Bash command "sed -i 's|a|b|g' .claude/settings.json"

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
must_pass "Write to the session scratchpad" Write file_path "${TEMP:-/tmp}/claude/scratchpad/notes.md"
# The Write tool sends Windows paths forward-slashed, which is a different
# to_posix branch from the backslashed value of $TEMP. Both must resolve.
must_pass "scratchpad, forward-slash form" Write file_path "C:/Users/rbsmi/AppData/Local/Temp/claude/scratchpad/notes.md"
must_pass "Write to /tmp"                  Write file_path "/tmp/analysis.json"
must_pass "Edit a scratch file"            Edit file_path "${TMPDIR:-${TEMP:-/tmp}}/draft.md"

printf '\n=== MUST PASS (self-protection, false-positive direction) ===\n'
must_pass "git diff of a hook"              Bash command "git diff .claude/hooks/bearings.sh"
must_pass "git diff scoped to hooks/"       Bash command "git diff main...HEAD -- .claude/hooks/"
must_pass "cat a hook"                      Bash command "cat .claude/hooks/bearings.sh"
must_pass "grep across the hooks dir"       Bash command 'grep -rn "CLAUDE_PROJECT_DIR" .claude/hooks/'
must_pass "grep, output redirected away"    Bash command 'grep -rn "exit 2" .claude/hooks/ > /tmp/hits.txt'
must_pass "run one hook test suite"         Bash command "sh .claude/hooks/destructive-guard.test.sh"
must_pass "run two hook test suites"        Bash command "sh .claude/hooks/bearings.test.sh; sh .claude/hooks/tests-guard.test.sh"
must_pass "run a suite, redirect elsewhere" Bash command "sh .claude/hooks/bearings.test.sh > /tmp/bearings.log"
must_pass "cat settings.json"               Bash command "cat .claude/settings.json"
# Reading a hook out is not a write to it. (A destination outside the repo
# root is refused by the older cp rule, so the backup lands inside.)
must_pass "copy a hook out to a backup"     Bash command "cp .claude/hooks/bearings.sh docs/bearings.bak"
must_pass "sed without -i reading a hook"   Bash command "sed -n '1,20p' .claude/hooks/bearings.sh"
must_pass "grep for the text of a sed flag"  Bash command "grep -n 'sed -i.bak' .claude/hooks/destructive-guard.test.sh"
must_pass "wc over the hooks dir"           Bash command "wc -l .claude/hooks/destructive-guard.sh"
must_pass "redirect elsewhere entirely"     Bash command "echo x > /tmp/notes.txt"
must_pass "an arrow in a quoted string"     Bash command 'echo "see --> .claude/hooks/README"'
must_pass "tee somewhere else"              Bash command "grep -rn x .claude/hooks/ | tee /tmp/out.txt"
must_pass "a heredoc body quoting a write"  Bash command "cat > /tmp/doc.md <<'EOF'
Never run: echo x > .claude/hooks/bearings.sh
EOF"

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

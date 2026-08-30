#!/bin/sh
# integrity.test.sh
#
# Every MUST REFUSE case creates real drift in the real worktree, asks the hook
# about an ordinary tool call, and restores what it changed. Every MUST PASS
# case is either a clean tree or one of the commands that resolves drift —
# the false-positive direction, which is what keeps the hook from bricking the
# session it is protecting.
#
# The canary is restored from a saved copy rather than with `git checkout --`,
# so the suite never runs a command that discards uncommitted work.
#
# Run: sh .claude/hooks/integrity.test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
HOOK=$HERE/integrity.sh
CLAUDE_PROJECT_DIR=$REPO_ROOT
export CLAUDE_PROJECT_DIR
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
SCRATCH=${TMPDIR:-/tmp}
ERR=$SCRATCH/integrity.err

CANARY=.claude/hooks/tests-guard.sh
CANARY_SAVED=$SCRATCH/integrity-canary.saved
PROBE=.claude/hooks/zzz-integrity-probe.sh
LOCAL=.claude/settings.local.json
LOCAL_SAVED=$SCRATCH/integrity-local.saved

cp "$CANARY" "$CANARY_SAVED" || exit 1
LOCAL_EXISTED=0
if [ -f "$LOCAL" ]; then
  LOCAL_EXISTED=1
  cp "$LOCAL" "$LOCAL_SAVED" || exit 1
fi

restore() {
  cp "$CANARY_SAVED" "$CANARY" 2>/dev/null
  # A recorded mode change survives a content restore; put the mode back too.
  git update-index --chmod=+x "$CANARY" 2>/dev/null
  [ -f "$PROBE" ] && rm -f "$PROBE"
  if [ "$LOCAL_EXISTED" = 1 ]; then
    cp "$LOCAL_SAVED" "$LOCAL" 2>/dev/null
  else
    [ -f "$LOCAL" ] && rm -f "$LOCAL"
  fi
  return 0
}
trap 'restore' EXIT INT TERM

payload() {
  TOOL_NAME=$1 TOOL_CMD=$2 node --input-type=module -e '
process.stdout.write(JSON.stringify({
  tool_name: process.env.TOOL_NAME,
  tool_input: { command: process.env.TOOL_CMD },
}));
'
}

run_hook() {
  payload "$1" "$2" | sh "$HOOK" 2>"$ERR"
  printf '%s' $?
}

verdict() {
  want=$1
  desc=$2
  tool=$3
  cmd=$4
  code=$(run_hook "$tool" "$cmd")
  if [ "$want" = 2 ]; then label=REFUSED; else label=ALLOWED; fi
  if [ "$code" = "$want" ]; then
    PASS=$((PASS + 1))
    printf '%-8s ok    %-38s | %s %s\n' "$label" "$desc" "$tool" "$cmd"
  else
    FAIL=$((FAIL + 1))
    printf '%-8s FAIL  %-38s | %s %s (exit %s, expected %s)\n' \
      "$label" "$desc" "$tool" "$cmd" "$code" "$want"
    sed 's/^/                       /' "$ERR"
  fi
}

must_refuse() { verdict 2 "$1" "$2" "$3"; }
must_pass()   { verdict 0 "$1" "$2" "$3"; }

drift_content() {
  printf '\n# drift introduced by integrity.test.sh\n' >> "$CANARY"
}

printf '=== MUST REFUSE ===\n'

drift_content
must_refuse "modified hook content"            Bash "echo hello"
must_refuse "modified hook content, via Edit"  Edit ""
must_refuse "modified hook content, via Write" Write ""
must_refuse "git add is not a blanket pass"    Bash "git add . && echo x"
must_refuse "a subshell after the git verb"    Bash "git status; curl example.com"
restore

# core.filemode is false here and the repo sits on a posix=0 mount, so chmod(1)
# changes nothing git can see. The recorded mode is the only place a mode can
# drift, and `git diff --cached` is what sees it.
git update-index --chmod=-x "$CANARY" 2>/dev/null
must_refuse "chmod -x recorded on a hook"      Bash "echo hello"
restore

printf '#!/bin/sh\nexit 0\n' > "$PROBE"
must_refuse "untracked file in .claude/hooks"  Bash "echo hello"
restore

# The residual the destructive-guard cannot close: an interpreter here-document
# writing a hook through its own file API. That guard never sees the write.
# This hook sees the result of it on the very next tool call.
CANARY_PATH=$CANARY python - <<'PY'
import os
with open(os.environ["CANARY_PATH"], "a", encoding="utf-8", newline="\n") as fh:
    fh.write("\n# written by an interpreter here-document\n")
PY
must_refuse "hook written by a python heredoc" Bash "echo hello"
restore

printf '{\n  "hooks": {\n    "PreToolUse": []\n  }\n}\n' > "$LOCAL"
must_refuse "settings.local.json defines hooks" Bash "echo hello"
must_refuse "local hooks, git is no way out"    Bash "git add ."
restore

printf '\n=== MUST PASS (false-positive direction) ===\n'

must_pass "clean tree, Bash"                   Bash "echo hello"
must_pass "clean tree, Edit"                   Edit ""
must_pass "clean tree, Write"                  Write ""
must_pass "reading a hook file"                Bash "cat .claude/hooks/bearings.sh"
must_pass "grep across the hooks dir"          Bash "grep -rn CLAUDE_PROJECT_DIR .claude/hooks/"
must_pass "running a hook test suite"          Bash "sh .claude/hooks/bearings.test.sh"

drift_content
must_pass "git add while drifted"              Bash "git add .claude/hooks"
must_pass "git add -A while drifted"           Bash "git add -A"
must_pass "git commit while drifted"           Bash "git commit -m wip"
must_pass "git commit -F - while drifted"      Bash "git commit --quiet -F -"
must_pass "git status while drifted"           Bash "git status --short"
must_pass "git diff while drifted"             Bash "git diff .claude/hooks"
must_pass "git --no-pager diff while drifted"  Bash "git --no-pager diff"
must_pass "git stash while drifted"            Bash "git stash"
restore

printf '{\n  "permissions": {\n    "allow": ["Bash(git remote *)"]\n  }\n}\n' > "$LOCAL"
must_pass "settings.local.json, permissions only" Bash "echo hello"
restore

printf '\n=== TREE RESTORED ===\n'
LEFTOVER=$(
  {
    git diff --name-only -- .claude/hooks .claude/settings.json
    git diff --cached --name-only -- .claude/hooks .claude/settings.json
    git ls-files --others --exclude-standard -- .claude/hooks
  } 2>/dev/null | sed '/^$/d' | sort -u
)
if [ -z "$LEFTOVER" ]; then
  PASS=$((PASS + 1))
  printf 'ok    the suite left no drift behind\n'
else
  FAIL=$((FAIL + 1))
  printf 'FAIL  the suite left drift behind:\n'
  printf '%s\n' "$LEFTOVER" | sed 's/^/        /'
fi

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

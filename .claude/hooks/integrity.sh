#!/bin/sh
# integrity.sh — PreToolUse hook (Bash, Edit, Write, MultiEdit).
#
# The other hooks decide whether an operation is safe. This one decides whether
# those hooks are still the ones that were reviewed. Before any tool call runs,
# everything in .claude/hooks and the registration in .claude/settings.json is
# compared against committed HEAD. A difference means the enforcement in force
# is not the enforcement that was merged, so the call is refused until the
# difference is committed or reverted.
#
# Registered first, so the attestation happens before the other hooks decide.
#
# Contract: exit 0 allows the tool call; exit 2 blocks it and returns the
# stderr text to the model. This hook NEVER asks for confirmation.
#
# Mode bits: `git diff --cached` compares the recorded mode against HEAD, so a
# staged chmod is caught wherever git records one. Where core.filemode is true,
# `git diff` catches an unstaged one as well. On a mount with posix=0 — the
# Windows case — chmod(1) does not change anything for git to see, and the
# recorded mode is the only place a mode can drift at all.
set -u

REPO_ROOT=${CLAUDE_PROJECT_DIR:-}
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
cd "$REPO_ROOT" 2>/dev/null || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# Nothing committed yet means nothing to attest against.
git rev-parse --verify HEAD >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat)

FIELDS=$(printf '%s' "$PAYLOAD" | node -e '
let raw = "";
process.stdin.on("data", d => raw += d);
process.stdin.on("end", () => {
  let d = {};
  try { d = JSON.parse(raw); } catch (e) { }
  const ti = d.tool_input || {};
  const b64 = s => Buffer.from(String(s == null ? "" : s), "utf8").toString("base64");
  process.stdout.write("TOOL=" + b64(d.tool_name) + "\n");
  process.stdout.write("CMD=" + b64(ti.command) + "\n");
});
' 2>/dev/null)

[ -z "$FIELDS" ] && exit 0

d64() { printf '%s' "$1" | base64 -d 2>/dev/null; }
TOOL=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^TOOL=//p')")
CMD=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^CMD=//p')")

HOOKS_DIR=.claude/hooks
SETTINGS=.claude/settings.json
LOCAL_SETTINGS=.claude/settings.local.json

refuse() {
  printf 'BLOCKED by integrity: %s\n' "$1" >&2
  shift
  for line in "$@"; do
    printf '%s\n' "$line" >&2
  done
  printf '  This hook never confirms. Commit or revert the change, or ask the human.\n' >&2
  exit 2
}

# --- unreviewed local hook overrides ---------------------------------------
# .claude/settings.local.json is gitignored, so nothing in it was ever
# reviewed. Permissions there are ordinary per-developer preference; a "hooks"
# key is a second, invisible enforcement configuration, and no amount of
# committing resolves it. Refused unconditionally, including for git.
if [ -f "$LOCAL_SETTINGS" ]; then
  if LOCAL_SETTINGS_PATH=$LOCAL_SETTINGS node --input-type=module -e '
import { readFileSync } from "node:fs";
try {
  const j = JSON.parse(readFileSync(process.env.LOCAL_SETTINGS_PATH, "utf8"));
  const has = j && typeof j === "object" && Object.prototype.hasOwnProperty.call(j, "hooks");
  process.exit(has ? 0 : 1);
} catch (e) {
  process.exit(1);
}
' 2>/dev/null; then
    refuse "$LOCAL_SETTINGS defines hooks" \
      "  That file is gitignored, so its hooks were never reviewed and no commit" \
      "  can bring them under review. Move them to $SETTINGS or remove the key." \
      "  Permissions in that file are fine; only a \"hooks\" key is refused."
  fi
fi

# --- drift against committed HEAD ------------------------------------------
# Worktree vs index, index vs HEAD, and files that are in neither.
DRIFT=$(
  {
    git diff --name-only -- "$HOOKS_DIR" "$SETTINGS"
    git diff --cached --name-only -- "$HOOKS_DIR" "$SETTINGS"
    git ls-files --others --exclude-standard -- "$HOOKS_DIR"
  } 2>/dev/null | sed '/^$/d' | sort -u
)

[ -z "$DRIFT" ] && exit 0

# --- the way out -----------------------------------------------------------
# Committing the drift is how it stops being drift, so the commands that do
# that stay available while everything else is refused. The command must be a
# single simple one: a compound line could carry anything after the git verb.
is_drift_resolution() {
  [ "$TOOL" = "Bash" ] || return 1
  [ -n "$CMD" ] || return 1
  first=$(printf '%s\n' "$CMD" | head -1)
  case "$first" in
    *';'*|*'&'*|*'|'*|*'`'*|*'$('*) return 1 ;;
  esac
  printf '%s\n' "$first" \
    | grep -qE '^[[:space:]]*git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(add|commit|diff|status|stash)([[:space:]]|$)'
}

is_drift_resolution && exit 0

LIST=$(printf '%s\n' "$DRIFT" | sed 's/^/    /')
refuse "the hooks in force differ from the hooks committed at HEAD" \
  "  drifted path(s):" \
  "$LIST" \
  "  Refusing $TOOL until the difference is reviewed and committed." \
  "  git add / git commit / git diff / git status / git stash stay available."

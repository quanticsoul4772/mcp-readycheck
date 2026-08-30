#!/bin/sh
# sessionstart-registration.test.sh
#
# bearings.sh passed its own suite while the session hook appeared dead. It was
# not dead — SessionStart output goes to Claude's context and is never printed
# to the terminal, so there was nothing to see. The one thing that suite could
# not catch was a registration that silently skips a session kind.
#
# This proves the wiring, not the script: SessionStart is registered, its
# matcher covers every documented session_kind, and the command it names is a
# file that exists.
#
# Run: sh .claude/hooks/sessionstart-registration.test.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
SETTINGS=$REPO_ROOT/.claude/settings.json

PASS=0
FAIL=0

report() {
  if [ "$1" = "ok" ]; then
    PASS=$((PASS + 1))
    printf 'ok    %s\n' "$2"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %s\n' "$2"
  fi
}

printf '=== SESSIONSTART REGISTRATION ===\n'

OUT=$(SETTINGS_PATH=$SETTINGS SETTINGS_REPO_ROOT=$REPO_ROOT node --input-type=module -e '
import { readFileSync, existsSync } from "node:fs";
// With `node -e`, process.argv has no script slot, so pass paths via the
// environment rather than guessing the argv offset.
const settingsPath = process.env.SETTINGS_PATH;
const repoRoot = process.env.SETTINGS_REPO_ROOT;

// The five values Claude Code can report as session_kind. A matcher that omits
// one gives that session no bearings and no error.
const KINDS = ["startup", "resume", "clear", "compact", "fork"];

const say = (ok, desc) => console.log((ok ? "ok" : "no") + "\t" + desc);

const settings = JSON.parse(readFileSync(settingsPath, "utf8"));
const entries = settings?.hooks?.SessionStart ?? [];
say(entries.length > 0, "SessionStart is registered in .claude/settings.json");

// A matcher of letters and "|" is read as a list of exact strings, not a regex.
const covered = new Set(
  entries.flatMap((e) =>
    (e.matcher ?? KINDS.join("|")).split(/[|,]/).map((s) => s.trim())
  )
);
for (const kind of KINDS) {
  say(covered.has(kind), `matcher covers session kind "${kind}"`);
}

const handlers = entries.flatMap((e) => e.hooks ?? []);
say(handlers.length > 0, "SessionStart declares at least one handler");

for (const h of handlers) {
  say(h.type === "command", `handler type is "command" (got "${h.type}")`);
  // command is: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>"
  const m = /\$CLAUDE_PROJECT_DIR\/([^"]+)/.exec(h.command ?? "");
  say(Boolean(m), "handler command resolves through $CLAUDE_PROJECT_DIR");
  if (m) {
    say(existsSync(repoRoot + "/" + m[1]), `handler script exists: ${m[1]}`);
  }
}
' 2>&1)

if [ -z "$OUT" ]; then
  printf 'FAIL  could not read the registration (node failed)\n'
  printf '\n=== SUMMARY: 0 passed, 1 failed ===\n'
  exit 1
fi

printf '%s\n' "$OUT" | while IFS= read -r line; do :; done
OLDIFS=$IFS
IFS='
'
for line in $OUT; do
  verdict=${line%%	*}
  desc=${line#*	}
  case "$verdict" in
    ok) report ok "$desc" ;;
    no) report no "$desc" ;;
    *)  report no "unexpected output: $line" ;;
  esac
done
IFS=$OLDIFS

printf '\n=== SUMMARY: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

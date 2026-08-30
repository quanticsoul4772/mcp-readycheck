#!/bin/sh
# destructive-guard.sh — PreToolUse hook.
#
# Refuses destructive operations before they run. Fires even under
# --dangerously-skip-permissions, because it is a hook rather than a
# permission prompt.
#
# Contract: exit 0 allows the tool call; exit 2 blocks it and returns the
# stderr text to the model. This hook NEVER asks for confirmation — that
# conversation happens with the human, outside the hook.
#
# JSON parsing uses node, which is guaranteed present in this repo (it is a
# Node project). All decision logic below is POSIX sh.
set -u

REPO_ROOT=${CLAUDE_PROJECT_DIR:-}
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
REPO_ROOT=$(cd "$REPO_ROOT" 2>/dev/null && pwd || printf '%s' "$REPO_ROOT")

PAYLOAD=$(cat)

# --- field extraction ------------------------------------------------------
FIELDS=$(printf '%s' "$PAYLOAD" | node -e '
let raw = "";
process.stdin.on("data", d => raw += d);
process.stdin.on("end", () => {
  let d = {};
  try { d = JSON.parse(raw); } catch (e) { }
  const ti = d.tool_input || {};
  const b64 = s => Buffer.from(String(s == null ? "" : s), "utf8").toString("base64");
  const paths = [ti.file_path, ti.path, ti.notebook_path].filter(Boolean).join("\n");
  process.stdout.write("TOOL=" + b64(d.tool_name) + "\n");
  process.stdout.write("CMD=" + b64(ti.command) + "\n");
  process.stdout.write("PATHS=" + b64(paths) + "\n");
});
' 2>/dev/null)

[ -z "$FIELDS" ] && exit 0

d64() { printf '%s' "$1" | base64 -d 2>/dev/null; }

TOOL=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^TOOL=//p')")
CMD=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^CMD=//p')")
PATHS=$(d64 "$(printf '%s\n' "$FIELDS" | sed -n 's/^PATHS=//p')")

SEGMENT=$CMD

block() {
  reason=$1
  refused=$2
  targets=${3:-}
  printf 'BLOCKED by destructive-guard: %s\n' "$reason" >&2
  printf '  refused command: %s\n' "$refused" >&2
  if [ -n "$targets" ]; then
    printf '  target path(s):\n' >&2
    printf '%s\n' "$targets" | while IFS= read -r t; do
      [ -n "$t" ] && printf '    %s\n' "$t" >&2
    done
  fi
  printf '  This hook never confirms. Ask the human, naming the exact paths.\n' >&2
  exit 2
}

# --- path containment ------------------------------------------------------
# Windows-style paths reach the hook as C:/... ; normalise them so a prefix
# comparison against a POSIX root means something.
to_posix() {
  p=$1
  case "$p" in
    [A-Za-z]:[/\\]*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$p" 2>/dev/null || printf '%s' "$p"
      else
        drive=$(printf '%s' "$p" | cut -c1 | tr 'A-Z' 'a-z')
        rest=$(printf '%s' "$p" | cut -c3- | tr '\\' '/')
        printf '/%s%s' "$drive" "$rest"
      fi
      ;;
    *) printf '%s' "$p" ;;
  esac
}

# Absolute, normalised, POSIX. Empty for a token that is not a path at all.
norm_abs() {
  p=$1
  case "$p" in
    -*) return 1 ;;
  esac
  case "$p" in
    /*|[A-Za-z]:[/\\]*) abs=$(to_posix "$p") ;;
    *..*)               abs=$PWD/$p ;;
    *)                  return 1 ;;
  esac
  realpath -m "$abs" 2>/dev/null || printf '%s' "$abs"
  return 0
}

under() {
  case "$1" in
    "$2"|"$2"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Deletes and moves are held to the repository root: destroying something
# outside the project is never this agent's call to make.
outside_repo() {
  abs=$(norm_abs "$1") || return 1
  under "$abs" "$REPO_ROOT" && return 1
  return 0
}

# Writes are held to an allow-list instead. The repository is where the work
# lives; the OS temp tree is where the harness tells the agent to put scratch
# files, and refusing that would break ordinary work while protecting nothing —
# the targets worth refusing (shell profiles, SSH keys, the agent's own global
# configuration) sit under $HOME, outside every allowed root.
WRITE_ROOTS=$REPO_ROOT
for candidate in "${TMPDIR:-}" "${TEMP:-}" "${TMP:-}" /tmp; do
  [ -n "$candidate" ] || continue
  croot=$(to_posix "$candidate")
  croot=$(realpath -m "$croot" 2>/dev/null || printf '%s' "$croot")
  case "$WRITE_ROOTS" in
    *"$croot"*) ;;
    *) WRITE_ROOTS="$WRITE_ROOTS
$croot" ;;
  esac
done

write_denied() {
  abs=$(norm_abs "$1") || return 1
  oldifs=$IFS
  IFS='
'
  for root in $WRITE_ROOTS; do
    IFS=$oldifs
    [ -n "$root" ] || continue
    if under "$abs" "$root"; then
      return 1
    fi
    IFS='
'
  done
  IFS=$oldifs
  return 0
}

check_paths_outside() {
  verb=$1
  shift
  bad=""
  for tok in "$@"; do
    if outside_repo "$tok"; then
      bad="$bad$tok
"
    fi
  done
  if [ -n "$bad" ]; then
    block "$verb targets a path outside the repository root ($REPO_ROOT)" "$SEGMENT" "$bad"
  fi
  return 0
}

has_tok() {
  want=$1
  shift
  for t in "$@"; do
    [ "$t" = "$want" ] && return 0
  done
  return 1
}

non_flags() {
  for t in "$@"; do
    case "$t" in
      -*|/*) ;;
      *) printf '%s\n' "$t" ;;
    esac
  done
}

# --- file-writing tools ----------------------------------------------------
case "$TOOL" in
  Edit|Write|NotebookEdit|MultiEdit)
    if [ -n "$PATHS" ]; then
      for p in $PATHS; do
        [ -z "$p" ] && continue
        if write_denied "$p"; then
          roots=$(printf '%s' "$WRITE_ROOTS" | tr '\n' ' ')
          block "$TOOL writes outside every writable root ($roots)" "$TOOL $p" "$p"
        fi
      done
    fi
    exit 0
    ;;
esac

[ "$TOOL" = "Bash" ] || exit 0
[ -z "$CMD" ] && exit 0

# --- segment the command line ---------------------------------------------
NL='
'
SEGMENTS=$(printf '%s' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g' -e 's/|/\n/g')

OLDIFS=$IFS
IFS=$NL
for SEGMENT in $SEGMENTS; do
  IFS=$OLDIFS

  # Shell-aware tokenisation. xargs applies shell quoting rules without
  # executing anything, so `-m "force the issue"` becomes one argument token
  # rather than three, and `grep "rm -rf" file` keeps grep as the first word.
  #
  # The explicit `printf` matters: bare `xargs -n1` defaults to `echo`, and
  # `echo -n` consumes its own argument, so flag tokens like -n, -e and -E
  # would silently vanish before the guard could match them.
  TOKENS=$(printf '%s\n' "$SEGMENT" | xargs -n1 printf '%s\n' 2>/dev/null) || TOKENS=""
  if [ -z "$TOKENS" ]; then
    TOKENS=$(printf '%s\n' "$SEGMENT" | tr ' \t' "$NL$NL")
  fi

  set -f
  IFS=$NL
  # shellcheck disable=SC2086
  set -- $TOKENS
  IFS=$OLDIFS
  set +f

  # Strip leading VAR=value assignments and transparent prefixes.
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*) shift ;;
      sudo|env|command|time|nohup|exec) shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 0 ] && { IFS=$NL; continue; }

  VERB=$(basename "$1" 2>/dev/null || printf '%s' "$1")
  shift

  case "$VERB" in
    rm)
      if has_tok -rf "$@" || has_tok -fr "$@" || has_tok -r "$@" || has_tok -R "$@" \
         || has_tok --recursive "$@" \
         || printf '%s\n' "$@" | grep -qE '^-[a-zA-Z]*[rR][a-zA-Z]*$'; then
        block "recursive delete" "$SEGMENT" "$(non_flags "$@")"
      fi
      check_paths_outside "delete" "$@"
      ;;
    rmdir)
      if has_tok /s "$@" || has_tok /S "$@"; then
        block "recursive directory delete" "$SEGMENT" "$(non_flags "$@")"
      fi
      check_paths_outside "rmdir" "$@"
      ;;
    del|erase)
      if has_tok /s "$@" || has_tok /S "$@" || has_tok /q "$@" || has_tok /Q "$@"; then
        block "recursive or quiet delete" "$SEGMENT" "$(non_flags "$@")"
      fi
      check_paths_outside "del" "$@"
      ;;
    mv|cp)
      check_paths_outside "$VERB" "$@"
      ;;
    git)
      # Skip git global options to reach the subcommand.
      while [ $# -gt 0 ]; do
        case "$1" in
          -C|-c|--git-dir|--work-tree)
            shift
            [ $# -gt 0 ] && shift
            ;;
          --no-pager|--paginate|--bare) shift ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      [ $# -eq 0 ] && { IFS=$NL; continue; }
      SUB=$1
      shift

      case "$SUB" in
        clean)
          block "git clean discards untracked files irreversibly" "$SEGMENT" "$(non_flags "$@")"
          ;;
        reset)
          has_tok --hard "$@" && block "git reset --hard discards uncommitted work" "$SEGMENT"
          ;;
        push)
          for t in "$@"; do
            case "$t" in
              --force|-f|--force-with-lease|--force-with-lease=*|--force-if-includes)
                block "force push rewrites published history" "$SEGMENT"
                ;;
              --all|--mirror)
                block "git push $t publishes every local ref, including backup branches that may hold removed content" "$SEGMENT"
                ;;
              --no-verify)
                block "git push --no-verify skips pre-push hooks" "$SEGMENT"
                ;;
            esac
          done
          ;;
        branch)
          has_tok -D "$@" && block "git branch -D force-deletes an unmerged branch" "$SEGMENT" "$(non_flags "$@")"
          if has_tok -d "$@" && has_tok --force "$@"; then
            block "git branch -d --force force-deletes an unmerged branch" "$SEGMENT" "$(non_flags "$@")"
          fi
          ;;
        checkout)
          has_tok -- "$@" && block "git checkout -- <path> discards uncommitted changes" "$SEGMENT" "$(non_flags "$@")"
          if has_tok -f "$@" || has_tok --force "$@"; then
            block "git checkout --force discards uncommitted changes" "$SEGMENT" "$(non_flags "$@")"
          fi
          ;;
        restore)
          # --staged on its own only unstages; anything else touches the worktree.
          only_staged=1
          saw_staged=0
          for t in "$@"; do
            case "$t" in
              --staged) saw_staged=1 ;;
              -*) only_staged=0 ;;
              *) ;;
            esac
          done
          if [ "$only_staged" -eq 1 ] && [ "$saw_staged" -eq 1 ]; then
            :
          else
            block "git restore discards uncommitted changes in the worktree" "$SEGMENT" "$(non_flags "$@")"
          fi
          ;;
        commit)
          has_tok --no-verify "$@" && block "git commit --no-verify skips the pre-commit hooks" "$SEGMENT"
          has_tok -n "$@" && block "git commit -n is --no-verify" "$SEGMENT"
          ;;
        filter-branch|filter-repo)
          block "history rewrite" "$SEGMENT"
          ;;
      esac
      ;;
  esac

  IFS=$NL
done
IFS=$OLDIFS

exit 0

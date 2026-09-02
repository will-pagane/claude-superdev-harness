#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
. "$HERE/verify/lib.sh"
G="$HOME/.claude/skills/session-build/scripts/gate.sh"
cd "$REPO" || { bad "cannot cd $REPO"; finish; }

run() {  # run <label> <command...>
  line=$("$G" "$@" 2>&1) ; rc=$?
  printf '%s\n' "$line"
  case "$line" in
    *" EXIT 0 "*)      ok   "$1" ;;
    *" UNDECIDED "*)   bad  "$1 - gate did not complete" ;;
    *WRAPPER_ERROR*)   bad  "$1 - wrapper error" ;;
    *)                 bad  "$1 - rc=$rc" ;;
  esac
}

run install-sh-parse bash -n install.sh
run statusline-parse node --check statusline/statusline.mjs
run settings-json node -e "JSON.parse(require('fs').readFileSync('settings.example.json','utf8'))"

# `for f in $(find ...)` splits on whitespace, which breaks on any path
# containing a space. Round 2 caught it; -print0 with a while-read avoids it.
# The loop body runs in THIS shell (process substitution, not a pipe), so
# FAILED survives - a pipe would put it in a subshell and lose every failure.
while IFS= read -r -d '' f; do
  run "sh-$(printf '%s' "$f" | tr '/.' '--')" bash -n "$f"
done < <(find skills -name '*.sh' -print0)

while IFS= read -r -d '' f; do
  run "js-$(printf '%s' "$f" | tr '/.' '--')" node --check "$f"
done < <(find skills \( -name '*.mjs' -o -name '*.js' \) -print0)

while IFS= read -r -d '' f; do
  run "py-$(printf '%s' "$f" | tr '/.' '--')" python -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$f"
done < <(find skills -name '*.py' -print0)

finish

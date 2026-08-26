#!/usr/bin/env bash
# gate.sh — run one command so its exit status cannot be swallowed.
#
# Why this is a script and not a rule: the rule does not work. "Never pipe a
# command whose failure matters" was stated four times in an earlier version of
# this skill and violated more than twenty times across real runs anyway,
# including by orchestrators who had warned their own forks about it minutes
# earlier. Knowing the trap does not immunise you against it. A script does.
#
# It captures stdout+stderr to a file, reads $? directly from the command with
# nothing in between, and prints ONE machine-readable line. Nothing here pipes
# the command, so nothing here can report a pipeline's status instead of the
# command's. (The classic failure: `git push | tail` exits 0 because tail did,
# while nothing reached the remote. And the classic bad fix: PIPESTATUS is a
# bashism that expands to nothing under zsh, so the repair reads as success a
# second time.)
#
# NOTE: duplicated verbatim in skills/session-end/scripts/gate.sh. The installer
# copies each skills/<name>/ directory as a unit, so a shared directory would
# install as a skill with no SKILL.md. Duplication is the lesser defect.
# Change both or neither.
#
# Usage:
#   scripts/gate.sh <label> <command> [args...]
#   scripts/gate.sh typecheck npm run typecheck
#   scripts/gate.sh --prove-red <label> <command> [args...]
#
# Output, always exactly one line on stdout:
#   GATE <label> EXIT <code> LOG <path> LINES <n>
#
# The script exits with the command's own status, so it composes in an `if`.
# Read the LOG when you need the output. Do not pipe this script either — you
# do not need to, the output is already one line.

set -u

OUT_DIR="${GATE_LOG_DIR:-${TMPDIR:-/tmp}}"
PROVE_RED=false

if [ "${1:-}" = "--prove-red" ]; then
  PROVE_RED=true
  shift
fi

if [ "$#" -lt 2 ]; then
  echo "usage: gate.sh [--prove-red] <label> <command> [args...]" >&2
  exit 64
fi

label="$1"
shift

case "$label" in
  '' | *[!A-Za-z0-9_.-]* )
    echo "gate.sh: label must match [A-Za-z0-9_.-]+, got: $label" >&2
    exit 64
    ;;
esac

mkdir -p "$OUT_DIR" 2>/dev/null || true
log="$OUT_DIR/gate-$label.log"

# The whole point of this file. No pipe, no command substitution, no `&&`.
"$@" > "$log" 2>&1
code=$?

lines=0
if [ -f "$log" ]; then
  lines=$(wc -l < "$log")
  lines=${lines// /}
fi

echo "GATE $label EXIT $code LOG $log LINES $lines"

# --prove-red answers what an inventory of green checks cannot: is this gate
# structurally capable of failing? A gate that exits 0 without checking anything
# is indistinguishable from a pass until you make it go red on purpose.
if [ "$PROVE_RED" = true ]; then
  if [ "$code" -eq 0 ]; then
    echo "GATE $label PROVE_RED INCONCLUSIVE - ran clean; re-run against a known-bad input" >&2
  else
    echo "GATE $label PROVE_RED OK - this gate can return non-zero" >&2
  fi
fi

exit "$code"

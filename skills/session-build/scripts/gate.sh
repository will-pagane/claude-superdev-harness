#!/usr/bin/env bash
# gate.sh — run one command so its exit status cannot be swallowed.
#
# Why this is a script and not a rule: the rule does not work. "Never pipe a
# command whose failure matters" was stated four times in an earlier version of
# this skill and violated more than twenty times across real runs anyway,
# including by orchestrators who had warned their own forks about it minutes
# earlier. Knowing the trap does not immunise you against it. A script does.
#
# WHAT THIS GUARANTEES, precisely — read this before quoting it:
#   * For a DIRECT argv command, the reported EXIT is that command's own status.
#     Nothing stands between the command finishing and $? being read.
#   * A failure to open the log is reported as a WRAPPER error, never as the
#     command's exit code, and the command does not run.
#   * With --expect <literal>, a log not containing that literal reports
#     UNDECIDED and exits 75. UNDECIDED is neither red nor green: it is absent
#     verification. Never merge off it and never report it as a failure -
#     re-run the gate scoped, split or backgrounded.
#
# NOTE: duplicated verbatim in the other session-* skill's scripts/gate.sh.
# Change both or neither.
#
# WHAT IT CANNOT GUARANTEE: if you hand it a shell interpreter and a script
# string, the shell owns the exit status, not this file. `gate.sh x sh -c 'foo |
# tail'` reports tail's status — exactly the bug this exists to prevent. So
# interpreter invocations are REJECTED unless you opt in with --shell, which
# runs the string under `bash -o pipefail -e` so a failing stage still surfaces.
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
#   scripts/gate.sh --shell <label> 'cmd1 | cmd2'      # pipefail is forced on
#
# Output, always exactly one line on stdout:
#   GATE <label> EXIT <code> LOG <path> LINES <n>
# or, when the wrapper itself failed and the command never ran:
#   GATE <label> WRAPPER_ERROR <reason>
#
# The script exits with the command's own status, so it composes in an `if`.
# Wrapper errors exit 70 and print a WRAPPER_ERROR record. Note that 70 is NOT a
# reserved code — a command under test can exit 70 too — so the two cases are
# told apart by the RECORD TYPE on stdout (`GATE … WRAPPER_ERROR …` versus
# `GATE … EXIT …`), never by the exit code alone.
# Read the LOG when you need the output. Do not pipe this script either — you
# do not need to, the output is already one line.

set -u

OUT_DIR="${GATE_LOG_DIR:-${TMPDIR:-/tmp}}"
PROVE_RED=false
ALLOW_SHELL=false
EXPECT=""

while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --prove-red) PROVE_RED=true; shift ;;
    --shell)     ALLOW_SHELL=true; shift ;;
    --expect)    shift
                 [ "$#" -gt 0 ] || { echo "gate.sh: --expect needs a pattern" >&2; exit 64; }
                 EXPECT="$1"; shift ;;
    *)           break ;;
  esac
done

wrapper_error() {
  echo "GATE ${1:--} WRAPPER_ERROR $2"
  exit 70
}

if [ "$#" -lt 2 ]; then
  echo "usage: gate.sh [--prove-red] [--shell] [--expect <literal>] <label> <command> [args...]" >&2
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

# Reject interpreter invocations unless --shell. Without this the caller can
# hand the exit status to a pipeline and this script will faithfully report the
# pipeline's — the precise failure it exists to prevent.
if [ "$ALLOW_SHELL" = false ]; then
  case "$(basename -- "$1")" in
    sh|bash|zsh|dash|ksh|busybox|env)
      for a in "$@"; do
        if [ "$a" = "-c" ]; then
          wrapper_error "$label" "refusing '$1 -c <string>': the shell would own the exit status. Pass a direct argv command, or opt in with --shell (runs under 'bash -o pipefail -e')."
        fi
      done
      ;;
  esac
fi

if ! mkdir -p "$OUT_DIR" 2>/dev/null; then
  wrapper_error "$label" "cannot create log dir: $OUT_DIR"
fi

# A unique log per invocation. A predictable name lets a concurrent run with the
# same label clobber this one, and lets a pre-existing symlink or unwritable
# file turn a redirection failure into something that looks like a gate result.
log=$(mktemp "$OUT_DIR/gate-$label.XXXXXX.log" 2>/dev/null) || \
  wrapper_error "$label" "cannot create log file under $OUT_DIR"

# Prove the log is writable BEFORE running, so a redirection failure can never
# be misread as the command's exit code.
: > "$log" 2>/dev/null || wrapper_error "$label" "log not writable: $log"

# The whole point of this file. No pipe, no command substitution, no `&&`
# between the command finishing and $? being read.
if [ "$ALLOW_SHELL" = true ]; then
  bash -o pipefail -e -c "$*" > "$log" 2>&1
  code=$?
else
  "$@" > "$log" 2>&1
  code=$?
fi

lines=0
if [ -f "$log" ]; then
  lines=$(wc -l < "$log")
  lines=${lines// /}
fi

# --expect answers a question the exit code cannot: did the gate FINISH?
# A suite killed mid-run returns 1 and is indistinguishable from a red - seven
# of twenty observed close-outs hit that, and at least two triaged a killed run
# as a failing one. So the caller names a fragment of the runner's own summary
# line, and a log without it is reported as UNDECIDED: not red, not green, no
# verification. Checked regardless of exit code - a command that exits 0 having
# printed no summary is a runner that did nothing, which is worse, not better.
#
# The match is a FIXED STRING, not a regex: grep -E speaks POSIX ERE and
# PowerShell's Select-String speaks .NET, so one flag documented as "a regex"
# would mean two different things on the two platforms. Runner summary lines
# are literal text, so the regex bought nothing and cost portability.
#
# NOTE 75 is EX_TEMPFAIL and is NOT reserved: a command under test can exit 75
# too. Tell the cases apart by the RECORD TYPE on stdout (`GATE ... UNDECIDED`
# versus `GATE ... EXIT`), never by the exit code alone - the same caveat this
# script already carries for WRAPPER_ERROR and 70.
if [ -n "$EXPECT" ] && ! grep -qF -- "$EXPECT" "$log" 2>/dev/null; then
  echo "GATE $label UNDECIDED LOG $log LINES $lines"
  if [ "$PROVE_RED" = true ]; then
    echo "GATE $label PROVE_RED INCONCLUSIVE - gate did not complete" >&2
  fi
  exit 75
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

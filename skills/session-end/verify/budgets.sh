#!/usr/bin/env bash
# budgets.sh - the router and step files must stay within their caps.
#
# THE CAP IS 8192, NOT THE SPEC'S ESTIMATED 7168. The spec's number was an
# estimate; this one is a measurement. But a cap whose recorded reason explains
# only one of the files it governs is a cap nobody can re-derive, so EVERY file
# over 7168 carries its own line in why() saying why it is over.
#
# An over-7168 file with no entry there FAILS. That is what stops the cap
# quietly absorbing the next long file somebody writes.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"

CAP_ROUTER=12288
CAP_STEP=8192
SOFT=7168

why() {
  case "$1" in
    step-01-verify.md)
      echo "six triage lanes, each defined by the proof it demands, plus the tree-that-lands rule. Unconditional: every run gates, and a red gate needs its lane at the moment it goes red. Deferring the table to references/ would leave a step that cannot triage without a second load." ;;
    step-04-pendings.md)
      echo "6307 bytes is Step 4's body, which the spec requires to move VERBATIM. Half A runs on EVERY invocation, including one that defers nothing, so none of it is trigger-gated and there is nothing to move." ;;
    *) return 1 ;;
  esac
}

n=$(wc -c < "$HERE/SKILL.md")
if [ "$n" -le "$CAP_ROUTER" ]; then ok "SKILL.md $n <= $CAP_ROUTER"; else bad "SKILL.md $n > $CAP_ROUTER"; fi

for f in "$HERE"/steps/*.md; do
  b=$(basename "$f")
  n=$(wc -c < "$f")
  if [ "$n" -gt "$CAP_STEP" ]; then
    bad "$b $n > $CAP_STEP"
  elif [ "$n" -gt "$SOFT" ]; then
    if r=$(why "$b"); then
      ok "$b $n over $SOFT, justified: $r"
    else
      bad "$b $n is over $SOFT with no recorded reason - add one to why() or shorten the file"
    fi
  else
    ok "$b $n <= $SOFT"
  fi
done

finish

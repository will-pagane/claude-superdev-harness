#!/usr/bin/env bash
# expect-flag.sh — prove --expect changes the output, in BOTH directions.
# A flag never seen to change the output is not a flag.
set -u
G="${1:?usage: expect-flag.sh <path-to-gate.sh>}"
fail=0

# 1. Log matches the expected line -> normal EXIT record, command's own code.
out=$("$G" --expect 'ran 3 tests' t-match printf 'ran 3 tests\n'); rc=$?
case "$out" in
  "GATE t-match EXIT 0 LOG "*) echo "PASS match -> EXIT" ;;
  *) echo "FAIL match: got [$out] rc=$rc"; fail=1 ;;
esac

# 2. Log does NOT match -> UNDECIDED record, exit 75. This is the killed-suite case.
out=$("$G" --expect 'ran 3 tests' t-nomatch printf 'killed after 2189 lines\n'); rc=$?
case "$out" in
  "GATE t-nomatch UNDECIDED LOG "*) [ "$rc" -eq 75 ] && echo "PASS nomatch -> UNDECIDED 75" \
      || { echo "FAIL nomatch rc: want 75 got $rc"; fail=1; } ;;
  *) echo "FAIL nomatch: got [$out] rc=$rc"; fail=1 ;;
esac

# 3. A REAL red whose runner printed its summary still reports EXIT, not UNDECIDED.
#    Round 1: the first draft allowed this case to SKIP, so the suite could pass
#    without ever testing one of --expect's core claims. --shell, and no skip.
out=$("$G" --shell --expect 'passed tests' t-red 'echo "2 failed, 1 passed tests"; exit 1')
case "$out" in
  "GATE t-red EXIT 1 LOG "*) echo "PASS real red -> EXIT 1" ;;
  *) echo "FAIL red: got [$out]"; fail=1 ;;
esac

# 4. No --expect at all -> byte-identical behaviour to before.
out=$("$G" t-plain printf 'anything\n')
case "$out" in
  "GATE t-plain EXIT 0 LOG "*) echo "PASS no-flag unchanged" ;;
  *) echo "FAIL no-flag: got [$out]"; fail=1 ;;
esac

exit $fail

#!/usr/bin/env bash
# lib.sh — shared assertion helpers. Sourced, never executed.
#
# Exists because round 1 of this plan's own review found that most of its
# verification was structurally incapable of failing. A check that cannot go
# red is a print statement wearing a gate's clothes.

TMPBASE="${TMPDIR:-/tmp}"      # Git Bash does not guarantee TMPDIR
FAILED=0

ok()  { printf 'PASS %s
' "$*"; }
bad() { printf 'FAIL %s
' "$*"; FAILED=1; }

# finish — the ONLY way these scripts end. Non-zero if anything failed.
finish() {
  if [ "$FAILED" -eq 0 ]; then printf '
ALL CHECKS PASSED
'; else printf '
CHECKS FAILED
'; fi
  exit "$FAILED"
}

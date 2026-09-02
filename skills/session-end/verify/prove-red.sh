#!/usr/bin/env bash
# prove-red.sh - mutate the split three ways and require reconstruct.sh to
# catch each one, restoring on every exit path including an interrupt.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"
ORIG="${1:?usage: prove-red.sh <pre-split SKILL.md>}"

R="$HERE/verify/reconstruct.sh"
S10="$HERE/steps/step-10-report.md"
S00="$HERE/steps/step-00-inventory.md"
SAVE="$TMPBASE/prove-red.$$"; mkdir -p "$SAVE"

restore() {
  [ -f "$SAVE/s10" ] && cp "$SAVE/s10" "$S10"
  [ -f "$SAVE/s00" ] && cp "$SAVE/s00" "$S00"
  rm -rf "$SAVE"
}
# Round 9: `trap restore EXIT INT TERM` restores on a signal but does NOT
# stop the script, so bash resumes and applies the next mutation to a
# just-restored tree. EXIT cleans up; the signal handlers must also exit.
trap restore EXIT
trap 'restore; echo "interrupted" >&2; exit 130' INT
trap 'restore; echo "terminated" >&2; exit 143' TERM
cp "$S10" "$SAVE/s10"; cp "$S00" "$SAVE/s00"

# (a) a step file removed - must be caught by the filename enumeration, not
#     merely by aggregate coverage, which a compensating duplicate could mask.
rm -f "$S10"
if bash "$R" "$ORIG" >"$SAVE/a.log" 2>&1; then bad "(a) missing file NOT caught"; else
  grep -qF "MISSING step-10-report.md" "$SAVE/a.log" \
    && ok "(a) missing file caught by enumeration" \
    || bad "(a) failed, but not via the enumeration"
fi
cp "$SAVE/s10" "$S10"

# (b) a line deleted from the MIDDLE of a block - fidelity AND coverage.
#     Deleting a TRAILING line leaves the block contiguous and proves nothing.
python - "$S00" <<'PY'
import io,sys
p=sys.argv[1]; L=io.open(p,encoding="utf-8").read().split("\n")
i=[n for n,x in enumerate(L) if x.strip()][3]
L.pop(i); io.open(p,"w",encoding="utf-8",newline="\n").write("\n".join(L))
PY
if bash "$R" "$ORIG" >"$SAVE/b.log" 2>&1; then bad "(b) deleted line NOT caught"; else
  grep -q "FAIL fidelity" "$SAVE/b.log" && grep -q "FAIL coverage" "$SAVE/b.log" \
    && ok "(b) deleted middle line caught by fidelity AND coverage" \
    || bad "(b) failed, but not on both claims"
fi
cp "$SAVE/s00" "$S00"

# (c) an existing line duplicated as its own moved block - COVERAGE ONLY.
#     Both blocks stay contiguous, so this is what isolates the two claims.
python - "$S10" <<'PY'
import io,sys
p=sys.argv[1]; t=io.open(p,encoding="utf-8").read()
b=[x for x in t.split("## NEXT")[0].strip().split("\n") if x.strip()][-1]
io.open(p,"w",encoding="utf-8",newline="\n").write(
    t.replace("\n## NEXT", "\n<!-- moved -->\n"+b+"\n\n## NEXT", 1))
PY
if bash "$R" "$ORIG" >"$SAVE/c.log" 2>&1; then bad "(c) duplicate NOT caught"; else
  grep -q "FAIL coverage" "$SAVE/c.log" && ! grep -q "FAIL fidelity" "$SAVE/c.log" \
    && ok "(c) duplicated block caught by coverage ONLY" \
    || bad "(c) failed, but fidelity also fired - the claims are not isolated"
fi
cp "$SAVE/s10" "$S10"

finish

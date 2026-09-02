#!/usr/bin/env bash
# reconstruct.sh - prove the split MOVED text and wrote none.
#
# Two claims, both enforced for the ROUTER as well as the step files. Round 3
# caught that the router's retained text was only multiset-checked, so its
# sections could be reordered freely while reconstruction passed - the exact
# round-1 defect, surviving in the one file nobody was checking.
#
#   FIDELITY  every retained BLOCK, in every file, appears verbatim and
#             contiguously in the original. This is what preserves blank lines
#             and ordering INSIDE a block.
#   COVERAGE  every NON-BLANK line of the original appears the same number of
#             times across all files. Blank lines between blocks are glue the
#             split may rearrange; blank lines inside blocks are fidelity's job.
#
# Markers, uniform across router and step files:
#   <!-- split-addition --> ... <!-- /split-addition -->   NEW text. Excluded
#     from both checks. Used for the router's entry-point table, each step
#     file's repeated table headers, and anything else the split writes.
#   <!-- moved -->                                          Block boundary. The
#     text after it comes from a DIFFERENT part of the original, so it is a new
#     contiguous block rather than a continuation of the last one.
#
# Usage: reconstruct.sh <pre-split SKILL.md> [<session-end dir>]
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"

ORIG="${1:?usage: reconstruct.sh <pre-split SKILL.md> [dir]}"
ROOT="${2:-$HERE}"

W="$TMPBASE/recon.$$"; mkdir -p "$W"; trap 'rm -rf "$W"' EXIT
tr -d '\r' < "$ORIG" > "$W/orig"
: > "$W/all"

# Round 3: a glob silently omits a missing file, so only aggregate coverage
# would have caught it - and a compensating duplicate elsewhere could hide it.
# Enumerate exactly.
EXPECTED="step-00-inventory.md step-01-verify.md step-02-production-state.md \
step-04-pendings.md step-05-push-and-pr.md step-07-merge.md \
step-08-sync-and-cleanup.md step-10-report.md"

for name in $EXPECTED; do
  if [ -f "$ROOT/steps/$name" ]; then ok "present $name"; else bad "MISSING $name"; fi
done
for f in "$ROOT"/steps/step-*.md; do
  [ -f "$f" ] || continue
  case " $EXPECTED " in
    *" $(basename "$f") "*) ;;
    *) bad "unexpected step file: $(basename "$f")" ;;
  esac
done

# blocks.py does extraction, marker validation and block splitting. It is
# Python rather than layered awk because the split-addition regions need
# balance and nesting validation, which awk expresses badly.
#
# Note precisely what is validated: split-addition is a PAIRED region, so
# nesting, unmatched closes and unclosed-at-EOF are all rejected. `moved` is a
# single BOUNDARY with no closing form, so there is nothing to pair and no
# pairing check to make. Round 4 caught the plan claiming otherwise.
check() {  # check <file> <router|step>
  label=$(basename "$1")
  rm -rf "$W/b"; mkdir -p "$W/b"
  if ! python "$HERE/verify/blocks.py" "$1" "$2" "$W/b" 2>"$W/err"; then
    bad "$label - $(head -1 "$W/err")"
    return
  fi
  n=0
  for blk in "$W"/b/blk*; do
    [ -f "$blk" ] || continue
    n=$((n+1))
    if python "$HERE/verify/contains.py" "$W/orig" "$blk"; then
      ok "fidelity $label block $n"
    else
      bad "fidelity $label block $n - not a verbatim contiguous block of the original"
    fi
  done
  if [ "$n" -eq 0 ]; then bad "fidelity $label - no retained blocks extracted"; fi
  cat "$W/b/cover" >> "$W/all"
}

check "$ROOT/SKILL.md" router
for name in $EXPECTED; do
  [ -f "$ROOT/steps/$name" ] && check "$ROOT/steps/$name" step
done

# COVERAGE: exact multiset of NON-BLANK lines.
#
# Blank lines are excluded deliberately, and the reason matters. A blank line
# INSIDE a retained block is already verified byte-exactly by fidelity, since
# the block must be a verbatim contiguous substring of the original. A blank
# line BETWEEN blocks is structural glue the split legitimately rearranges - a
# section that now ends a file no longer needs the blank that separated it from
# its old neighbour. Counting those made the check fail on a CORRECT split,
# which is how it was found: by running it, not by reading it.
if diff <(grep -v '^[[:space:]]*$' "$W/orig" | sort) \
        <(grep -v '^[[:space:]]*$' "$W/all"  | sort) > "$W/diff" 2>&1; then
  ok "coverage: every original NON-BLANK line accounted for exactly once"
else
  bad "coverage: $(wc -l < "$W/diff") differing lines"
  head -40 "$W/diff"
fi

finish

#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"
n=$(wc -c < "$HERE/SKILL.md")
if [ "$n" -le 12288 ]; then ok "SKILL.md $n <= 12288"; else bad "SKILL.md $n > 12288"; fi
for f in "$HERE"/steps/*.md; do
  n=$(wc -c < "$f")
  # 8192, not the spec's estimated 7168. Measured during the split: Step 4's
  # body is 6307 bytes the spec protects VERBATIM, the invariant recap every
  # step file carries is ~600, and its own Common-mistakes and Red-flags rows
  # are ~1000 more. 7168 leaves ~260 bytes of headroom for 1000 bytes of
  # content that belongs there, so the cap was infeasible against a constraint
  # the spec imposes elsewhere. Raised with the measurement, not to pass.
  if [ "$n" -le 8192 ]; then ok "$(basename "$f") $n <= 8192"; else bad "$(basename "$f") $n > 8192"; fi
done
finish

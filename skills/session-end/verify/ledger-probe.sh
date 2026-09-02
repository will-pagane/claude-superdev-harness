#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"
L="$(cd "$HERE/../.." && pwd)/skills/session-build/scripts/ledger.py"
D="$TMPBASE/ledger-probe.$$"
rm -rf "$D"; mkdir -p "$D"
trap 'rm -rf "$D"' EXIT

# 1. init --fork creates fork-<slug>.md and NOT ledger.md
if python "$L" init --dir "$D" --run-id probe --fork probe-slug >/dev/null 2>&1; then ok "init --fork accepted"; else bad "init --fork rejected"; fi
if [ -f "$D/fork-probe-slug.md" ]; then ok "fork file created"; else bad "fork file missing"; fi
if [ ! -f "$D/ledger.md" ]; then ok "init --fork did not create the orchestrator ledger"; else bad "init --fork also wrote ledger.md"; fi

# 2. re-init REFUSES rather than truncating an existing ledger.
#    Round 2: "any nonzero" also passes on a syntax error or a missing
#    interpreter, so require the specific exit code AND the specific message.
err="$D/reinit.err"
python "$L" init --dir "$D" --run-id probe --fork probe-slug >/dev/null 2>"$err"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF "refusing to re-init" "$err"; then
  ok "re-init refused with exit 2 and the expected message"
else
  bad "re-init: want exit 2 + 'refusing to re-init', got rc=$rc msg=$(head -1 "$err")"
fi

# 3. both new vocabulary entries append
for t in PENDINGS-RULING CLOSED READY; do
  if python "$L" append --dir "$D" --fork probe-slug --type "$t" --text "probe $t" >/dev/null 2>&1; then ok "append $t"; else bad "append $t rejected"; fi
done

# 4. an unknown type is still refused - the vocabulary is a gate, not a suggestion
if python "$L" append --dir "$D" --fork probe-slug --type NOT-A-REAL-TYPE --text x >/dev/null 2>&1; then bad "unknown type accepted"; else ok "unknown type refused"; fi

# 5. a hand-written CODEX APPROVED line is still refused
if python "$L" append --dir "$D" --fork probe-slug --type CODEX --text "APPROVED ROUNDS 1" >/dev/null 2>&1; then bad "hand-written CODEX APPROVED accepted"; else ok "hand-written CODEX APPROVED refused"; fi

finish

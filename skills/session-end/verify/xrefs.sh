#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
. "$HERE/verify/lib.sh"
# Round 2: hard-coding four files contradicts the plan's own claim that
# fourteen references live outside SKILL.md, and lets a reference elsewhere go
# orphaned unnoticed. Derive repo-wide.
#
# Round 5: --exclude-dir matches a BASENAME, so --exclude-dir=steps also
# excluded skills/session-build/steps - one of the known external reference
# sources, silently dropped from a sweep whose whole job is to find them.
# Exclude by PATH instead, and only the one directory that legitimately
# contains the headings rather than references to them.
refs=$(grep -rlE 'Step [0-9]+' "$REPO/skills" "$REPO/docs" 2>/dev/null \
  --exclude-dir=plans --exclude-dir=specs --exclude-dir=codex-review \
  | grep -v "^$HERE/steps/" \
  | tr '\n' '\0' | xargs -0 -r grep -hoE 'Step [0-9]+' 2>/dev/null \
  | grep -oE '[0-9]+' | sort -un)
if [ -z "$refs" ]; then bad "no Step N references found at all - the sweep is looking in the wrong place"; finish; fi
printf 'sweeping %s referenced step numbers\n' "$(printf '%s\n' "$refs" | wc -w)"
for n in $refs; do
  if grep -rq "^## Step $n " "$HERE/steps/"; then ok "Step $n resolves"; else bad "Step $n referenced but no owning heading"; fi
done
finish

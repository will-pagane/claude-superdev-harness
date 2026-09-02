#!/usr/bin/env bash
# check-drift.sh - is what runs the same as what is committed?
#
# Two modes, one script, because the normalisation rule is shared and two
# copies of it would drift apart. The rule: LINE ENDINGS ARE NOT DRIFT.
# .gitattributes forces eol=crlf on *.ps1 and eol=lf on *.sh, and a Windows
# checkout normalises on top of that, so a byte comparison of the skill tree on
# this machine reports 34 differences where only 5 are real. A check that cries
# 34 gets ignored, and being ignored is how the 5 sat unnoticed.
#
#   check-drift.sh              comparison mode: skills/** vs
#                               $CLAUDE_CONFIG_DIR/skills/** (default
#                               ~/.claude), CR stripped on both sides.
#   check-drift.sh --repo-only  repository invariants only: every skill has a
#                               SKILL.md, *.sh are LF, *.ps1 are CRLF. This is
#                               what a CI runner can prove about a checkout
#                               with no ~/.claude of its own.
#
# WHAT THIS DOES NOT PROVE: --repo-only says NOTHING about what is installed on
# anyone's machine. Only comparison mode does, and only for the machine it runs
# on. CI exercises comparison mode against an installation it builds itself,
# which proves the instrument works - not that your laptop is clean.
#
# Exit 0 clean, 1 drift found, 2 usage error or missing precondition.
#
# DELIBERATELY LAYOUT-AGNOSTIC: never carries a list of files a skill is
# expected to hold. It compares whatever exists. Enumerating them would
# hard-code one skill's internal layout and break on the next restructure.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="comparison"

case "${1:-}" in
  "")           MODE="comparison" ;;
  --repo-only)  MODE="repo-only" ;;
  -h|--help)    sed -n '2,28p' "$0"; exit 0 ;;
  *)            echo "check-drift.sh: unknown argument: $1" >&2; exit 2 ;;
esac

drift=0

# Line endings, read as BYTES. Two traps this avoids, both hit while building it:
#
#   * `grep -U` is a GNU extension, not portable to BSD/macOS grep;
#   * plain `grep` on MSYS treats CRLF as the line terminator and STRIPS it, so
#     a pattern of CR never matches a trailing CR. Measured on this machine: a
#     file containing `echo crlf<CR><LF>` returned "not found" for BOTH
#     `grep "$(printf '\r')"` and `grep $'\r'` - so the check called a CRLF .sh
#     clean. Dropping -U for BSD portability is what introduced that.
#
# `od` is POSIX, byte-exact and indifferent to how any tool defines a line, so
# it answers the question actually being asked. It also removes the need for a
# Python interpreter here, and with it the MSYS-path-to-Windows-Python
# translation that would have silently failed on a temp-dir checkout.
#
# Emits "<lf> <crlf> <cr>" for one file.
newline_counts() {
  LC_ALL=C od -An -v -tx1 "$1" | tr -s ' ' '\n' | awk '
    /^0d$/ { pend=1; cr++; next }
    /^0a$/ { lf++; if (pend) crlf++; pend=0; next }
    { pend=0 }
    END { printf "%d %d %d\n", lf+0, crlf+0, cr+0 }'
}

has_cr() {
  set -- $(newline_counts "$1")
  [ "$3" -gt 0 ]
}

# OK / BARE-LF / LONE-CR for a file that must be CRLF throughout. Asking only
# "does it contain a CR" would pass a file with one CRLF and five hundred LFs.
crlf_verdict() {
  set -- $(newline_counts "$1")
  if [ "$1" -ne "$2" ]; then echo "BARE-LF"
  elif [ "$3" -ne "$2" ]; then echo "LONE-CR"
  else echo "OK"
  fi
}

if [ "$MODE" = "repo-only" ]; then
  for root in skills scripts; do
    if [ ! -d "$REPO_DIR/$root" ]; then
      echo "check-drift: required directory missing: $root" >&2
      exit 2
    fi
  done

  skill_count=0
  for d in "$REPO_DIR"/skills/*/; do
    [ -d "$d" ] || continue
    skill_count=$((skill_count + 1))
    if [ ! -f "$d/SKILL.md" ]; then
      echo "MISSING SKILL.md: skills/$(basename "$d")"
      drift=1
    fi
  done
  if [ "$skill_count" -eq 0 ]; then
    echo "check-drift: found ZERO skill directories - this check proved nothing" >&2
    exit 2
  fi

  sh_list="$(mktemp)"
  find "$REPO_DIR/skills" "$REPO_DIR/scripts" -type f -name '*.sh' > "$sh_list" || {
    echo "check-drift: find failed while listing *.sh" >&2; rm -f "$sh_list"; exit 2; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if has_cr "$f"; then
      echo "CR byte in a file that must be LF-only: ${f#"$REPO_DIR"/}"
      drift=1
    fi
  done < "$sh_list"
  rm -f "$sh_list"

  ps_roots=""
  [ -d "$REPO_DIR/skills" ] && ps_roots="$ps_roots $REPO_DIR/skills"
  [ -d "$REPO_DIR/hooks" ]  && ps_roots="$ps_roots $REPO_DIR/hooks"
  ps_list="$(mktemp)"
  if [ -n "$ps_roots" ]; then
    # shellcheck disable=SC2086 -- deliberate word-split over a list of paths
    find $ps_roots -type f -name '*.ps1' > "$ps_list" || {
      echo "check-drift: find failed while listing *.ps1" >&2; rm -f "$ps_list"; exit 2; }
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    verdict="$(crlf_verdict "$f")"
    if [ "$verdict" != "OK" ]; then
      echo "line endings in a file that must be CRLF ($verdict): ${f#"$REPO_DIR"/}"
      drift=1
    fi
  done < "$ps_list"
  rm -f "$ps_list"

  [ "$drift" -eq 0 ] && echo "check-drift: repo-only clean ($skill_count skills)"
  exit "$drift"
fi

INSTALLED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
if [ ! -d "$INSTALLED" ]; then
  echo "check-drift: no installed skills at $INSTALLED - nothing to compare." >&2
  echo "check-drift: run ./install.sh --skills first, or use --repo-only." >&2
  exit 2
fi
if [ ! -d "$REPO_DIR/skills" ]; then
  echo "check-drift: required directory missing: skills" >&2
  exit 2
fi

# A symlinked install makes this a tautology, which is the point: it then
# catches a PARTIAL install rather than content drift.
norm() { tr -d '\r' < "$1"; }

repo_list="$(mktemp)"
(cd "$REPO_DIR/skills" && find . -type f) > "$repo_list" || {
  echo "check-drift: find failed over skills/" >&2; rm -f "$repo_list"; exit 2; }
[ -s "$repo_list" ] || { echo "check-drift: zero files under skills/ - proved nothing" >&2; rm -f "$repo_list"; exit 2; }

while IFS= read -r rel; do
  rel="${rel#./}"
  [ -n "$rel" ] || continue
  a="$REPO_DIR/skills/$rel"
  b="$INSTALLED/$rel"
  if [ ! -f "$b" ]; then
    echo "ONLY IN REPO: $rel"; drift=1
  elif ! diff -q <(norm "$a") <(norm "$b") >/dev/null 2>&1; then
    echo "DIFFERS: $rel"; drift=1
  fi
done < "$repo_list"
rm -f "$repo_list"

# The installed-only sweep is SCOPED TO SKILLS THIS REPO OWNS, and that scoping
# is the difference between a usable check and an ignored one. ~/.claude/skills
# is a shared namespace: this repo manages 5 directories there, and on the
# machine this was built for it also held 44 installed from elsewhere
# (firecrawl-*, hermes-*, site-*, graphify, ...). Sweeping the whole namespace
# reported 99 "extra" files, none of them drift and none of them this repo's
# business - the same cry-wolf failure as counting line endings, arrived at from
# the other direction.
#
# Scoped, it still catches what matters: a file added or left behind INSIDE a
# skill this repo owns. Note this is still layout-agnostic - it asks which
# top-level skill directories the repo has, never which files they should hold.
inst_list="$(mktemp)"
(cd "$INSTALLED" && find . -type f) > "$inst_list" || {
  echo "check-drift: find failed over the installed tree" >&2; rm -f "$inst_list"; exit 2; }
while IFS= read -r rel; do
  rel="${rel#./}"
  [ -n "$rel" ] || continue
  owner="${rel%%/*}"
  [ -d "$REPO_DIR/skills/$owner" ] || continue      # not ours; not our business
  if [ ! -f "$REPO_DIR/skills/$rel" ]; then
    echo "ONLY IN INSTALLED TREE: $rel"; drift=1
  fi
done < "$inst_list"
rm -f "$inst_list"

[ "$drift" -eq 0 ] && echo "check-drift: no real drift (line endings ignored)"
exit "$drift"

#!/usr/bin/env bash
# Does install.sh's capability probe agree with reality?
#
# This exists because the obvious test is vacuous. Asserting "the installer
# produced symlinks" PASSES when the probe wrongly says the system cannot
# symlink, because the installer then honestly copies and everything agrees
# with everything. That is precisely the bug this repo fixed on 2026-09-02.
#
# So: work out INDEPENDENTLY whether a directory symlink is possible here,
# using the method known to be correct, then require can_symlink() to say the
# same thing. Delete MSYS=winsymlinks:nativestrict from the probe and the
# oracle still says "can" while the probe says "cannot" -> red.
#
# --require-capable: fail when this machine cannot create a directory symlink
# at all. Without it the job passes vacuously on such a runner - oracle=no and
# installed=no agree, and the regression coverage silently disappears. CI
# passes the flag; a developer on a machine without the capability does not,
# and gets an honest "agrees, both no".
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REQUIRE_CAPABLE=0
[ "${1:-}" = "--require-capable" ] && REQUIRE_CAPABLE=1

# --- the oracle -------------------------------------------------------------
oracle_dir="$(mktemp -d)"
mkdir -p "$oracle_dir/src"
: > "$oracle_dir/src/sentinel"
oracle="no"
if MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -s "$oracle_dir/src" "$oracle_dir/dst" 2>/dev/null \
   && [ -L "$oracle_dir/dst" ] && [ -d "$oracle_dir/dst" ] && [ -f "$oracle_dir/dst/sentinel" ]; then
  oracle="yes"
fi
rm -rf "$oracle_dir"
echo "oracle: directory symlink possible here = $oracle"

if [ "$REQUIRE_CAPABLE" -eq 1 ] && [ "$oracle" != "yes" ]; then
  echo "PRECONDITION FAILED: this runner cannot create a directory symlink, so"
  echo "this job cannot cover the regression it exists for. Not a silent pass."
  exit 1
fi

# --- what the installer actually did ----------------------------------------
home="$(mktemp -d)"
log="$(mktemp)"
CLAUDE_CONFIG_DIR="$home" "$REPO_DIR/install.sh" --skills > "$log" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "FAIL: installer exited $rc"
  sed -n '1,60p' "$log"
  rm -rf "$home" "$log"
  exit 1
fi

installed="no"
first="$(find "$home/skills" -maxdepth 1 -mindepth 1 -type l -print -quit 2>/dev/null || true)"
[ -n "$first" ] && installed="yes"
echo "installer: produced symlinks = $installed"

status=0
if [ "$oracle" != "$installed" ]; then
  echo "MISMATCH: this system can symlink=$oracle but install.sh produced symlinks=$installed"
  echo "If oracle=yes and installed=no, can_symlink() is under-reporting - the exact"
  echo "regression this job exists to catch (MSYS missing from the probe)."
  sed -n '1,40p' "$log"
  status=1
else
  echo "OK: probe and reality agree (both $oracle)"
fi
rm -rf "$home" "$log"
exit "$status"

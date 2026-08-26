#!/usr/bin/env bash
# preflight.sh — the checks that, skipped, cost real runs hours.
#
# Two jobs, chosen because each has a documented multi-hour failure behind it:
#
#   repo   — is this checkout current? A brainstorm once ran against a tree
#            3,602 commits behind the default branch; three of its four scope
#            targets were already done in the real code and the whole spec was
#            rebuilt.
#   tree   — is this worktree bootstrapped? An unbootstrapped worktree has NO
#            GATES AT ALL, silently: hook managers point core.hooksPath at a
#            relative directory their install script creates, so without an
#            install git runs no hooks and reports nothing. Every gate, quietly,
#            while commits and pushes succeed.
#
# Usage:
#   scripts/preflight.sh repo [<remote>] [<default-branch>]
#   scripts/preflight.sh tree <worktree-abs-path> [<env-file>]
#
# Output: one PREFLIGHT line per check, plus a final verdict line.
#   PREFLIGHT <check> <OK|WARN|FAIL> <detail>
#   PREFLIGHT VERDICT <OK|BLOCKED> <n> issue(s)
#
# Exits non-zero if any check FAILed, so it composes in an `if`.

set -u

issues=0
warns=0

say() {
  # $1 check, $2 status, rest detail
  local check="$1" status="$2"
  shift 2
  echo "PREFLIGHT $check $status $*"
  [ "$status" = "FAIL" ] && issues=$((issues + 1))
  [ "$status" = "WARN" ] && warns=$((warns + 1))
  return 0
}

cmd_repo() {
  local remote="${1:-origin}" branch="${2:-}"

  git rev-parse --is-inside-work-tree > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    say repo.is-git FAIL "not inside a git work tree"
    return 0
  fi

  if [ -z "$branch" ]; then
    branch=$(git symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null)
    branch="${branch#$remote/}"
  fi
  if [ -z "$branch" ]; then
    say repo.default-branch WARN "could not resolve $remote/HEAD; pass the default branch explicitly"
    return 0
  fi

  git fetch "$remote" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    say repo.fetch WARN "git fetch $remote failed; the comparison below may be stale"
  else
    say repo.fetch OK "fetched $remote"
  fi

  local counts ahead behind
  counts=$(git rev-list --left-right --count "HEAD...$remote/$branch" 2>/dev/null)
  if [ -z "$counts" ]; then
    say repo.freshness WARN "could not compare against $remote/$branch"
    return 0
  fi
  ahead=$(echo "$counts" | awk '{print $1}')
  behind=$(echo "$counts" | awk '{print $2}')

  if [ "$behind" -gt 0 ]; then
    say repo.freshness FAIL "$behind commit(s) behind $remote/$branch - sync, or state in one line why not"
  else
    say repo.freshness OK "current with $remote/$branch (ahead $ahead)"
  fi
}

cmd_tree() {
  local wt="${1:-}" envfile="${2:-.env}"

  if [ -z "$wt" ]; then
    say tree.args FAIL "usage: preflight.sh tree <worktree-abs-path> [<env-file>]"
    return 0
  fi
  if [ ! -d "$wt" ]; then
    say tree.exists FAIL "no such directory: $wt"
    return 0
  fi
  say tree.exists OK "$wt"

  # Dependencies. Presence of a manifest without its install directory is the
  # signal; which manifest depends on the project, so check the common ones.
  if [ -f "$wt/package.json" ]; then
    if [ -d "$wt/node_modules" ]; then
      say tree.deps OK "node_modules present"
    else
      say tree.deps FAIL "package.json with no node_modules - install before dispatching"
    fi
  fi

  # The gitignored environment file. Missing it does not fail fast; one run
  # spent 22 minutes and three full test runs finding it in a log.
  if [ -f "$wt/$envfile" ]; then
    say tree.env OK "$envfile present"
  else
    say tree.env FAIL "$envfile missing - it is gitignored, so a fresh worktree never has it"
  fi

  # Per-checkout link state. Gitignored and per-worktree; copying another
  # checkout's copy in is worse than not having it.
  if [ -d "$wt/supabase" ]; then
    if [ -f "$wt/supabase/.temp/project-ref" ]; then
      say tree.link OK "supabase project linked"
    else
      say tree.link WARN "supabase/ present but not linked - run 'supabase link --project-ref <ref>' HERE, never copy another checkout's .temp"
    fi
  fi

  # The false green that matters most.
  local hp
  hp=$(git -C "$wt" config --get core.hooksPath 2>/dev/null)
  if [ -z "$hp" ]; then
    if [ -d "$wt/.git/hooks" ] || [ -d "$(git -C "$wt" rev-parse --git-common-dir 2>/dev/null)/hooks" ]; then
      say tree.hooks OK "no core.hooksPath; default hooks directory in use"
    else
      say tree.hooks WARN "no core.hooksPath and no default hooks directory found"
    fi
  else
    case "$hp" in
      /*) resolved="$hp" ;;
      *)  resolved="$wt/$hp" ;;
    esac
    if [ -d "$resolved" ]; then
      say tree.hooks OK "core.hooksPath=$hp resolves to an existing directory"
    else
      say tree.hooks FAIL "core.hooksPath=$hp does NOT exist - git is running no hooks and saying nothing"
    fi
  fi

  say tree.prove-red WARN "not checked here - run 'scripts/gate.sh --prove-red <label> <known-bad command>' before dispatching"
}

case "${1:-}" in
  repo) shift; cmd_repo "$@" ;;
  tree) shift; cmd_tree "$@" ;;
  *)
    echo "usage: preflight.sh repo [<remote>] [<default-branch>]" >&2
    echo "       preflight.sh tree <worktree-abs-path> [<env-file>]" >&2
    exit 64
    ;;
esac

if [ "$issues" -gt 0 ]; then
  echo "PREFLIGHT VERDICT BLOCKED $issues issue(s), $warns warning(s)"
  exit 1
fi

echo "PREFLIGHT VERDICT OK 0 issue(s), $warns warning(s)"
exit 0

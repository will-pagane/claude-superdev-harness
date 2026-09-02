# Skill Propagation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **EXCEPTION FOR THIS RUN:** this plan is executed by a `session-build` **fork**, whose boilerplate forbids the `Agent` tool. Subagent-driven-development therefore cannot run. Implement **inline, one task at a time**, running each task's verification and reading real output before marking it done — SDD's discipline without its parallelism.

**Goal:** Make an edit to a session skill reach this repository automatically, by fixing the installer's symlink probe, and make undetected drift impossible by adding a check that fails loudly.

**Architecture:** Three independent pieces plus one gating experiment. The experiment (Task 1) answers whether Claude Code loads a skill whose directory is a symlink — the primary path depends on it and nothing else does. Task 2 fixes `install.sh`'s capability probe, which today answers "this system cannot symlink" on a system that can. Task 3 adds `scripts/check-drift.sh` with two modes: a local mode comparing the repo against `~/.claude` with line endings normalised, and a repo-only mode for CI, which cannot see a developer's home directory. Task 4 wires the repo-only mode into the existing `syntax-check` job. Task 5 documents the trade-off the symlink path creates. Task 6 is the fallback, and runs **only if Task 1 answers no**.

**Tech Stack:** Bash (`set -euo pipefail`), GitHub Actions, Git Bash / MSYS2 on Windows. No package manager, no test framework, no application code in this repository.

**Spec:** `docs/superpowers/specs/2026-09-02-skill-propagation-design.md`

## Global Constraints

- **`set -euo pipefail` is already set in `install.sh:24`.** Every edit must stay safe under `-e`: a command whose non-zero status is expected goes inside an `if`, or is suffixed with `|| true` **only** where the status is genuinely uninteresting.
- **This repository runs NO local git hooks.** `core.hooksPath` is unset and `.git/hooks` holds only samples. A clean commit proves nothing here; every gate is one you run and read yourself.
- **Gates run through `~/.claude/skills/session-build/scripts/gate.sh`** — absolute path, the skill's script, not this repo's. This repo has no `scripts/gate.sh`.
- **Gate order for this repo:** `bash -n install.sh` · `node --check statusline/statusline.mjs` · `bash -n` on every `skills/**/*.sh` · `node --check` on every `skills/**/*.{js,mjs}` · `node -e JSON.parse` on `settings.example.json` · then the installer integration tests in `.github/workflows/lint.yml`.
- **No migrations and no deploys exist in this repository.** Checked, not assumed: there is no `supabase/` directory, no `package.json`, and `.github/workflows/` holds only `lint.yml`. Steps that would apply a migration or deploy a function have nothing to act on.
- **Surface fence.** This plan writes only `install.sh`, `scripts/check-drift.sh`, `.github/workflows/lint.yml`, `README.md`, and its own plan/ledger files. `skills/**` and `docs/cadeia-session.md` belong to the peer fork. `docs/superpowers/specs/**` belongs to the orchestrator: read, never write.
- **Two absolute fences on `~/.claude`,** from the dispatch and binding over the spec's own wording:
  1. Any probe that writes under `C:/Users/willi/.claude/` writes **only** inside `skills/symlink-probe/`. Never `session-end`, never `session-build` — those are the live copies of the skills this run is executing, and the peer fork is rewriting one of them.
  2. **Never run `install.sh --skills` against the real `~/.claude` during this run.** Test the installer the way CI does: `export CLAUDE_CONFIG_DIR="$(mktemp -d)"`. The real install is sequenced after the peer's branch merges.
- **`check-drift.sh` is layout-agnostic.** It never carries a manifest of expected files. Enumerating them would hard-code the peer's new `steps/`/`references/` layout and re-couple two branches that step-02 deliberately made independent.
- **Language:** code, comments and commit messages in English; user-facing `README.md` prose in Brazilian Portuguese, matching the file it is edited into.

---

## Corrections to the spec, made from readings taken against the live tree

The spec is the authority on intent. Three of its factual claims were re-measured before planning, per the rule that a fact the spec asserts is not a fact the plan may inherit.

| Spec says | Measured 2026-09-02 in this worktree | Consequence |
|---|---|---|
| "a byte comparison of the **23** skill files reports **23** differences … stripping `\r` reports **five**" | **41** skill files; **34** raw byte differences; **5** normalised | The ratio is worse than the spec claimed, not better. Task 3's acceptance uses the measured numbers. |
| Task 1 probes by symlinking `~/.claude/skills/session-end` | Forbidden by the dispatch fence | Probe uses the throwaway `~/.claude/skills/symlink-probe/`. Strictly safer: no rollback of a real skill is needed. |
| CI mode "verifies that every skill directory holds the files the installer expects" | Conflicts with the layout-agnostic fence | CI mode asserts every skill directory holds a `SKILL.md` — the harness's own requirement, true regardless of the peer's layout — plus the line-ending rules. No file manifest. |

Two facts confirmed rather than corrected, both by direct measurement:

- `MSYS=winsymlinks:nativestrict ln -sfn <dir> <dst>` creates a real **directory** symlink on this machine: `test -L` true, `test -d` true, and the target's contents list through it. Windows distinguishes file and directory symlinks, so this needed checking separately from the spec's file-symlink probe.
- `claude` is on `PATH` at version `2.1.258`, and there is **no `claude skill` subcommand** — `claude --help` lists `agents`, `auth`, `auto-mode`, `doctor`, `gateway`, `import`, `install`, `logs`, `mcp`, `plugin`, `project`, `respawn`, `rm`. So no deterministic CLI listing of skills exists, and Task 1's automated attempt has to be a functional invocation.

---

## File Structure

| File | Responsibility |
|---|---|
| `install.sh` (modify, two sites) | Decide symlink-vs-copy correctly, and create the link. Sites: `can_symlink()` at `:73-84` and `install_path()`'s `ln -sfn` at `:147`. |
| `scripts/check-drift.sh` (create) | Report real drift between `skills/**` and an installed `~/.claude/skills/**`, normalised. Two modes, one script, because the CI check and the local check share the normalisation rule and must not drift apart. |
| `.github/workflows/lint.yml` (modify) | Run the repo-only mode as one more step in the existing `syntax-check` job. |
| `README.md` (modify, `:33-37`) | State what changes for the reader once symlink actually works, including the hazard. |
| `hooks/mirror-skills.ps1` (create, **Task 6 only**) | Fallback: mirror `~/.claude/skills/{session-build,session-end}` writes into the repo, normalising line endings. Created only if Task 1 answers no. |

---

## Task 1: Answer whether Claude Code loads a symlinked skill directory

This gates the entire primary path and nothing else depends on it. It writes to `~/.claude`, so it is fenced to a throwaway directory and cleans up after itself in every outcome.

**Files:**
- Create (temporary, outside the repo): `~/.claude/skills/symlink-probe/SKILL.md`
- Create (temporary, outside the repo): a source directory under `$(mktemp -d)`
- Test: this task's verification is the probe itself

**Interfaces:**
- Consumes: nothing.
- Produces: a recorded verdict — `SYMLINK-LOADS: yes` or `SYMLINK-LOADS: no` — in the fork ledger. Tasks 2, 4 and 5 proceed regardless; **Task 6 runs if and only if the verdict is `no`.**

- [ ] **Step 1: Record the pre-state, so rollback is a fact and not a memory**

```bash
ls -la "$HOME/.claude/skills/" | grep -i symlink-probe || echo "PRE-STATE: no symlink-probe directory exists"
test -e "$HOME/.claude/skills/symlink-probe" && echo "ABORT: symlink-probe already exists, investigate before continuing"
```

Expected: `PRE-STATE: no symlink-probe directory exists`, and no `ABORT` line.

- [ ] **Step 2: Build the probe skill in a temp source directory**

The frontmatter matches what the harness requires of any skill: a `name` and a `description`.

```bash
PROBE_SRC="$(mktemp -d)/symlink-probe"
mkdir -p "$PROBE_SRC"
cat > "$PROBE_SRC/SKILL.md" <<'EOF'
---
name: symlink-probe
description: Throwaway probe that exists only to answer whether Claude Code loads a skill whose directory is a symlink. Delete on sight.
---

# Symlink probe

If you are reading this, the harness resolved a skill through a symlinked directory.

Reply with exactly this line and nothing else:

SYMLINK-PROBE-LOADED
EOF
echo "PROBE_SRC=$PROBE_SRC"
```

Expected: a path printed, `SKILL.md` present at it.

- [ ] **Step 3: Symlink it into `~/.claude/skills/`, and verify the disk rather than the exit code**

`ln` in Git Bash returns 0 after copying, so the exit code is not evidence. `test -L` is.

```bash
MSYS=winsymlinks:nativestrict ln -sfn "$PROBE_SRC" "$HOME/.claude/skills/symlink-probe"
test -L "$HOME/.claude/skills/symlink-probe" && echo "IS SYMLINK" || echo "NOT A SYMLINK - probe invalid, stop"
test -f "$HOME/.claude/skills/symlink-probe/SKILL.md" && echo "RESOLVES" || echo "DOES NOT RESOLVE"
```

Expected: `IS SYMLINK` and `RESOLVES`. If `NOT A SYMLINK`, the probe cannot answer the question — clean up (Step 6) and record `SYMLINK-LOADS: inconclusive (could not create symlink)`.

- [ ] **Step 4: Try the automated answer before considering a manual one**

A fresh `claude` process reads the skills directory from scratch, so it does not need a human to restart anything. There is no `claude skill` subcommand, so the test is functional: ask a headless session to invoke the probe by name and see whether the skill resolves.

```bash
~/.claude/skills/session-build/scripts/gate.sh probe-headless \
  claude -p "/symlink-probe" --allowedTools "Skill"
```

Read the log the gate names. Three readings, and only the first two are verdicts:

- Output contains `SYMLINK-PROBE-LOADED` → **`SYMLINK-LOADS: yes`**. The harness discovered and executed a skill through a symlink.
- Output says the skill is unknown / not found → **`SYMLINK-LOADS: no`**.
- Anything else — auth prompt, non-interactive refusal, a timeout, an error unrelated to skills → **inconclusive**, go to Step 5.

- [ ] **Step 5: Only on inconclusive — escalate as a genuinely manual step**

Do not guess and do not fall back silently. Report to the orchestrator with `BLOCKED`, naming what was tried:

```
BLOCKED symlink-load verdict inconclusive. Tried: throwaway symlink at
~/.claude/skills/symlink-probe verified with test -L and test -f (both true);
headless `claude -p "/symlink-probe"` returned <paste the decisive line>.
No `claude skill` subcommand exists to list skills deterministically
(claude 2.1.258, --help enumerated). Needs a human to restart Claude Code
and confirm whether symlink-probe appears. Probe left in place for that
check; cleanup is Step 6 and runs after the answer.
```

Then end the turn. This is the one step in this plan that may need a human, and it earns that only after the automated path was attempted and read.

- [ ] **Step 6: Clean up, in every outcome**

```bash
rm -f "$HOME/.claude/skills/symlink-probe"
test -e "$HOME/.claude/skills/symlink-probe" && echo "STILL PRESENT - investigate" || echo "REMOVED"
ls "$HOME/.claude/skills/" | grep -c . 
```

Expected: `REMOVED`. `rm -f` on a symlink removes the link, never the target — but confirm by listing, because a removal reporting success over work not done has been observed on this machine.

- [ ] **Step 7: Record the verdict**

```bash
python ~/.claude/skills/session-build/scripts/ledger.py append \
  --dir "C:/dev/Projects/claude-setup/.superpowers/session-build/20260902-0447" \
  --fork skill-propagation --type READING \
  --text "SYMLINK-LOADS: <yes|no>. Method: throwaway ~/.claude/skills/symlink-probe symlinked with MSYS=winsymlinks:nativestrict, verified test -L and test -f true, then headless claude -p /symlink-probe. Decisive output line: <paste>. Probe removed, confirmed by listing. Gates Task 6."
```

No commit — this task changes no file in the repository.

---

## Task 2: Make `can_symlink()` and the real `ln` ask the right question

**Files:**
- Modify: `install.sh:73-84` (`can_symlink`), `install.sh:147` (`ln -sfn` inside `install_path`)
- Test: an end-to-end install into a throwaway `CLAUDE_CONFIG_DIR`, which is how CI already tests this file

**Interfaces:**
- Consumes: nothing.
- Produces: `MODE=symlink` on a machine where symlinks are possible. Task 3's local mode and Task 5's README text both describe behaviour this task creates, but neither imports code from it.

- [ ] **Step 1: Write the failing test**

There is no test framework here, so the test is a script that asserts and exits non-zero. Save it as a scratch file outside the repo — it is a probe, not a deliverable.

```bash
cat > "$(mktemp -d)/t-symlink-install.sh" <<'EOF'
#!/usr/bin/env bash
# Asserts install.sh links rather than copies on a system that supports symlinks.
set -uo pipefail
REPO="$1"
CLAUDE_CONFIG_DIR="$(mktemp -d)"
export CLAUDE_CONFIG_DIR
"$REPO/install.sh" --skills >/dev/null 2>&1
rc=0
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"
  target="$CLAUDE_CONFIG_DIR/skills/$name"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    echo "MISSING $name"; rc=1; continue
  fi
  if [ ! -L "$target" ]; then
    echo "NOT A SYMLINK: $name"; rc=1
  fi
done
[ "$rc" -eq 0 ] && echo "ALL SKILLS SYMLINKED"
rm -rf "$CLAUDE_CONFIG_DIR"
exit "$rc"
EOF
```

Note the deliberate absence of `-e` in that script: it must survive a failing assertion long enough to report every one, not die on the first.

- [ ] **Step 2: Run it to make sure it fails**

```bash
~/.claude/skills/session-build/scripts/gate.sh symlink-install-red \
  bash <path-to>/t-symlink-install.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: non-zero, with `NOT A SYMLINK:` lines. This is the prove-red — without it, a pass after the change proves nothing, because `MODE` could have been `symlink` all along.

- [ ] **Step 3: Fix the probe**

Replace `install.sh:73-84`. The comment gains the sentence that explains the fix, because the existing comment is right about `ln` and silent about `MSYS`, which is exactly how the bug survived review.

```bash
# Symlink e capacidade do SISTEMA, nao do SO: Windows com Developer Mode ligado
# symlinka, Windows sem ele nao. `ln -s` do Git Bash e pior que falhar — ele
# COPIA e retorna 0, entao a unica leitura confiavel e escrever um symlink de
# teste e perguntar ao `test -L` se o que ficou no disco e mesmo um symlink.
#
# E o Git Bash NAO cria symlink nativo sem MSYS=winsymlinks:nativestrict, nem
# com o Developer Mode ligado. Sem essa variavel o probe responde "esta maquina
# nao symlinka" numa maquina que symlinka, o install cai pra copia, e a copia
# nunca mais se atualiza. A variavel e inerte fora do MSYS.
can_symlink() {
  local probe_dir probe_src probe_dst rc
  probe_dir="$(mktemp -d 2>/dev/null)" || return 1
  probe_src="$probe_dir/src"; probe_dst="$probe_dir/dst"
  : > "$probe_src"
  rc=1
  if MSYS=winsymlinks:nativestrict ln -s "$probe_src" "$probe_dst" 2>/dev/null && [ -L "$probe_dst" ]; then
    rc=0
  fi
  rm -rf "$probe_dir"
  return $rc
}
```

- [ ] **Step 4: Fix the real link, at `install.sh:147`**

The probe answering yes is worthless if the install itself still copies. Same variable, same reason.

```bash
  if [ "$MODE" = "symlink" ]; then
    MSYS=winsymlinks:nativestrict ln -sfn "$src" "$dst"
    # Verifica em vez de confiar: o `ln` do Git Bash retorna 0 depois de copiar.
    [ -L "$dst" ] || die "esperava symlink em $dst e o disco tem outra coisa — rode com --copy"
    info "${GRN}LINK${RST}  $dst ${DIM}-> $src${RST}"
```

The `[ -L "$dst" ] || die` line already present is what makes this fail closed, and it stays exactly as it is.

- [ ] **Step 5: Syntax gate before behaviour**

```bash
~/.claude/skills/session-build/scripts/gate.sh install-parse bash -n "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/install.sh"
```

Expected: `EXIT 0`.

- [ ] **Step 6: Run the test again and read it**

```bash
~/.claude/skills/session-build/scripts/gate.sh symlink-install-green \
  bash <path-to>/t-symlink-install.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: `EXIT 0` and `ALL SKILLS SYMLINKED`. Read the log, do not infer from the exit code alone.

- [ ] **Step 7: Confirm `--copy` still forces a copy**

A fix that removes the escape hatch is a regression. `--copy` is the documented way out for anyone who does not want links.

```bash
d="$(mktemp -d)"; CLAUDE_CONFIG_DIR="$d" "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/install.sh" --skills --copy >/dev/null 2>&1
test -L "$d/skills/session-end" && echo "REGRESSION: --copy produced a symlink" || echo "--copy still copies"
rm -rf "$d"
```

Expected: `--copy still copies`.

- [ ] **Step 8: Commit**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
git add install.sh
git commit -m "fix(install): the probe that asked the wrong question

Git Bash does not create a native symlink without
MSYS=winsymlinks:nativestrict, and can_symlink() did not set it. So the
probe answered 'this system cannot symlink' on a system that can, the
install fell back to copy, and a copy never updates itself. Developer
Mode alone does not change that -- it was already on when this was
measured.

The comment was right about ln returning 0 after copying and silent
about MSYS, which is how the bug survived being read."
```

The `git branch --show-current` line is not decoration: it must print `fix/skill-propagation-20260902` before the commit, every time.

---

## Task 3: `scripts/check-drift.sh`

**Files:**
- Create: `scripts/check-drift.sh`
- Test: the script run against a deliberately introduced difference, then without it

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/check-drift.sh`, callable two ways. Task 4 calls it as `bash scripts/check-drift.sh --repo-only`.
  - `check-drift.sh` → local mode. Compares `skills/**` against `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/**`, `\r` stripped both sides. Exit 0 when identical, 1 when not, 2 on usage error.
  - `check-drift.sh --repo-only` → CI mode. No home directory involved. Exit 0/1/2 the same way.

- [ ] **Step 1: Write the failing test**

```bash
cat > "$(mktemp -d)/t-check-drift.sh" <<'EOF'
#!/usr/bin/env bash
# Proves check-drift.sh can BOTH pass and fail. A check never seen to fail is not a check.
set -uo pipefail
REPO="$1"
rc=0

# repo-only mode must pass on a clean tree
bash "$REPO/scripts/check-drift.sh" --repo-only >/dev/null 2>&1 \
  || { echo "FAIL: --repo-only red on a clean tree"; rc=1; }

# repo-only mode must go red when a skills/**/*.sh carries CRLF
victim="$REPO/skills/session-build/scripts/gate.sh"
cp "$victim" "$victim.orig"
printf 'echo crlf\r\n' >> "$victim"
if bash "$REPO/scripts/check-drift.sh" --repo-only >/dev/null 2>&1; then
  echo "FAIL: --repo-only stayed green with a CRLF .sh"; rc=1
else
  echo "OK: --repo-only detects CRLF"
fi
mv "$victim.orig" "$victim"

# local mode must go red on a real content difference
fake_home="$(mktemp -d)"
mkdir -p "$fake_home/skills"
cp -R "$REPO/skills/." "$fake_home/skills/"
if CLAUDE_CONFIG_DIR="$fake_home" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1; then
  echo "OK: local mode green on an identical copy"
else
  echo "FAIL: local mode red on an identical copy"; rc=1
fi
echo "a real difference" >> "$fake_home/skills/session-end/SKILL.md"
if CLAUDE_CONFIG_DIR="$fake_home" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1; then
  echo "FAIL: local mode stayed green with a real difference"; rc=1
else
  echo "OK: local mode detects a real difference"
fi

# and it must IGNORE a pure line-ending difference
mv "$fake_home/skills/session-end/SKILL.md" "$fake_home/skills/session-end/SKILL.md.bak"
sed 's/$/\r/' "$REPO/skills/session-end/SKILL.md" > "$fake_home/skills/session-end/SKILL.md"
if CLAUDE_CONFIG_DIR="$fake_home" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1; then
  echo "OK: local mode ignores CRLF-only difference"
else
  echo "FAIL: local mode reported CRLF-only noise as drift"; rc=1
fi
rm -rf "$fake_home"
exit "$rc"
EOF
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/.claude/skills/session-build/scripts/gate.sh check-drift-red \
  bash <path-to>/t-check-drift.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: non-zero — the script does not exist yet, so every invocation fails.

- [ ] **Step 3: Write `scripts/check-drift.sh`**

```bash
#!/usr/bin/env bash
# check-drift.sh - is what runs the same as what is committed?
#
# Two modes, one script, because the normalisation rule is the same in both and
# two copies of it would drift apart. The rule: line endings are NOT drift.
# .gitattributes forces eol=crlf on *.ps1 and eol=lf on *.sh, and a Windows
# checkout normalises on top of that, so a byte comparison of the skill tree on
# this machine reports 34 differences where only 5 are real. A check that cries
# 34 is noise, and noise is what let a real drift sit unnoticed.
#
#   check-drift.sh              local mode: skills/** vs $CLAUDE_CONFIG_DIR/skills/**
#                               (default ~/.claude), \r stripped on both sides.
#   check-drift.sh --repo-only  CI mode: no home directory exists on a runner, so
#                               this checks only what the repo can prove about
#                               itself - every skill has a SKILL.md, no *.sh
#                               carries CR, every *.ps1 carries CRLF.
#
# Exit 0 clean, 1 drift found, 2 usage error.
#
# DELIBERATELY LAYOUT-AGNOSTIC: this script never carries a list of files a
# skill is expected to hold. It compares whatever exists. Enumerating them
# would hard-code one skill's internal layout and break on the next
# restructure - which is precisely the kind of coupling this repo keeps
# removing.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="local"

case "${1:-}" in
  "")           MODE="local" ;;
  --repo-only)  MODE="repo-only" ;;
  -h|--help)    sed -n '2,26p' "$0"; exit 0 ;;
  *)            echo "check-drift.sh: unknown argument: $1" >&2; exit 2 ;;
esac

drift=0

if [ "$MODE" = "repo-only" ]; then
  for d in "$REPO_DIR"/skills/*/; do
    [ -d "$d" ] || continue
    if [ ! -f "$d/SKILL.md" ]; then
      echo "MISSING SKILL.md: skills/$(basename "$d")"
      drift=1
    fi
  done

  while IFS= read -r f; do
    if grep -qU $'\r' "$f" 2>/dev/null; then
      echo "CRLF in a file that must be LF: ${f#"$REPO_DIR"/}"
      drift=1
    fi
  done < <(find "$REPO_DIR/skills" "$REPO_DIR/scripts" -type f -name '*.sh' 2>/dev/null)

  while IFS= read -r f; do
    if ! grep -qU $'\r' "$f" 2>/dev/null; then
      echo "LF in a file that must be CRLF: ${f#"$REPO_DIR"/}"
      drift=1
    fi
  done < <(find "$REPO_DIR/skills" "$REPO_DIR/hooks" -type f -name '*.ps1' 2>/dev/null)

  [ "$drift" -eq 0 ] && echo "check-drift: repo-only clean"
  exit "$drift"
fi

INSTALLED="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
if [ ! -d "$INSTALLED" ]; then
  echo "check-drift: no installed skills at $INSTALLED - nothing to compare." >&2
  echo "check-drift: run ./install.sh --skills first, or use --repo-only." >&2
  exit 2
fi

# A symlinked install makes this comparison a tautology, which is the point:
# it then catches a PARTIAL install rather than content drift.
norm() { tr -d '\r' < "$1"; }

while IFS= read -r rel; do
  a="$REPO_DIR/skills/$rel"
  b="$INSTALLED/$rel"
  if [ ! -f "$b" ]; then
    echo "ONLY IN REPO: $rel"
    drift=1
  elif ! diff -q <(norm "$a") <(norm "$b") >/dev/null 2>&1; then
    echo "DIFFERS: $rel"
    drift=1
  fi
done < <(cd "$REPO_DIR/skills" && find . -type f | sed 's|^\./||' | sort)

while IFS= read -r rel; do
  if [ ! -f "$REPO_DIR/skills/$rel" ]; then
    echo "ONLY IN ~/.claude: $rel"
    drift=1
  fi
done < <(cd "$INSTALLED" && find . -type f | sed 's|^\./||' | sort)

[ "$drift" -eq 0 ] && echo "check-drift: no real drift (line endings ignored)"
exit "$drift"
```

- [ ] **Step 4: Make it executable and syntax-gate it**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && chmod +x scripts/check-drift.sh
~/.claude/skills/session-build/scripts/gate.sh check-drift-parse bash -n "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/scripts/check-drift.sh"
```

Expected: `EXIT 0`.

- [ ] **Step 5: Run the test and read every line**

```bash
~/.claude/skills/session-build/scripts/gate.sh check-drift-green \
  bash <path-to>/t-check-drift.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: `EXIT 0`, and the log carries all five `OK:` lines with no `FAIL:`. The two that matter most are *"--repo-only detects CRLF"* and *"local mode ignores CRLF-only difference"* — together they are the proof the script discriminates rather than always answering the same thing.

- [ ] **Step 6: Run it for real against the current machine and record the number**

```bash
~/.claude/skills/session-build/scripts/gate.sh check-drift-live \
  bash "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/scripts/check-drift.sh"
```

Expected: **exit 1 with exactly 5 `DIFFERS:` lines** — `session-build/scripts/ledger.py`, `session-build/steps/step-02-scope-and-collisions.md`, `session-build/steps/step-06-closeout.md`, `session-end/SKILL.md`, `session-end/assets/report-template.md`. That is the real, un-propagated drift this whole spec exists to make visible, and seeing the script name exactly those five is the acceptance criterion. **If it prints 34, the normalisation is broken.**

Peer-fork note: the peer is rewriting `skills/session-end/**` on its own branch, so the set may shift. Record what you measured and when; do not treat a moved number as a bug in the script without re-reading the list.

- [ ] **Step 7: Commit**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
git add scripts/check-drift.sh
git commit -m "feat(scripts): a drift check that reports five instead of thirty-four

Line endings are not drift. .gitattributes forces eol=crlf on *.ps1 and
eol=lf on *.sh, so a byte comparison of the installed skill tree reports
34 differences where 5 are real -- and a check that cries 34 gets
ignored, which is how the 5 sat unnoticed.

Two modes because CI has no home directory to compare against. Neither
mode carries a list of files a skill should hold: enumerating them would
hard-code one skill's internal layout and break on the next restructure."
```

---

## Task 4: Run the repo-only mode in CI

**Files:**
- Modify: `.github/workflows/lint.yml`, appending a step to the existing `syntax-check` job (its steps run at `:17-48`)
- Test: run the same command the workflow will run

**Interfaces:**
- Consumes: `scripts/check-drift.sh --repo-only` from Task 3.
- Produces: nothing other tasks read.

- [ ] **Step 1: Write the failing test**

The test is that the exact command the workflow runs succeeds from a clean checkout. Prove it can fail first, using the same CRLF injection Task 3 used — this time through the workflow's own invocation.

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
printf 'echo crlf\r\n' >> skills/session-build/scripts/gate.sh
~/.claude/skills/session-build/scripts/gate.sh ci-drift-red bash scripts/check-drift.sh --repo-only
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" checkout -- skills/session-build/scripts/gate.sh
```

Expected: non-zero, naming `skills/session-build/scripts/gate.sh`.

**Note the one exception to the surface fence:** that `git checkout --` restores a peer-owned file to its committed state after a deliberate local mutation. It writes no new content and leaves `git status` clean. Verify with `git status --porcelain` immediately after; if it shows anything under `skills/`, stop and report.

- [ ] **Step 2: Add the step to `syntax-check`**

Insert after the `hooks/**/*.ps1 parse` step (`:40-48`), keeping the file's existing Portuguese step-name style:

```yaml
      - name: skills nao divergiram do que o instalador entrega
        run: bash scripts/check-drift.sh --repo-only
```

- [ ] **Step 3: Validate the workflow is still parseable YAML**

```bash
~/.claude/skills/session-build/scripts/gate.sh lint-yml-parse \
  node -e "const fs=require('fs');const s=fs.readFileSync('C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/.github/workflows/lint.yml','utf8');if(!/check-drift\.sh --repo-only/.test(s))throw new Error('step not present');if(/\t/.test(s))throw new Error('tab character in YAML');console.log('lint.yml carries the step, no tabs')"
```

Expected: `EXIT 0`, `lint.yml carries the step, no tabs`. This repo has no YAML parser dependency, so the check is a targeted assertion rather than a full parse — stated plainly so nobody reads it as more than it is.

- [ ] **Step 4: Run the command exactly as CI will**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
~/.claude/skills/session-build/scripts/gate.sh ci-drift-green bash scripts/check-drift.sh --repo-only
```

Expected: `EXIT 0`, `check-drift: repo-only clean`.

- [ ] **Step 5: Commit**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
git add .github/workflows/lint.yml
git commit -m "ci: check the skills tree for the drift a runner can actually see

A runner has no ~/.claude to compare against, so CI runs the repo-only
mode: every skill has a SKILL.md, no *.sh carries CR, every *.ps1 does.
The comparison against an installed tree stays a local command."
```

---

## Task 5: Say plainly what the symlink path costs

**Files:**
- Modify: `README.md:33-37`
- Test: read it back and check the claims against the code just written

**Interfaces:**
- Consumes: the behaviour Tasks 2 and 3 created.
- Produces: nothing other tasks read.

- [ ] **Step 1: Replace `README.md:33-37`**

The current text says Windows needs Developer Mode and that without it the script copies. That is now incomplete in a way that matters: Developer Mode alone never worked, and the reader deserves the hazard as well as the benefit.

```markdown
`install.sh` prefere **symlink**, pra que um `git pull` neste repo atualize tudo que já está instalado. Windows só permite symlink com o **Modo de Desenvolvedor ligado** (`Configurações > Sistema > Para desenvolvedores`).

Sem ele, o script **copia e diz que copiou**. Copia funciona igual, com uma diferença que importa: ela não se atualiza sozinha, então depois de cada `git pull` aqui você roda `./install.sh` de novo.

> O `ln -s` do Git Bash não falha quando não consegue symlinkar — ele copia e retorna sucesso. Por isso o script escreve um symlink de teste e pergunta ao disco o que ficou lá, em vez de confiar no código de saída.
>
> E o Git Bash não cria symlink nativo sem `MSYS=winsymlinks:nativestrict`, **nem com o Modo de Desenvolvedor ligado**. Até 2026-09-02 o probe não setava essa variável, então ele respondia "esta máquina não symlinka" numa máquina que symlinka, e todo mundo no Windows ficava na cópia sem saber. Ligar o Modo de Desenvolvedor sozinho não resolvia nada.

**O que o symlink te dá, e o que ele te cobra.** Com symlink, `~/.claude/skills/session-end` **é** o `skills/session-end` deste repo: editar um é editar o outro, e propagar deixa de ser tarefa pra virar `git add`. O preço é o mesmo fato visto de outro lado — uma edição quebrada aqui é uma skill quebrada em toda sessão, na hora, sem passar por commit. Se preferir a rede de proteção, `./install.sh --skills --copy` continua copiando.

**Pra saber se o que roda é o que está commitado:** `bash scripts/check-drift.sh` compara `skills/**` com o que está instalado, ignorando fim de linha — sem isso a comparação acusa 34 diferenças onde só 5 são reais, e um check que grita 34 ninguém lê. O CI roda `bash scripts/check-drift.sh --repo-only`, que é o que um runner consegue provar sem ter um `~/.claude`.
```

- [ ] **Step 2: Verify every claim in that text against the code**

Not a formality — the README is where a wrong claim survives longest.

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
grep -c "MSYS=winsymlinks:nativestrict" install.sh
grep -n "repo-only" scripts/check-drift.sh | head -3
grep -n "check-drift" .github/workflows/lint.yml
```

Expected: `2` for the first (probe and real link — if it prints 1, Task 2 Step 4 was skipped), the `--repo-only` branch present, and the CI step present.

- [ ] **Step 3: Confirm the drift number quoted in the README is the number the script prints**

```bash
bash scripts/check-drift.sh 2>&1 | grep -c "^DIFFERS:"
```

If this is not 5, **change the README to the measured number** rather than leaving the prose to age. A number in documentation that nobody re-measured is exactly the `stale-cause` failure the sibling skill spends a section on.

- [ ] **Step 4: Commit**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
git add README.md
git commit -m "docs(readme): what the symlink gives you, and what it charges

Developer Mode alone never worked, which the old text implied it did.
And the trade-off was missing entirely: with symlink, a broken edit in
this repo is a broken skill in every session immediately, with no commit
in between. That is the same fact as the benefit, seen from the side
that can hurt."
```

---

## Task 6: Fallback — the mirroring hook

**RUN THIS TASK ONLY IF Task 1 recorded `SYMLINK-LOADS: no`.** If it recorded `yes`, skip the task and say so in the final report; do not build a fallback for a path that works. If it recorded `inconclusive`, Task 1 already ended the turn with `BLOCKED`.

**Files:**
- Create: `hooks/mirror-skills.ps1`
- Modify: `README.md` (append to the section Task 5 wrote)
- Test: run the hook body directly against a scratch file

**Interfaces:**
- Consumes: Task 1's verdict.
- Produces: a hook the user may wire into `settings.json` themselves. **This plan does not edit the user's `settings.json`** — the repo ships `settings.example.json` and the README explains the wiring, matching how `reap-orphans.ps1` is already handled ("o `install.sh` copia mas **não liga**").

- [ ] **Step 1: Write the failing test**

```bash
cat > "$(mktemp -d)/t-mirror.sh" <<'EOF'
#!/usr/bin/env bash
# The mirror must copy a changed skill file into the repo AND normalise line endings.
set -uo pipefail
REPO="$1"
src="$(mktemp -d)"; mkdir -p "$src/skills/session-end"
printf 'line one\r\nline two\r\n' > "$src/skills/session-end/SKILL.md"
dst="$(mktemp -d)"; mkdir -p "$dst/skills/session-end"
pwsh -NoProfile -File "$REPO/hooks/mirror-skills.ps1" \
  -SourceRoot "$src/skills" -RepoSkills "$dst/skills" -RelativePath "session-end/SKILL.md"
rc=0
[ -f "$dst/skills/session-end/SKILL.md" ] || { echo "FAIL: file not mirrored"; rc=1; }
if grep -qU $'\r' "$dst/skills/session-end/SKILL.md" 2>/dev/null; then
  echo "FAIL: CRLF survived the mirror"; rc=1
else
  echo "OK: mirrored and normalised"
fi
rm -rf "$src" "$dst"
exit "$rc"
EOF
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/.claude/skills/session-build/scripts/gate.sh mirror-red bash <path-to>/t-mirror.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: non-zero — the script does not exist.

- [ ] **Step 3: Write `hooks/mirror-skills.ps1`**

```powershell
<#
.SYNOPSIS
  Mirror an edited session skill file from ~/.claude into this repo.

.DESCRIPTION
  The fallback for machines where a symlinked skill directory does not load.
  Copies one file and NORMALISES ITS LINE ENDINGS to LF on the way, because a
  mirror that preserves CRLF reproduces the exact noise this repo added
  check-drift.sh to remove: 34 reported differences where 5 are real.

  Two honest limits, stated rather than discovered:
    - it only sees writes made through Claude Code's Write/Edit tools;
    - it copies, it does not commit. Committing stays the user's.

  Wire it yourself in settings.json as a PostToolUse hook on Write|Edit. This
  repo ships the script and does not enable it, the same way reap-orphans.ps1
  is shipped and left switched off.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [Parameter(Mandatory=$true)][string]$RepoSkills,
  [Parameter(Mandatory=$true)][string]$RelativePath
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $SourceRoot $RelativePath
if (-not (Test-Path -LiteralPath $src)) {
  Write-Error "mirror-skills: source does not exist: $src"
  exit 1
}

$dst = Join-Path $RepoSkills $RelativePath
$dstDir = Split-Path -Parent $dst
if (-not (Test-Path -LiteralPath $dstDir)) {
  New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
}

# Read as text, write with LF. -Raw keeps the file as one string so the
# replacement is exact rather than line-by-line reassembly.
$content = Get-Content -LiteralPath $src -Raw
$content = $content -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($dst, $content, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "mirrored: $RelativePath"
```

- [ ] **Step 4: Syntax-gate it the way CI does**

`lint.yml` already parses `hooks/**/*.ps1` at `:40-48`; run the same check locally.

```bash
~/.claude/skills/session-build/scripts/gate.sh mirror-parse \
  pwsh -NoProfile -Command "\$null = [System.Management.Automation.Language.Parser]::ParseFile('C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/hooks/mirror-skills.ps1', [ref]\$null, [ref]\$errors); if (\$errors) { \$errors; exit 1 }; 'parsed'"
```

Expected: `EXIT 0`, `parsed`.

- [ ] **Step 5: Run the test again**

```bash
~/.claude/skills/session-build/scripts/gate.sh mirror-green bash <path-to>/t-mirror.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: `EXIT 0`, `OK: mirrored and normalised`.

- [ ] **Step 6: Confirm the new file obeys the repo's own line-ending rule**

`.gitattributes` says `*.ps1 text eol=crlf`. The drift check written in Task 3 enforces it, so run it rather than reasoning about it.

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
~/.claude/skills/session-build/scripts/gate.sh repo-only-after-mirror bash scripts/check-drift.sh --repo-only
```

Expected: `EXIT 0`. A red here means the new `.ps1` landed with LF; fix the file, not the check.

- [ ] **Step 7: Document it and commit**

Append to the README section Task 5 wrote:

```markdown
**Se a sua máquina não carrega skill symlinkada.** `hooks/mirror-skills.ps1` copia pro repo cada arquivo de skill editado, normalizando fim de linha na ida. Ele é enviado desligado: você liga em `settings.json` como hook `PostToolUse` em `Write|Edit`, igual ao `reap-orphans.ps1`. Duas limitações honestas: ele só enxerga edição feita pelas ferramentas do Claude Code, e ele copia — commitar continua sendo seu.
```

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
git add hooks/mirror-skills.ps1 README.md
git commit -m "feat(hooks): mirror skill edits into the repo when symlinks will not do

Shipped switched off, like reap-orphans.ps1. It normalises line endings
on the way in -- a mirror that preserves CRLF would recreate the exact
noise check-drift.sh exists to remove."
```

---

## Final verification, after every task

- [ ] **Full gate order, read rather than inferred**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
~/.claude/skills/session-build/scripts/gate.sh final-install-parse bash -n install.sh
~/.claude/skills/session-build/scripts/gate.sh final-drift-parse bash -n scripts/check-drift.sh
~/.claude/skills/session-build/scripts/gate.sh final-statusline node --check statusline/statusline.mjs
~/.claude/skills/session-build/scripts/gate.sh final-settings-json node -e "JSON.parse(require('fs').readFileSync('settings.example.json','utf8'));console.log('valid')"
~/.claude/skills/session-build/scripts/gate.sh final-repo-only bash scripts/check-drift.sh --repo-only
```

Every skill `*.sh` and `*.{js,mjs}` also parses — run those loops as CI does, one gate each, and read the logs.

- [ ] **The installer smoke tests, as CI runs them**

Run the `install-smoke` job's steps locally against `CLAUDE_CONFIG_DIR="$(mktemp -d)"`: dry-run writes nothing · unknown argument fails · install and every target exists · reinstall re-syncs · a user file is preserved without `--force` · `--settings` preserves the rest · `--uninstall` removes only what it installed. **These now exercise the symlink path for the first time on this machine**, so a failure here is Task 2's, not CI's.

- [ ] **Push**

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && git push -u origin fix/skill-propagation-20260902
```

Never `--force`, never `--no-verify`. Confirm the ref landed with `git ls-remote`, not with the exit code.

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task: the root-cause `MSYS` fix → Task 2 (both sites, and the plan fails Task 5 Step 2 if only one was done); the gating precondition → Task 1, with the automated attempt required before any manual claim; the drift check with its two modes → Tasks 3 and 4; the README trade-off → Task 5; the mirroring-hook fallback → Task 6, conditional on Task 1. The spec's "Sequencing against the other spec" section is a constraint on `/session-end`, not a task here, and is carried in the Global Constraints as the fence forbidding a real `install.sh --skills` this run.

**Placeholder scan.** No `TBD`, no "similar to Task N", no "add error handling". Every code step carries the literal content. The three `<path-to>` markers are scratch-file paths created inside the step that uses them; each is created by an explicit `cat > "$(mktemp -d)/..."` in the immediately preceding step.

**Type consistency.** `check-drift.sh` is called identically everywhere: `bash scripts/check-drift.sh` and `bash scripts/check-drift.sh --repo-only`. Its three exit codes (0 clean / 1 drift / 2 usage) are used consistently, including the `exit 2` when `$INSTALLED` is absent. `mirror-skills.ps1`'s three parameters — `-SourceRoot`, `-RepoSkills`, `-RelativePath` — match between its definition in Task 6 Step 3 and its invocation in Task 6 Step 1.

**One gap found and closed during review:** Task 4 Step 1 mutates a peer-owned file (`skills/session-build/scripts/gate.sh`) to prove the CI check can go red, which brushes the surface fence. It is a local mutation immediately reverted with `git checkout --` on a file whose committed state is unchanged, and the step now carries an explicit `git status --porcelain` confirmation with a stop condition. Called out rather than left implicit, because "I only reverted it" is what someone says after the revert did not happen.

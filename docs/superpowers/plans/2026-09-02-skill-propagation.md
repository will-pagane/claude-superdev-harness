# Skill Propagation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **EXCEPTION FOR THIS RUN:** this plan is executed by a `session-build` **fork**, whose boilerplate forbids the `Agent` tool. Subagent-driven-development therefore cannot run. Implement **inline, one task at a time**, running each task's verification and reading real output before marking it done.

**Goal:** Make an edit to a session skill reach this repository automatically, by fixing the installer's symlink probe, and give the repository a drift check that can actually go red — locally against an installed tree, and in CI against a tree CI installs for itself.

**Architecture:** Three independent pieces plus one gating experiment. Task 1 answers whether Claude Code loads a skill whose directory is a symlink; the primary path depends on it and nothing else does. Task 2 fixes `install.sh`'s capability probe, which today answers "this system cannot symlink" on a system that can. Task 3 adds `scripts/check-drift.sh` with two modes. Task 4 adds the Windows job that is the only check able to fail on the original bug. Task 5 wires both drift modes into CI — the repo-only mode over the checkout, and the comparison mode over an installation CI builds itself. Task 6 documents the trade-off. Task 7 is the fallback and runs **only if Task 1 answers no**.

**Tech Stack:** Bash (`set -euo pipefail`), PowerShell (fallback only), GitHub Actions, Git Bash / MSYS2 on Windows, Python 3 with PyYAML for workflow validation.

**Spec:** `docs/superpowers/specs/2026-09-02-skill-propagation-design.md`

## Scope of the claim, stated precisely

An earlier draft of this plan said it made "undetected drift impossible". **That was false and is corrected here.** What each mode can and cannot prove:

| Mode | Proves | Cannot prove |
|---|---|---|
| `--repo-only`, over the checkout | Repository invariants: every skill has a `SKILL.md`, `*.sh` are LF, `*.ps1` are CRLF | Anything about what is installed on any machine |
| comparison mode, locally | The developer's `~/.claude` matches this checkout, line endings ignored | Anything about anyone else's machine |
| comparison mode, in CI (Task 5) | That the comparison mode itself works — CI installs into a temp dir, confirms clean, mutates, confirms red | That any *developer's* machine is clean |

The drift this spec exists to catch is a developer's, and no CI can see it. What CI can do is guarantee the instrument works, so a developer running it locally gets a trustworthy answer. That is the honest claim.

## Global Constraints

- **`set -euo pipefail` is already set in `install.sh:24`.** Every edit must stay safe under `-e`.
- **This repository runs NO local git hooks.** `core.hooksPath` is unset and `.git/hooks` holds only samples. A clean commit proves nothing; every gate is one you run and read yourself.
- **Gates run through `~/.claude/skills/session-build/scripts/gate.sh`** — absolute path, the skill's script. This repo has no `scripts/gate.sh`.
- **Gate order:** `bash -n install.sh` · `node --check statusline/statusline.mjs` · `bash -n` on every `skills/**/*.sh` · `node --check` on every `skills/**/*.{js,mjs}` · `node -e JSON.parse` on `settings.example.json` · then the installer integration tests in `.github/workflows/lint.yml`.
- **No migrations and no deploys exist in this repository.** Checked: no `supabase/`, no `package.json`, and `.github/workflows/` holds only `lint.yml`.
- **Surface fence.** This plan writes only `install.sh`, `scripts/check-drift.sh`, `scripts/symlink-oracle.sh`, `scripts/validate-workflow.py`, `.github/workflows/lint.yml`, `README.md`, `hooks/mirror-skills.ps1` (Task 7 only), and its own plan/review files. `skills/**` and `docs/cadeia-session.md` belong to the peer fork. **No test in this plan mutates a file under `skills/**`, even temporarily** — see below.
- **Two absolute fences on `~/.claude`:**
  1. Any probe writing under `C:/Users/willi/.claude/` writes **only** inside `skills/symlink-probe/`.
  2. **Never run `install.sh --skills` against the real `~/.claude` during this run.** Always `export CLAUDE_CONFIG_DIR="$(mktemp -d)"`.
- **Language:** code, comments, commit messages in English; `README.md` prose in Brazilian Portuguese.
- **`python3` DOES NOT WORK ON THIS MACHINE, and every step that needs Python must resolve the interpreter.** Measured 2026-09-02: `command -v python3` succeeds and points at `…/WindowsApps/python3`, which is the Microsoft Store stub — it prints "Python nao foi encontrado" and runs nothing, while still being found on `PATH`. `python` is a real 3.12.10. On `ubuntu-latest` the reverse is likelier: `python3` exists and `python` may not. So **`command -v` is not enough, and neither is an exit status: the interpreter is probed by its OUTPUT**, and every local step that runs Python resolves it first:

```bash
PYBIN=""
for c in python3 python; do
  # Probe by OUTPUT, not by exit status. The failure mode is an interpreter that
  # runs nothing; a shim is free to print its error and still exit 0, and then a
  # status-only probe hands you a PYBIN that produces no work. Measured here on
  # 2026-09-02 the Store stub does exit 49 - but that is luck, not a contract.
  if [ "$("$c" -c 'print("PY_OK")' 2>/dev/null)" = "PY_OK" ]; then PYBIN="$c"; break; fi
done
[ -n "$PYBIN" ] || { echo "no working python interpreter"; exit 2; }
echo "PYBIN=$PYBIN"
```

CI steps hardcode `python3`, which is correct **there** and stated as an environment fact rather than a portable assumption.

### Never mutate the shared tree to test

An earlier draft proved the CRLF check could go red by appending `\r\n` to `skills/session-build/scripts/gate.sh` and restoring it with `git checkout --`. Two things are wrong with that, and both are fatal rather than stylistic:

- The file is **peer-owned** and the worktree is shared with concurrent sessions. `git checkout -- <path>` over a path another session may be writing destroys work that is not yours — tree-mutating recovery, which this skill family forbids outright.
- An interruption between the mutation and the restore leaves a tracked peer file dirty with no record of why.

**Every mutation test in this plan operates on a throwaway copy under `$(mktemp -d)`.** `check-drift.sh` derives the repo root from its own location, so a copied tree is a first-class subject: `cp -R` the skeleton, mutate the copy, run the script from the copy, delete it. Nothing in the real worktree is touched, no trap is needed to undo anything, and an interruption leaves a temp directory rather than a dirty repository.

---

## Corrections to the spec, made from readings taken against the live tree

| Spec says | Measured 2026-09-02 in this worktree | Consequence |
|---|---|---|
| "a byte comparison of the **23** skill files reports **23** differences … stripping `\r` reports **five**" | **41** skill files; **34** raw byte differences; **5** normalised | The ratio is worse than claimed. Acceptance uses the measured numbers. |
| Task 1 probes by symlinking `~/.claude/skills/session-end` | Forbidden by the dispatch fence | Probe uses a throwaway directory; no rollback of a real skill needed. |
| CI mode "verifies that every skill directory holds the files the installer expects" | Conflicts with the layout-agnostic fence | CI asserts a `SKILL.md` per skill plus line-ending rules. No file manifest. |

Confirmed by direct measurement rather than assumed:

- `MSYS=winsymlinks:nativestrict ln -sfn <dir> <dst>` creates a real **directory** symlink here: `test -L` true, `test -d` true, contents list through it.
- `claude` is on `PATH` at `2.1.258`, with **no `claude skill` subcommand** (`--help` enumerates `agents auth auto-mode doctor gateway import install logs mcp plugin project respawn rm`). No deterministic listing exists, so Task 1's automated attempt must be functional.
- **PyYAML 6.0.3** is importable here under `python` (3.12.10); `python3` on this machine is the Microsoft Store stub and runs nothing, so the interpreter is resolved functionally rather than by name (see Global Constraints). CI installs PyYAML **pinned** rather than assuming the runner ships it. `actionlint` is **not** installed here.

---

## Considered and rejected

Written into the plan rather than argued in chat, so the next review reads a document that answers these rather than one that ignores them.

**1. A Windows CI job.** *Was rejected in round 1. That rejection was WRONG and is withdrawn — the job is now Task 4.*

The round-1 argument rested on one load-bearing claim: that a regression is caught at runtime by `[ -L "$dst" ] || die` in `install_path`. **That claim is false in exactly the failure mode being fixed.** If `MSYS` is removed from `can_symlink()`, the probe returns false, `MODE` becomes `copy`, and the `ln -sfn` branch — which is where the `die` lives — is never reached. The installer silently copies and nothing goes red anywhere. A safeguard that does not execute in the scenario it is cited for is not a safeguard, and citing it was the error.

The cost argument fell too, and for a reason worth naming: the counter-proposal was **a small dedicated job containing only the symlink-mode test**, not Windows variants of all seven `install-smoke` steps. I costed a proposal nobody had made.

**But the replacement gets the same scrutiny the rejection did, which is where a second defect appears.** The obvious Windows job — "install, assert the targets are symlinks" — is **vacuous against this very regression**. Remove `MSYS` from `can_symlink()` and the probe says "cannot symlink"; the installer then honestly copies; probe and behaviour agree; a consistency check passes. The job would go green on the exact bug it exists to catch.

So Task 4 asserts against an **independent oracle**: it determines by itself, using the known-correct method, whether this runner can create a directory symlink, and then requires `can_symlink()` to agree with that answer. Remove `MSYS` from the probe and the oracle says *can* while the probe says *cannot* — disagreement, red. That is a test of the thing that actually broke.

**2. `actionlint` for workflow validation.** *Still rejected, with one claim corrected.*

`actionlint` is not installed here, and adding a Go binary to a repo whose CI is seven `bash -n` calls is disproportionate. The underlying objection stands and is addressed: the earlier draft's substring `grep` was not validation and would accept malformed indentation.

**One thing round 1's rejection asserted and should not have: duplicate keys.** `yaml.safe_load` does **not** reject duplicate mapping keys — it accepts them and the last value wins — so citing that case was an overclaim. Task 5 now uses a loader that raises on duplicate keys explicitly, so the claim and the code agree. And per the round-2 objection, the validation no longer runs only on this machine: CI installs a **pinned** PyYAML and runs the same assertions, rather than relying on a runner image happening to ship it.

---

## File Structure

| File | Responsibility |
|---|---|
| `install.sh` (modify, two sites) | Decide symlink-vs-copy correctly, and create the link. Sites: `can_symlink()` at `:73-84`, `install_path()`'s `ln -sfn` at `:147`. |
| `scripts/check-drift.sh` (create) | Report real drift, normalised. Two modes, one script, because the normalisation rule is shared and two copies would drift apart. |
| `scripts/validate-workflow.py` (create) | Structural validation of the workflow, including duplicate mapping keys, which `yaml.safe_load` accepts silently. |
| `scripts/symlink-oracle.sh` (create) | Decide independently whether a directory symlink is possible, then require `can_symlink()` to agree. The only check that fails on the original bug. |
| `.github/workflows/lint.yml` (modify) | Run repo-only mode over the checkout, and exercise comparison mode against an installation CI builds. |
| `README.md` (modify, `:33-37`) | What the symlink path gives and what it charges. |
| `hooks/mirror-skills.ps1` (create, **Task 7 only**) | Fallback mirror, if Task 1 answers no. |

---

## Task 1: Answer whether Claude Code loads a symlinked skill directory

Gates the primary path; nothing else depends on it. Writes to `~/.claude`, so it is fenced to a throwaway directory, aborts rather than proceeds on a surprise, and cleans up from a trap so an interruption cannot strand the link.

**Files:**
- Create (temporary, outside the repo): a temp root holding the probe skill source
- Create (temporary, outside the repo): `~/.claude/skills/symlink-probe` → that source
- Test: the probe is its own verification

**Interfaces:**
- Consumes: nothing.
- Produces: a verdict in the fork ledger — `SYMLINK-LOADS: yes` / `no` / `inconclusive`. **Task 7 runs if and only if the verdict is `no`.** Tasks 2-6 proceed regardless.

### The whole probe is ONE script, and that is a correctness requirement

An earlier draft spread this across six fenced blocks that shared `PROBE_ROOT`, `PROBE_LINK` and `NONCE` as shell variables. **That cannot work, in either direction.** Run each block in its own shell and Step 1's `EXIT` trap fires the instant Step 1 ends, deleting the probe root before Step 2 writes into it — and the variables are gone anyway. Run them all in one shell and the `EXIT` trap has still not fired when the "confirm cleanup happened" step asserts that it has. The lifecycle was impossible as written.

So Task 1 is a single script, written to a fixed path, with one trap, and cleanup performed **explicitly before** the final assertions rather than left to `EXIT`. Every later task that shares state between steps follows the same rule: **one dependent sequence, one script, no variables crossing a fence boundary.**

- [ ] **Step 1: Write the probe script**

```bash
mkdir -p /tmp/skillprop
cat > /tmp/skillprop/probe-symlink-load.sh <<'OUTER'
#!/usr/bin/env bash
# Answers: does Claude Code load a skill whose directory is a symlink?
# One script, one trap, cleanup before the final assertions.
set -uo pipefail

PROBE_LINK="$HOME/.claude/skills/symlink-probe"
PROBE_ROOT=""
KEEP=0            # set to 1 to deliberately leave the probe for a human

cleanup_probe() {
  if [ "$KEEP" -eq 1 ]; then
    echo "PROBE LEFT IN PLACE DELIBERATELY at $PROBE_LINK -> $PROBE_ROOT/symlink-probe"
    echo "Remove with: rm -f '$PROBE_LINK' && rm -rf '$PROBE_ROOT'"
    return 0
  fi
  # Unlink ONLY if the destination is still the symlink we made. If something
  # replaced it with a real directory, removing it could destroy a real skill.
  if [ -L "$PROBE_LINK" ]; then
    rm -f "$PROBE_LINK"
  elif [ -e "$PROBE_LINK" ]; then
    echo "cleanup: $PROBE_LINK is NOT a symlink - leaving it alone, investigate" >&2
  fi
  [ -n "$PROBE_ROOT" ] && [ -d "$PROBE_ROOT" ] && rm -rf "$PROBE_ROOT"
  return 0
}
# Signal traps must TERMINATE, not just clean up: a bare `trap cleanup INT`
# lets bash resume after the handler and operate on a probe that is now gone.
trap 'cleanup_probe; exit 130' INT
trap 'cleanup_probe; exit 143' TERM
trap cleanup_probe EXIT

if [ -e "$PROBE_LINK" ] || [ -L "$PROBE_LINK" ]; then
  echo "ABORT: $PROBE_LINK already exists - investigate before probing" >&2
  exit 1
fi

PROBE_ROOT="$(mktemp -d)"
echo "PRE-STATE: no symlink-probe present; traps armed; PROBE_ROOT=$PROBE_ROOT"

# A fixed magic string is a false positive waiting to happen: the model is told
# to invoke /symlink-probe and could produce a plausible constant without the
# skill resolving at all. This nonce is generated now and written ONLY into the
# symlink target - unguessable, absent from training data, absent from this repo.
NONCE="probe-$(date +%s)-$$-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
mkdir -p "$PROBE_ROOT/symlink-probe"
cat > "$PROBE_ROOT/symlink-probe/SKILL.md" <<INNER
---
name: symlink-probe
description: Throwaway probe that answers whether Claude Code loads a skill whose directory is a symlink. Delete on sight.
---

# Symlink probe

Reply with exactly this line and nothing else:

$NONCE
INNER
echo "NONCE=$NONCE"

MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -sfn "$PROBE_ROOT/symlink-probe" "$PROBE_LINK"
if [ ! -L "$PROBE_LINK" ]; then
  echo "NOT A SYMLINK - probe cannot answer the question" >&2
  exit 1
fi
[ -d "$PROBE_LINK" ] || { echo "LINK IS NOT A DIRECTORY - probe invalid" >&2; exit 1; }
[ -f "$PROBE_LINK/SKILL.md" ] || { echo "LINK DOES NOT RESOLVE - probe invalid" >&2; exit 1; }
echo "IS A DIRECTORY SYMLINK AND RESOLVES"

# A fresh claude process reads the skills directory from scratch, so no human
# restart is needed. There is no `claude skill` subcommand, so this is a
# FUNCTIONAL test: the nonce can only appear if the skill was actually read.
OUT="$(mktemp)"
claude -p "/symlink-probe" --allowedTools "Skill" > "$OUT" 2>&1
claude_rc=$?
echo "--- claude exit: $claude_rc, output follows ---"
sed -n '1,40p' "$OUT"
echo "--- end output ---"

hits="$(grep -c "$NONCE" "$OUT" 2>/dev/null || true)"

VERDICT="inconclusive"
if [ "${hits:-0}" -ge 1 ]; then
  VERDICT="yes"
elif grep -qiE "unknown skill|no such skill|not found|does not exist" "$OUT"; then
  VERDICT="no"
fi
# A killed or empty run decided nothing. Never read it as `no`.
if [ ! -s "$OUT" ]; then
  VERDICT="inconclusive"
fi

echo "SYMLINK-LOADS: $VERDICT (nonce hits=$hits, claude exit=$claude_rc)"
echo "LOG: $OUT"

if [ "$VERDICT" = "inconclusive" ]; then
  KEEP=1     # leave it for a human; the trap now reports instead of removing
  exit 3
fi

# Clean up EXPLICITLY, then assert. The EXIT trap would not have run yet.
cleanup_probe
trap - EXIT INT TERM
if [ -e "$PROBE_LINK" ] || [ -L "$PROBE_LINK" ]; then
  echo "STILL PRESENT - investigate" >&2; exit 1
fi
[ -d "$PROBE_ROOT" ] && { echo "TEMP ROOT STILL PRESENT: $PROBE_ROOT" >&2; exit 1; }
echo "REMOVED and TEMP ROOT REMOVED"
exit 0
OUTER
chmod +x /tmp/skillprop/probe-symlink-load.sh
bash -n /tmp/skillprop/probe-symlink-load.sh && echo "probe script parses"
```

- [ ] **Step 2: Run it and read the verdict**

```bash
~/.claude/skills/session-build/scripts/gate.sh probe-symlink-load bash /tmp/skillprop/probe-symlink-load.sh
```

Read the gate's log. Three outcomes, and the exit code distinguishes them:

- `EXIT 0` with `SYMLINK-LOADS: yes` → the nonce came back. It exists only inside the symlink target, so the harness resolved and read the skill through the link.
- `EXIT 0` with `SYMLINK-LOADS: no` → the harness reported the skill unknown.
- `EXIT 3` → **inconclusive**, and the probe has been left in place deliberately. Go to Step 3.
- Anything else, or a `GATE … ` line the gate could not complete → the probe itself failed. Re-read the log; do not record a verdict.

- [ ] **Step 3: Only on exit 3 — escalate as a genuinely manual step**

```
BLOCKED symlink-load verdict inconclusive. Tried: throwaway directory symlink at
~/.claude/skills/symlink-probe (test -L, test -d, test -f on SKILL.md all true);
headless `claude -p "/symlink-probe"` with a per-run nonce; the nonce did not
appear and the output carried no "skill not found" signal either. Decisive line:
<paste>. No `claude skill` subcommand exists to list skills deterministically
(claude 2.1.258). Needs a human to restart Claude Code and confirm whether
symlink-probe appears. THE PROBE IS STILL INSTALLED for that check; the script
prints the exact two commands that remove it.
```

- [ ] **Step 4: Record the verdict**

```bash
python ~/.claude/skills/session-build/scripts/ledger.py append \
  --dir "C:/dev/Projects/claude-setup/.superpowers/session-build/20260902-0447" \
  --fork skill-propagation --type READING \
  --text "SYMLINK-LOADS: <yes|no|inconclusive>. Method: throwaway directory symlink at ~/.claude/skills/symlink-probe created with MSYS append, verified test -L, test -d and test -f; per-run nonce <value> written only into the symlink target; headless claude -p /symlink-probe; grep for the nonce in the gate log returned <n>. Probe removed, confirmed by listing. Gates Task 7."
```

No commit — this task changes no repository file.

---

## Task 2: Make the probe and the real link ask the right question

**Files:**
- Modify: `install.sh:73-84` (`can_symlink`), `install.sh:147` (`ln -sfn`)
- Test: an end-to-end install into a throwaway `CLAUDE_CONFIG_DIR`

**Interfaces:**
- Consumes: nothing.
- Produces: `MODE=symlink` where symlinks are possible. Tasks 3-5 describe behaviour this creates but import no code from it.

- [ ] **Step 1: Write the test, with the two defects of the earlier draft fixed**

The earlier version suppressed all installer output and treated any non-symlink as a `--copy` success — so an installer that failed outright printed a pass. This version captures output, prints it on failure, requires the installer to succeed, and abstains honestly where the assertion cannot go red.

```bash
mkdir -p /tmp/skillprop
cat > /tmp/skillprop/t-symlink-install.sh <<'EOF'
#!/usr/bin/env bash
# Asserts install.sh LINKS rather than copies where symlinks are possible.
# Deliberately no -e: it must survive a failed assertion long enough to report all of them.
set -uo pipefail
REPO="$1"
MODE_EXPECT="${2:-symlink}"      # symlink | copy

# This assertion can only go red under MSYS. Anywhere else `ln -s` already
# works, MODE is already symlink, and a green proves nothing about the bug.
# Exit 3 = SKIPPED, deliberately distinct from 0. A skip that exits 0 is
# indistinguishable from a pass by any caller that reads only the status, which
# is how a vacuous green gets mistaken for evidence.
if [ "$MODE_EXPECT" = "symlink" ] && [ -z "${MSYSTEM:-}" ]; then
  echo "SKIPPED - not MSYS/Git Bash, this assertion cannot go red here"
  exit 3
fi

CLAUDE_CONFIG_DIR="$(mktemp -d)"; export CLAUDE_CONFIG_DIR
LOG="$(mktemp)"
if [ "$MODE_EXPECT" = "copy" ]; then
  "$REPO/install.sh" --skills --copy >"$LOG" 2>&1
else
  "$REPO/install.sh" --skills >"$LOG" 2>&1
fi
install_rc=$?
if [ "$install_rc" -ne 0 ]; then
  echo "FAIL: installer exited $install_rc"; sed -n '1,60p' "$LOG"
  rm -rf "$CLAUDE_CONFIG_DIR" "$LOG"; exit 1
fi

rc=0
count=0
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"; target="$CLAUDE_CONFIG_DIR/skills/$name"; count=$((count+1))
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    echo "MISSING $name"; rc=1; continue
  fi
  if [ "$MODE_EXPECT" = "symlink" ]; then
    [ -L "$target" ] || { echo "NOT A SYMLINK: $name"; rc=1; }
  else
    [ -L "$target" ] && { echo "UNEXPECTED SYMLINK under --copy: $name"; rc=1; }
    [ -f "$target/SKILL.md" ] || { echo "COPY INCOMPLETE: $name has no SKILL.md"; rc=1; }
  fi
done
[ "$count" -eq 0 ] && { echo "FAIL: zero skills found - the test proved nothing"; rc=1; }

# The installer prints LINK or COPY per target; assert the reported mode too,
# so a disagreement between what it says and what it did is caught.
if [ "$MODE_EXPECT" = "symlink" ]; then
  grep -q "LINK" "$LOG" || { echo "FAIL: installer never reported LINK"; rc=1; }
else
  grep -q "COPY" "$LOG" || { echo "FAIL: installer never reported COPY"; rc=1; }
fi

[ "$rc" -ne 0 ] && { echo "--- installer output ---"; sed -n '1,60p' "$LOG"; }
[ "$rc" -eq 0 ] && echo "OK: $count skills, mode=$MODE_EXPECT as expected"
rm -rf "$CLAUDE_CONFIG_DIR" "$LOG"
exit "$rc"
EOF
echo "test written"
```

- [ ] **Step 2: Run it to make sure it fails, and read WHY**

```bash
~/.claude/skills/session-build/scripts/gate.sh symlink-install-red \
  bash /tmp/skillprop/t-symlink-install.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected on this machine: non-zero, with `NOT A SYMLINK:` lines and `installer never reported LINK`. **If the gate reports `EXIT 3` and `SKIPPED`, this machine cannot prove the fix and the prove-red has not happened** — say so, and do not treat the later green as evidence. Exit 3 is deliberately not 0, so a skip can never be read as a pass by a caller that only checks the status.

- [ ] **Step 3: Fix the probe — directory symlink, sentinel, MSYS appended not overwritten**

Three changes. The probe now creates a **directory** symlink, because that is what the installer creates and Windows treats file and directory symlinks as distinct operations — a file-symlink probe can succeed where a directory symlink is refused. It resolves a sentinel through the link, so "the link exists" and "the link works" are separate assertions. And `MSYS` is **appended to**, because assigning it would silently discard the user's own runtime options.

```bash
# Symlink e capacidade do SISTEMA, nao do SO: Windows com Developer Mode ligado
# symlinka, Windows sem ele nao. `ln -s` do Git Bash e pior que falhar — ele
# COPIA e retorna 0, entao a unica leitura confiavel e escrever um symlink de
# teste e perguntar ao `test -L` se o que ficou no disco e mesmo um symlink.
#
# E o Git Bash NAO cria symlink nativo sem MSYS=winsymlinks:nativestrict, nem
# com o Developer Mode ligado. Sem essa variavel o probe responde "esta maquina
# nao symlinka" numa maquina que symlinka, o install cai pra copia, e a copia
# nunca mais se atualiza. A variavel e inerte fora do MSYS, e e ADICIONADA ao
# $MSYS que ja existir — sobrescrever descartaria opcao do usuario.
#
# O probe linka um DIRETORIO com um sentinela dentro, nao um arquivo: e isso que
# o instalador realmente cria, e o Windows trata symlink de arquivo e de
# diretorio como operacoes distintas.
can_symlink() {
  local probe_dir probe_src probe_dst rc
  probe_dir="$(mktemp -d 2>/dev/null)" || return 1
  probe_src="$probe_dir/src"; probe_dst="$probe_dir/dst"
  mkdir -p "$probe_src"
  : > "$probe_src/sentinel"
  rc=1
  if MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -s "$probe_src" "$probe_dst" 2>/dev/null \
     && [ -L "$probe_dst" ] && [ -d "$probe_dst" ] && [ -f "$probe_dst/sentinel" ]; then
    rc=0
  fi
  rm -rf "$probe_dir"
  return $rc
}
```

- [ ] **Step 4: Fix the real link at `install.sh:147`**

A probe answering yes is worthless if the install still copies. Same variable, same append.

```bash
  if [ "$MODE" = "symlink" ]; then
    MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -sfn "$src" "$dst"
    # Verifica em vez de confiar: o `ln` do Git Bash retorna 0 depois de copiar.
    [ -L "$dst" ] || die "esperava symlink em $dst e o disco tem outra coisa — rode com --copy"
    info "${GRN}LINK${RST}  $dst ${DIM}-> $src${RST}"
```

The existing `[ -L "$dst" ] || die` is what makes this fail closed and stays exactly as it is.

- [ ] **Step 5: Syntax gate before behaviour**

```bash
~/.claude/skills/session-build/scripts/gate.sh install-parse bash -n "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/install.sh"
```

Expected: `EXIT 0`.

- [ ] **Step 6: Run the test again and read the log**

```bash
~/.claude/skills/session-build/scripts/gate.sh symlink-install-green \
  bash /tmp/skillprop/t-symlink-install.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: `EXIT 0`, `OK: <n> skills, mode=symlink as expected`.

- [ ] **Step 7: Confirm `--copy` still copies, with the installer's status guarded**

```bash
~/.claude/skills/session-build/scripts/gate.sh copy-still-copies \
  bash /tmp/skillprop/t-symlink-install.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" copy
```

Expected: `EXIT 0`, `OK: <n> skills, mode=copy as expected`. The same script serves both modes, so the copy path gets the same installer-succeeded and completeness checks — the earlier draft printed success for a missing target.

- [ ] **Step 8: Commit**

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && git add install.sh
git commit -m "fix(install): the probe that asked the wrong question

Git Bash does not create a native symlink without
MSYS=winsymlinks:nativestrict, and can_symlink() did not set it. So the
probe answered 'this system cannot symlink' on a system that can, the
install fell back to copy, and a copy never updates itself. Developer
Mode alone does not change that -- it was already on when this was
measured.

Two smaller corrections in the same place. The probe now links a
DIRECTORY with a sentinel inside, because that is what install_path
creates and Windows treats the two as different operations. And MSYS is
appended to rather than assigned, so a user's own runtime options
survive."
```

`git branch --show-current` must print `fix/skill-propagation-20260902` before the commit, every time.

---

## Task 3: `scripts/check-drift.sh`

**Files:**
- Create: `scripts/check-drift.sh`
- Test: a throwaway copy of the tree, mutated

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/check-drift.sh`. Task 4 calls it as `bash scripts/check-drift.sh --repo-only` and as `bash scripts/check-drift.sh`.
  - no argument → comparison mode against `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills`
  - `--repo-only` → repository invariants only
  - exit `0` clean, `1` drift, `2` usage or missing precondition

- [ ] **Step 1: Write the test, on a copied tree, with the CRLF case fixed**

The earlier draft's CRLF assertion could never pass: it renamed the divergent file to `SKILL.md.bak` **inside the compared tree**, so the script correctly reported `ONLY IN ~/.claude` and the test read that correct answer as a failure. Here the backup lives outside the compared tree, and every mutation happens on a copy.

```bash
mkdir -p /tmp/skillprop
cat > /tmp/skillprop/t-check-drift.sh <<'EOF'
#!/usr/bin/env bash
# Proves check-drift.sh can BOTH pass and fail, for the right reasons.
# Every mutation happens on a COPY. The real worktree is never touched.
set -uo pipefail
REPO="$1"
rc=0

# --- repo-only: clean tree passes -------------------------------------------
bash "$REPO/scripts/check-drift.sh" --repo-only >/dev/null 2>&1 \
  && echo "OK: --repo-only green on a clean tree" \
  || { echo "FAIL: --repo-only red on a clean tree"; rc=1; }

# --- repo-only: CRLF in a .sh is caught, on a COPY --------------------------
copy="$(mktemp -d)/repo"
mkdir -p "$copy"
cp -R "$REPO/skills" "$REPO/scripts" "$copy/" 2>/dev/null
[ -d "$REPO/hooks" ] && cp -R "$REPO/hooks" "$copy/"
printf 'echo crlf\r\n' >> "$copy/skills/session-build/scripts/gate.sh"
if bash "$copy/scripts/check-drift.sh" --repo-only >/dev/null 2>&1; then
  echo "FAIL: --repo-only stayed green with a CRLF .sh"; rc=1
else
  echo "OK: --repo-only detects CRLF in a .sh"
fi
rm -rf "$(dirname "$copy")"

# --- repo-only: a skill with no SKILL.md is caught, on a COPY ---------------
copy2="$(mktemp -d)/repo"
mkdir -p "$copy2"
cp -R "$REPO/skills" "$REPO/scripts" "$copy2/" 2>/dev/null
[ -d "$REPO/hooks" ] && cp -R "$REPO/hooks" "$copy2/"
mkdir -p "$copy2/skills/no-skill-file"
if bash "$copy2/scripts/check-drift.sh" --repo-only >/dev/null 2>&1; then
  echo "FAIL: --repo-only stayed green with a skill lacking SKILL.md"; rc=1
else
  echo "OK: --repo-only detects a missing SKILL.md"
fi
rm -rf "$(dirname "$copy2")"

# --- comparison mode --------------------------------------------------------
fake_home="$(mktemp -d)"
mkdir -p "$fake_home/skills"
cp -R "$REPO/skills/." "$fake_home/skills/"
CLAUDE_CONFIG_DIR="$fake_home" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1 \
  && echo "OK: comparison green on an identical copy" \
  || { echo "FAIL: comparison red on an identical copy"; rc=1; }

echo "a real difference" >> "$fake_home/skills/session-end/SKILL.md"
if CLAUDE_CONFIG_DIR="$fake_home" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1; then
  echo "FAIL: comparison stayed green with a real difference"; rc=1
else
  echo "OK: comparison detects a real difference"
fi

# CRLF-only difference must be IGNORED. The backup lives OUTSIDE the compared
# tree - an earlier version left a .bak inside it, which the script correctly
# reported as an extra file, and the test misread that as a failure.
stash="$(mktemp -d)"
mv "$fake_home/skills/session-end/SKILL.md" "$stash/SKILL.md.orig"
sed 's/$/\r/' "$REPO/skills/session-end/SKILL.md" > "$fake_home/skills/session-end/SKILL.md"
if CLAUDE_CONFIG_DIR="$fake_home" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1; then
  echo "OK: comparison ignores a CRLF-only difference"
else
  echo "FAIL: comparison reported CRLF-only noise as drift"; rc=1
fi

# An extra file only in the installed tree must be caught.
echo "orphan" > "$fake_home/skills/session-end/ORPHAN.md"
if CLAUDE_CONFIG_DIR="$fake_home" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1; then
  echo "FAIL: comparison missed a file present only in the installed tree"; rc=1
else
  echo "OK: comparison detects an installed-only file"
fi

# Missing installed tree is a usage error (2), not a clean pass.
empty="$(mktemp -d)"
CLAUDE_CONFIG_DIR="$empty" bash "$REPO/scripts/check-drift.sh" >/dev/null 2>&1
[ "$?" -eq 2 ] && echo "OK: missing installed tree exits 2" \
               || { echo "FAIL: missing installed tree did not exit 2"; rc=1; }

rm -rf "$fake_home" "$stash" "$empty"
exit "$rc"
EOF
echo "test written"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/.claude/skills/session-build/scripts/gate.sh check-drift-red \
  bash /tmp/skillprop/t-check-drift.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: non-zero — the script does not exist, so every invocation fails.

- [ ] **Step 3: Write `scripts/check-drift.sh`**

Five defects of the earlier draft are fixed here, each commented in place: roots are asserted to exist rather than silently iterated over an empty `find`; zero skills is a failure rather than a pass; the `.ps1` check validates **every** newline instead of asking whether the file contains any `\r`; the CR test is portable rather than `grep -U`; and `find` results are collected through a status-checked command.

```bash
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
#                               ~/.claude), \r stripped on both sides.
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
  -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
  *)            echo "check-drift.sh: unknown argument: $1" >&2; exit 2 ;;
esac

drift=0

# Portable "does this file contain a CR byte". `grep -U` is GNU-only and this
# script is read by people on macOS. LC_ALL=C keeps the match byte-exact.
has_cr() { LC_ALL=C grep -q "$(printf '\r')" "$1" 2>/dev/null; }

# Resolve a python that actually RUNS. On Windows, `command -v python3` finds
# the Microsoft Store stub: it is on PATH, it prints an error and it executes
# nothing. Existence is not capability, so probe it. Declared here, before any
# mode uses it, because `set -u` turns an unset PYBIN into a hard error the
# moment a repo contains a single .ps1 file.
PYBIN=""
for c in python3 python; do
  # Probe by OUTPUT, not by exit status: the failure mode is "runs nothing", and
  # a shim may print its error and still exit 0.
  if [ "$("$c" -c 'print("PY_OK")' 2>/dev/null)" = "PY_OK" ]; then
    PYBIN="$c"; break
  fi
done

if [ "$MODE" = "repo-only" ]; then
  # A missing root must be an ERROR, not an empty loop that reports clean.
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
  # Zero skills would otherwise sail through every loop below.
  if [ "$skill_count" -eq 0 ]; then
    echo "check-drift: found ZERO skill directories - this check proved nothing" >&2
    exit 2
  fi

  # Collect through a status-checked command: a failing `find` inside a process
  # substitution cannot fail the parent shell, so its status must be captured.
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

  # *.ps1 must be CRLF THROUGHOUT. Asking only "contains a CR" passes a file
  # with one CRLF and five hundred LFs, and passes a lone CR too.
  # Build the list of roots that EXIST, then run a status-checked find over
  # them. The earlier `2>/dev/null || true` swallowed a real find failure and
  # reported clean - which contradicted this script's own promise to fail closed.
  ps_roots=""
  [ -d "$REPO_DIR/skills" ] && ps_roots="$ps_roots $REPO_DIR/skills"
  [ -d "$REPO_DIR/hooks" ]  && ps_roots="$ps_roots $REPO_DIR/hooks"
  ps_list="$(mktemp)"
  if [ -n "$ps_roots" ]; then
    # shellcheck disable=SC2086 -- ps_roots is a deliberate word-split list of paths
    find $ps_roots -type f -name '*.ps1' > "$ps_list" || {
      echo "check-drift: find failed while listing *.ps1" >&2; rm -f "$ps_list"; exit 2; }
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -z "$PYBIN" ]; then
      echo "check-drift: no working python interpreter; cannot validate *.ps1 line endings" >&2
      rm -f "$ps_list"; exit 2
    fi
    verdict="$("$PYBIN" - "$f" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
lf   = data.count(b'\n')
crlf = data.count(b'\r\n')
cr   = data.count(b'\r')
if lf != crlf:
    print("BARE-LF")
elif cr != crlf:
    print("LONE-CR")
else:
    print("OK")
PY
)"
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

inst_list="$(mktemp)"
(cd "$INSTALLED" && find . -type f) > "$inst_list" || {
  echo "check-drift: find failed over the installed tree" >&2; rm -f "$inst_list"; exit 2; }
while IFS= read -r rel; do
  rel="${rel#./}"
  [ -n "$rel" ] || continue
  if [ ! -f "$REPO_DIR/skills/$rel" ]; then
    echo "ONLY IN INSTALLED TREE: $rel"; drift=1
  fi
done < "$inst_list"
rm -f "$inst_list"

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
  bash /tmp/skillprop/t-check-drift.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: `EXIT 0`, and the log carries eight `OK:` lines with no `FAIL:`. The three that matter most are *"--repo-only detects CRLF in a .sh"*, *"comparison detects a real difference"* and *"comparison ignores a CRLF-only difference"* — together they prove the script discriminates rather than always answering the same thing.

- [ ] **Step 6: Run it for real and record the number**

```bash
~/.claude/skills/session-build/scripts/gate.sh check-drift-live \
  bash "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/scripts/check-drift.sh"
```

Expected: **exit 1 with exactly 5 `DIFFERS:` lines** — `session-build/scripts/ledger.py`, `session-build/steps/step-02-scope-and-collisions.md`, `session-build/steps/step-06-closeout.md`, `session-end/SKILL.md`, `session-end/assets/report-template.md`. **If it prints 34, the normalisation is broken.**

The peer fork is rewriting `skills/session-end/**` on its own branch, so the set may shift. Record what was measured and when; a moved number is not a bug in the script until the list has been re-read.

- [ ] **Step 7: Commit**

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && git add scripts/check-drift.sh
git commit -m "feat(scripts): a drift check that reports five instead of thirty-four

Line endings are not drift. .gitattributes forces eol=crlf on *.ps1 and
eol=lf on *.sh, so a byte comparison of the installed skill tree reports
34 differences where 5 are real -- and a check that cries 34 gets
ignored, which is how the 5 sat unnoticed.

Two modes because CI has no home directory to compare against, and the
help text says plainly which one proves what. Neither carries a list of
files a skill should hold: enumerating them would hard-code one skill's
internal layout and break on the next restructure.

Every loop fails closed. A missing root, zero skills, or a failing find
exits 2 rather than iterating over nothing and reporting clean."
```

---

## Task 4: The Windows job — an independent oracle, not a consistency check

Added in round 2, after the round-1 rejection was refuted, and moved AHEAD of the CI task in round 3: `scripts/validate-workflow.py` asserts this job exists, so the job has to be in the workflow before the validator is run against it. **The point of this job is that it can go red when `MSYS` is removed from `can_symlink()`, which no Linux job can.**

**The trap this job has to avoid.** The obvious version — install, then assert the targets are symlinks — is *vacuous against this very regression*. Remove `MSYS` from the probe and it reports "cannot symlink", the installer honestly copies, probe and behaviour agree, and a consistency check goes green on the bug. So the job determines the answer **itself**, by the known-correct method, and then requires `can_symlink()` to agree with it. Disagreement is the failure signal.

**Files:**
- Create: `scripts/symlink-oracle.sh`
- Modify: `.github/workflows/lint.yml` — one job, `symlink-probe-windows`
- Test: run the oracle locally, where it must agree with what this machine actually does

**Interfaces:**
- Consumes: `install.sh` from Task 2.
- Produces: nothing other tasks read. `scripts/validate-workflow.py` (Task 5 Step 4) asserts this job exists and runs on `windows-latest` — which is why this task comes first.

- [ ] **Step 1: Write the oracle script**

Write `scripts/symlink-oracle.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Does install.sh's capability probe agree with reality?
#
# This exists because the obvious test is vacuous. Asserting "the installer
# produced symlinks" PASSES when the probe wrongly says the system cannot
# symlink, because the installer then honestly copies and everything agrees
# with everything. That is precisely the bug this repo just fixed.
#
# So: work out INDEPENDENTLY whether a directory symlink is possible here,
# using the method known to be correct, then require can_symlink() to say the
# same thing. Delete MSYS=winsymlinks:nativestrict from the probe and the
# oracle still says "can" while the probe says "cannot" -> red.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --require-capable: fail when this machine cannot create a directory symlink
# at all. Without it the job passes vacuously on such a runner - oracle=no and
# installed=no agree, and the regression coverage silently disappears. CI
# passes the flag; a developer running it locally on a machine without symlink
# capability does not, and gets an honest "agrees, both no".
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
```

Then:

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
chmod +x scripts/symlink-oracle.sh
~/.claude/skills/session-build/scripts/gate.sh oracle-parse bash -n scripts/symlink-oracle.sh
```

Expected: `EXIT 0`.

- [ ] **Step 2: Prove it can go red, by removing MSYS from a COPY of install.sh**

The regression is simulated on a copy. The real `install.sh` is never edited to test it.

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
PYBIN="$(for c in python3 python; do [ "$("$c" -c 'print("PY_OK")' 2>/dev/null)" = "PY_OK" ] && { echo "$c"; break; }; done)"
[ -n "$PYBIN" ] || { echo "no working python interpreter"; exit 2; }
rm -rf /tmp/skillprop/oracle-red && mkdir -p /tmp/skillprop/oracle-red
cp -R install.sh skills scripts /tmp/skillprop/oracle-red/

# The mutation is GUARDED: exactly one substitution must happen, or the test
# would run without simulating anything and its red would mean nothing.
"$PYBIN" - /tmp/skillprop/oracle-red/install.sh <<'MUT'
import sys, pathlib
# BYTES, not text. Path.write_text() applies platform newline translation,
# so on Windows it rewrites install.sh with CRLF endings - and then bash cannot
# parse it, so the prove-red goes red because the file is broken rather than
# because the oracle
# caught the simulated regression. A red for the wrong reason is worse than no
# test. (Measured while writing this plan: an earlier revision of THIS FILE was
# silently converted to CRLF by exactly that call.)
p = pathlib.Path(sys.argv[1])
data = p.read_bytes()
probe = b'MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -s "$probe_src"'
n = data.count(probe)
if n != 1:
    sys.exit("MUTATION ABORTED: expected exactly 1 probe occurrence, found %d. "
             "The pattern drifted; fix this test rather than trusting its red." % n)
p.write_bytes(data.replace(probe, b'ln -s "$probe_src"'))
print("mutated: MSYS removed from can_symlink() only, bytes preserved")
MUT

# Assert the SPECIFIC commands, not a word count: `grep -c winsymlinks` also
# counts the explanatory comment block, so it can never be 1.
grep -q 'MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -s "$probe_src"' /tmp/skillprop/oracle-red/install.sh   && { echo "MUTATION DID NOT APPLY - probe still carries MSYS"; exit 1; }   || echo "confirmed: probe no longer carries MSYS"
grep -q 'MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ln -sfn "$src"' /tmp/skillprop/oracle-red/install.sh   && echo "confirmed: the real link still carries MSYS (only the probe was broken)"   || { echo "MUTATION TOO BROAD - the real ln lost MSYS too"; exit 1; }

# The mutated installer must still PARSE, or the oracle's red could come from
# bash choking on a corrupted file rather than from the simulated bug.
~/.claude/skills/session-build/scripts/gate.sh oracle-red-parses bash -n /tmp/skillprop/oracle-red/install.sh

~/.claude/skills/session-build/scripts/gate.sh oracle-red bash /tmp/skillprop/oracle-red/scripts/symlink-oracle.sh
rm -rf /tmp/skillprop/oracle-red
```

Expected on this machine: both `confirmed:` lines, `oracle-red-parses` **EXIT 0**, then the gate returning **non-zero** with `MISMATCH: this system can symlink=yes but install.sh produced symlinks=no`.

**This is the single most important prove-red in the plan.** It is the only check anywhere that fails on the original bug.

- [ ] **Step 3: Run it unmodified, and expect agreement**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
~/.claude/skills/session-build/scripts/gate.sh oracle-green bash scripts/symlink-oracle.sh
```

Expected: `EXIT 0`, `OK: probe and reality agree (both yes)`.

- [ ] **Step 4: Add the job**

Small and dedicated, as the counter-proposal asked — it runs the oracle and nothing else. No Windows variants of `install-smoke`'s seven steps.

```yaml
  symlink-probe-windows:
    runs-on: windows-latest
    defaults:
      run:
        shell: bash
    steps:
      - uses: actions/checkout@v4

      - name: o probe do install.sh concorda com a realidade da maquina
        run: bash scripts/symlink-oracle.sh --require-capable
```

`shell: bash` on `windows-latest` is Git Bash, which is the environment this whole fix is about.

- [ ] **Step 5: Validate and commit**

`scripts/validate-workflow.py` does not exist yet — it is written in Task 5, which then validates the workflow with this job already in it. Sanity-check the YAML shape here with the parser alone:

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
PYBIN="$(for c in python3 python; do [ "$("$c" -c 'print("PY_OK")' 2>/dev/null)" = "PY_OK" ] && { echo "$c"; break; }; done)"
[ -n "$PYBIN" ] || { echo "no working python interpreter"; exit 2; }
~/.claude/skills/session-build/scripts/gate.sh yml-parses-after-windows "$PYBIN" -c "import yaml; d=yaml.safe_load(open('.github/workflows/lint.yml',encoding='utf-8')); assert d['jobs']['symlink-probe-windows']['runs-on']=='windows-latest'; print('job present, runs-on windows-latest')"
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
git add scripts/symlink-oracle.sh .github/workflows/lint.yml
git commit -m "ci(windows): catch the regression no Linux job can see

The fix is Windows-only, so nothing in the existing two Linux jobs goes
red if MSYS=winsymlinks:nativestrict is ever deleted from can_symlink().
An earlier draft argued the runtime guard covered it. It does not: with
the probe under-reporting, MODE becomes copy and the ln branch holding
that guard never executes.

The obvious job would have been vacuous for the same reason -- remove
MSYS, the probe says no, the installer honestly copies, and probe and
behaviour agree. So this asks an INDEPENDENT oracle whether a directory
symlink is possible here, and requires the probe to agree with it."
```

**On the first CI run, read the result rather than assuming it.** The job passes `--require-capable`, so if `windows-latest` turns out not to permit symlink creation the job goes **red with a precondition error** rather than passing vacuously — which is the honest outcome, because a green there would mean the regression coverage had quietly disappeared. If that happens, the finding is about the runner, not about `install.sh`: record it, and take it to the user rather than deleting the flag to get a green.

## Task 5: CI — the invariants, and proof the comparison mode works

**Files:**
- Modify: `.github/workflows/lint.yml` — a step in `syntax-check`, and a new job
- Test: the same commands, run locally

**Interfaces:**
- Consumes: `scripts/check-drift.sh` from Task 3, `install.sh` from Task 2.
- Produces: nothing other tasks read.

- [ ] **Step 1: Prove the CI command can go red — on a copy, never on the shared tree**

```bash
copy="$(mktemp -d)/repo"; mkdir -p "$copy"
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
cp -R skills scripts "$copy/"; [ -d hooks ] && cp -R hooks "$copy/"
printf 'echo crlf\r\n' >> "$copy/skills/session-build/scripts/gate.sh"
~/.claude/skills/session-build/scripts/gate.sh ci-drift-red bash "$copy/scripts/check-drift.sh" --repo-only
rm -rf "$(dirname "$copy")"
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" status --porcelain
```

Expected: non-zero from the gate, naming `skills/session-build/scripts/gate.sh`; and `git status --porcelain` printing **nothing**. The real tree was never touched, so there is nothing to restore and no window in which an interruption leaves a peer's file dirty.

- [ ] **Step 2: Add the invariants step to `syntax-check`**

Insert after the `hooks/**/*.ps1 parse` step (`:40-48`), keeping the file's Portuguese step-name style:

```yaml
      - name: invariantes do repo (SKILL.md por skill, fim de linha)
        run: bash scripts/check-drift.sh --repo-only
```

- [ ] **Step 3: Add the job that exercises comparison mode**

`--repo-only` cannot see drift between a repo and an installation, which is the drift this spec is about. A runner has no `~/.claude` — but it can build one, and then the comparison mode is testable. This job proves the instrument, not any developer's machine.

```yaml
  drift-check-works:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: instala numa CLAUDE_CONFIG_DIR temporaria
        run: |
          set -euo pipefail
          echo "CLAUDE_CONFIG_DIR=$RUNNER_TEMP/claude-home" >> "$GITHUB_ENV"
          CLAUDE_CONFIG_DIR="$RUNNER_TEMP/claude-home" ./install.sh --skills --copy

      - name: sem divergencia logo apos instalar
        run: bash scripts/check-drift.sh

      - name: divergencia real e detectada
        run: |
          set -euo pipefail
          target="$(find "$CLAUDE_CONFIG_DIR/skills" -name 'SKILL.md' -print -quit)"
          test -n "$target" || { echo "nenhum SKILL.md instalado"; exit 1; }
          echo "uma diferenca real" >> "$target"
          if bash scripts/check-drift.sh; then
            echo "FALHOU: o check ficou verde com divergencia real"; exit 1
          fi
          echo "ok: divergencia detectada"

      - name: diferenca so de fim de linha e ignorada
        run: |
          set -euo pipefail
          target="$(find "$CLAUDE_CONFIG_DIR/skills" -name 'SKILL.md' -print -quit)"
          rel="${target#"$CLAUDE_CONFIG_DIR/skills/"}"
          sed 's/$/\r/' "skills/$rel" > "$target"
          bash scripts/check-drift.sh
```

The last step's success **is** the assertion: after rewriting the installed file with CRLF endings and identical content, the check must exit 0. If normalisation ever breaks, that step goes red.

- [ ] **Step 4: Write `scripts/validate-workflow.py`**

A substring grep would accept malformed indentation or the step text sitting inside a comment. Two corrections over the earlier draft, both from round 2: **`yaml.safe_load` does not reject duplicate mapping keys** — it accepts them and the last wins — so a loader that raises on them is written explicitly rather than claimed; and the validator lives in a file so **CI can run the same code**, instead of the assertions existing only on this machine.

```python
#!/usr/bin/env python3
"""Validate a GitHub workflow structurally, not by substring.

Two things a `grep` cannot do and this can: reject a duplicate mapping key
(PyYAML's safe_load accepts them silently, last-one-wins), and assert that a
step lives inside a particular job's `steps` list rather than merely appearing
somewhere in the file - including inside a comment.
"""
import sys
import yaml


class NoDuplicatesLoader(yaml.SafeLoader):
    pass


def _no_duplicates(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.YAMLError(f"duplicate key {key!r} at line {key_node.start_mark.line + 1}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


NoDuplicatesLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates
)


def runs_of(job):
    return [s.get("run", "") for s in job.get("steps", [])]


def main(path):
    with open(path, encoding="utf-8") as fh:
        doc = yaml.load(fh, Loader=NoDuplicatesLoader)

    jobs = doc["jobs"]
    problems = []

    if not any("check-drift.sh --repo-only" in r for r in runs_of(jobs.get("syntax-check", {}))):
        problems.append("repo-only step is not inside jobs.syntax-check.steps")

    if "drift-check-works" not in jobs:
        problems.append("job drift-check-works is missing")
    else:
        dw = runs_of(jobs["drift-check-works"])
        if not any("install.sh --skills --copy" in r for r in dw):
            problems.append("drift-check-works never installs")
        if not any(r.strip().endswith("check-drift.sh") for r in dw):
            problems.append("drift-check-works never runs comparison mode")

    if "symlink-probe-windows" not in jobs:
        problems.append("job symlink-probe-windows is missing")
    elif jobs["symlink-probe-windows"].get("runs-on") != "windows-latest":
        problems.append("symlink-probe-windows does not run on windows-latest")

    if problems:
        for p in problems:
            print(f"INVALID: {p}", file=sys.stderr)
        return 1
    print(f"{path}: parses, no duplicate keys, all required steps structurally present")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ".github/workflows/lint.yml"))
```

Prove it can reject before trusting it to accept — on a copy, never on the real workflow:

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
PYBIN="$(for c in python3 python; do [ "$("$c" -c 'print("PY_OK")' 2>/dev/null)" = "PY_OK" ] && { echo "$c"; break; }; done)"
[ -n "$PYBIN" ] || { echo "no working python interpreter"; exit 2; }
mkdir -p /tmp/skillprop
sed 's/^jobs:/jobs:
  syntax-check:
    runs-on: ubuntu-latest/' .github/workflows/lint.yml > /tmp/skillprop/dup.yml
~/.claude/skills/session-build/scripts/gate.sh yml-validator-red "$PYBIN" scripts/validate-workflow.py /tmp/skillprop/dup.yml
~/.claude/skills/session-build/scripts/gate.sh yml-validator-green "$PYBIN" scripts/validate-workflow.py .github/workflows/lint.yml
```

Expected: `yml-validator-red` **non-zero** with a duplicate-key error, and `yml-validator-green` `EXIT 0`. A validator never seen to reject is not a validator.

- [ ] **Step 5: Run the validator in CI too, with PyYAML pinned**

Round 2's objection stands: a runner image *happening* to ship PyYAML is not a contract. Add to `syntax-check`, before the invariants step:

```yaml
      - name: workflow e valido estruturalmente
        run: |
          python3 -m pip install --quiet --disable-pip-version-check 'PyYAML==6.0.3'
          python3 scripts/validate-workflow.py .github/workflows/lint.yml
```

- [ ] **Step 6: Run the invariants command exactly as CI will**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
~/.claude/skills/session-build/scripts/gate.sh ci-drift-green bash scripts/check-drift.sh --repo-only
```

Expected: `EXIT 0`, `check-drift: repo-only clean (<n> skills)`.

- [ ] **Step 7: Rehearse the new job locally, end to end**

The job is new, so run its steps by hand before trusting them — a CI job that has never executed is a claim.

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
H="$(mktemp -d)"
CLAUDE_CONFIG_DIR="$H" ./install.sh --skills --copy >/dev/null
~/.claude/skills/session-build/scripts/gate.sh rehearse-clean env CLAUDE_CONFIG_DIR="$H" bash scripts/check-drift.sh
t="$(find "$H/skills" -name SKILL.md -print -quit)"; echo "uma diferenca real" >> "$t"
~/.claude/skills/session-build/scripts/gate.sh rehearse-dirty env CLAUDE_CONFIG_DIR="$H" bash scripts/check-drift.sh
rel="${t#"$H/skills/"}"; sed 's/$/\r/' "skills/$rel" > "$t"
~/.claude/skills/session-build/scripts/gate.sh rehearse-crlf env CLAUDE_CONFIG_DIR="$H" bash scripts/check-drift.sh
rm -rf "$H"
```

Expected: `rehearse-clean` EXIT 0 · `rehearse-dirty` **EXIT 1** · `rehearse-crlf` EXIT 0. The middle one going red is the point.

- [ ] **Step 8: Commit**

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && git add .github/workflows/lint.yml
git commit -m "ci: check the invariants, and prove the drift check can go red

A runner has no ~/.claude, so it cannot see the drift this repo cares
about. Two different things follow, and conflating them was the earlier
mistake: syntax-check asserts what a checkout can prove about itself,
and a new job installs into a temp CLAUDE_CONFIG_DIR so comparison mode
has something to compare -- clean after install, red after a real edit,
green again when the only difference is line endings.

That proves the instrument works. It does not prove anyone's laptop is
clean, and the script's help text now says so."
```

---

---

## Task 6: Say plainly what the symlink path costs

**Files:**
- Modify: `README.md:33-37`
- Test: read it back and check every claim against the code just written

**Interfaces:**
- Consumes: behaviour from Tasks 2, 3 and 4.
- Produces: nothing other tasks read.

- [ ] **Step 1: Replace `README.md:33-37`**

```markdown
`install.sh` prefere **symlink**, pra que um `git pull` neste repo atualize tudo que já está instalado. Windows só permite symlink com o **Modo de Desenvolvedor ligado** (`Configurações > Sistema > Para desenvolvedores`).

Sem ele, o script **copia e diz que copiou**. Copia funciona igual, com uma diferença que importa: ela não se atualiza sozinha, então depois de cada `git pull` aqui você roda `./install.sh` de novo.

> O `ln -s` do Git Bash não falha quando não consegue symlinkar — ele copia e retorna sucesso. Por isso o script escreve um symlink de teste e pergunta ao disco o que ficou lá, em vez de confiar no código de saída.
>
> E o Git Bash não cria symlink nativo sem `MSYS=winsymlinks:nativestrict`, **nem com o Modo de Desenvolvedor ligado**. Até 2026-09-02 o probe não setava essa variável, então respondia "esta máquina não symlinka" numa máquina que symlinka, e todo mundo no Windows ficava na cópia sem saber. Ligar o Modo de Desenvolvedor sozinho não resolvia nada.

**O que o symlink te dá, e o que ele te cobra.** Com symlink, `~/.claude/skills/session-end` **é** o `skills/session-end` deste repo: editar um é editar o outro, e propagar deixa de ser tarefa pra virar `git add`. O preço é o mesmo fato visto de outro lado — uma edição quebrada aqui é uma skill quebrada em toda sessão, na hora, sem passar por commit. Se preferir a rede de proteção, `./install.sh --skills --copy` continua copiando.

**Pra saber se o que roda é o que está commitado:** `bash scripts/check-drift.sh` compara `skills/**` com o que está instalado, ignorando fim de linha — sem isso a comparação acusa 34 diferenças onde só 5 são reais, e um check que grita 34 ninguém lê.

**O CI não enxerga o seu `~/.claude`, e não finge que enxerga.** Ele roda `bash scripts/check-drift.sh --repo-only`, que checa só o que um checkout prova sobre si mesmo (todo skill tem `SKILL.md`, `*.sh` em LF, `*.ps1` em CRLF), e um job separado que instala numa pasta temporária pra provar que o modo de comparação funciona — verde depois de instalar, vermelho depois de uma edição real, verde de novo quando a única diferença é fim de linha. Quem roda a comparação na sua máquina é você.
```

- [ ] **Step 2: Verify every claim in that text against the code**

The README is where a wrong claim survives longest.

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
grep -c "winsymlinks:nativestrict" install.sh
grep -n "repo-only" scripts/check-drift.sh | head -3
grep -n "check-drift" .github/workflows/lint.yml
grep -c "drift-check-works" .github/workflows/lint.yml
```

Expected: `2` for the first — probe and real link. **If it prints 1, Task 2 Step 4 was skipped and the README's central claim is false.** Then the `--repo-only` branch present, the CI steps present, and `drift-check-works` present.

- [ ] **Step 3: Confirm the drift number quoted in the README is the number the script prints**

```bash
bash scripts/check-drift.sh 2>&1 | grep -c "^DIFFERS:"
```

If this is not 5, **change the README to the measured number.** A number in documentation that nobody re-measured is exactly the `stale-cause` failure the sibling skill devotes a section to.

- [ ] **Step 4: Commit**

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && git add README.md
git commit -m "docs(readme): what the symlink gives you, and what it charges

Developer Mode alone never worked, which the old text implied it did.
The trade-off was missing entirely: with symlink, a broken edit in this
repo is a broken skill in every session immediately, with no commit in
between -- the same fact as the benefit, seen from the side that hurts.

And it says which drift CI can see, which is none of yours."
```

---

## Task 7: Fallback — the mirroring hook

**RUN THIS TASK ONLY IF Task 1 recorded `SYMLINK-LOADS: no`.** On `yes`, skip it and say so in the final report. On `inconclusive`, Task 1 already ended the turn with `BLOCKED`.

**Files:**
- Create: `hooks/mirror-skills.ps1`
- Modify: `README.md` (append to the section Task 6 wrote)
- Test: run the hook the way the harness runs it — event JSON on stdin

**Interfaces:**
- Consumes: Task 1's verdict.
- Produces: a hook the user wires into `settings.json` themselves. **This plan does not edit `settings.json`** — the repo ships `settings.example.json` and documents the wiring, exactly as `reap-orphans.ps1` is shipped and left switched off.

- [ ] **Step 1: Write the test, against the real invocation contract**

The earlier draft invoked the hook with three command-line parameters including a per-event relative path. That is not how a `PostToolUse` hook is called: the harness passes **event JSON on stdin**, and the script derives the edited path from it. A hook tested through an interface nobody uses is not tested.

```bash
mkdir -p /tmp/skillprop
cat > /tmp/skillprop/t-mirror.sh <<'EOF'
#!/usr/bin/env bash
# The mirror must: read event JSON on stdin, mirror the file, normalise line
# endings, copy binaries byte-for-byte, and refuse paths outside the roots.
set -uo pipefail
REPO="$1"
rc=0

src="$(mktemp -d)"; mkdir -p "$src/skills/session-end"
dst="$(mktemp -d)"; mkdir -p "$dst/skills"

printf 'line one\r\nline two\r\nlone\rcr\n' > "$src/skills/session-end/SKILL.md"
printf '\x89PNG\r\n\x1a\n\x00\x01\x02\x03' > "$src/skills/session-end/logo.png"

run_hook() {  # $1 = file path to report in the event
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" \
  | pwsh -NoProfile -File "$REPO/hooks/mirror-skills.ps1" \
      -SourceRoot "$src/skills" -RepoSkills "$dst/skills"
}

run_hook "$src/skills/session-end/SKILL.md" >/dev/null 2>&1
if [ -f "$dst/skills/session-end/SKILL.md" ]; then
  if LC_ALL=C grep -q "$(printf '\r')" "$dst/skills/session-end/SKILL.md"; then
    echo "FAIL: CR survived the mirror (CRLF or lone CR)"; rc=1
  else
    echo "OK: text mirrored and fully normalised"
  fi
else
  echo "FAIL: text file not mirrored"; rc=1
fi

run_hook "$src/skills/session-end/logo.png" >/dev/null 2>&1
if cmp -s "$src/skills/session-end/logo.png" "$dst/skills/session-end/logo.png"; then
  echo "OK: binary copied byte-for-byte"
else
  echo "FAIL: binary was corrupted or not copied"; rc=1
fi

outside="$(mktemp -d)/escape.md"; echo "should not be mirrored" > "$outside"
if run_hook "$outside" >/dev/null 2>&1; then
  echo "FAIL: hook accepted a path outside SourceRoot"; rc=1
else
  echo "OK: path outside the root refused"
fi

if run_hook "$src/skills/../../etc/passwd" >/dev/null 2>&1; then
  echo "FAIL: hook accepted a traversal path"; rc=1
else
  echo "OK: traversal refused"
fi

rm -rf "$src" "$dst"
exit "$rc"
EOF
echo "test written"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
~/.claude/skills/session-build/scripts/gate.sh mirror-red bash /tmp/skillprop/t-mirror.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: non-zero — the script does not exist.

- [ ] **Step 3: Write `hooks/mirror-skills.ps1`**

```powershell
<#
.SYNOPSIS
  Mirror an edited session skill file from ~/.claude into this repo.

.DESCRIPTION
  The fallback for machines where a symlinked skill directory does not load.
  Reads a PostToolUse event as JSON on STDIN, derives the edited file, and
  copies it into the repo.

  Four things it is careful about, each because the obvious version is wrong:
    - it NORMALISES line endings for text, including a lone CR, because a
      mirror that preserves CRLF recreates exactly the noise check-drift.sh
      exists to remove;
    - it copies BYTES for anything not in the text extension list, because
      Get-Content/WriteAllText corrupts a PNG;
    - it REFUSES any path that does not canonicalise to somewhere beneath
      SourceRoot, so a traversal or absolute path cannot write outside;
    - it writes to a temp file in the destination directory and moves it into
      place, so no reader ever sees a half-written file.

  WHAT IT DOES NOT DO, stated because the stronger claim is tempting: this is
  atomic REPLACEMENT, not serialisation. Two events completing out of order can
  still leave the older content last, and nothing here orders them. The mirror
  is a convenience for a single editor, not a synchronisation primitive; if that
  ever matters, the fix is a per-destination lock or a version check, and this
  comment is where to start.

  Two honest limits: it only sees writes made through Claude Code's tools, and
  it copies rather than commits. Committing stays the user's.

  Shipped switched off. Wire it in settings.json as a PostToolUse hook on
  Write|Edit, the same way reap-orphans.ps1 is shipped and left disabled.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [Parameter(Mandatory=$true)][string]$RepoSkills
)

$ErrorActionPreference = 'Stop'

$TextExtensions = @('.md', '.sh', '.ps1', '.py', '.js', '.mjs', '.json', '.txt', '.yml', '.yaml', '.toml')

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { Write-Error 'mirror-skills: empty stdin; expected PostToolUse event JSON'; exit 2 }
try { $evt = $raw | ConvertFrom-Json } catch { Write-Error "mirror-skills: stdin is not valid JSON: $_"; exit 2 }

$filePath = $evt.tool_input.file_path
if ([string]::IsNullOrWhiteSpace($filePath)) { Write-Error 'mirror-skills: event carries no tool_input.file_path'; exit 2 }

# Canonicalise BOTH sides before comparing. Resolve-Path fails on a
# non-existent path, which is itself a refusal we want.
try {
  $srcFull  = (Resolve-Path -LiteralPath $filePath).Path
  $rootFull = (Resolve-Path -LiteralPath $SourceRoot).Path
} catch {
  Write-Error "mirror-skills: cannot resolve path: $_"; exit 1
}

$rootWithSep = if ($rootFull.EndsWith([IO.Path]::DirectorySeparatorChar)) { $rootFull } else { $rootFull + [IO.Path]::DirectorySeparatorChar }
if (-not $srcFull.StartsWith($rootWithSep, [StringComparison]::OrdinalIgnoreCase)) {
  Write-Error "mirror-skills: refusing path outside SourceRoot: $srcFull"; exit 1
}

$relative = $srcFull.Substring($rootWithSep.Length)
$dst      = Join-Path $RepoSkills $relative
$dstDir   = Split-Path -Parent $dst
if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }

# Write to a sibling temp file, then move into place. A partial write is never
# visible under the real name, and overlapping events cannot interleave.
$tmp = Join-Path $dstDir ('.mirror-' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
  $ext = [IO.Path]::GetExtension($srcFull).ToLowerInvariant()
  if ($TextExtensions -contains $ext) {
    $content = [IO.File]::ReadAllText($srcFull)
    $content = $content -replace "`r`n", "`n"
    $content = $content -replace "`r", "`n"      # lone CR too, not just CRLF
    [IO.File]::WriteAllText($tmp, $content, (New-Object Text.UTF8Encoding($false)))
  } else {
    [IO.File]::Copy($srcFull, $tmp, $true)
  }
  [IO.File]::Move($tmp, $dst, $true)
} catch {
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
  throw
}

Write-Output "mirrored: $relative"
```

- [ ] **Step 4: Syntax-gate it the way CI does**

```bash
~/.claude/skills/session-build/scripts/gate.sh mirror-parse \
  pwsh -NoProfile -Command "\$errors = \$null; \$null = [System.Management.Automation.Language.Parser]::ParseFile('C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902/hooks/mirror-skills.ps1', [ref]\$null, [ref]\$errors); if (\$errors) { \$errors; exit 1 }; 'parsed'"
```

Expected: `EXIT 0`, `parsed`.

- [ ] **Step 5: Run the test again**

```bash
~/.claude/skills/session-build/scripts/gate.sh mirror-green bash /tmp/skillprop/t-mirror.sh "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
```

Expected: `EXIT 0` with all four `OK:` lines — normalisation, binary integrity, outside-root refusal, traversal refusal.

**Not tested, because it is not claimed:** ordering between two overlapping events. The write is atomic in the sense that no partial file is ever visible; it is not serialised, so a later event can be overtaken by an earlier one. The script's header says so.

- [ ] **Step 6: Confirm the new file obeys the repo's own line-ending rule**

`.gitattributes` says `*.ps1 text eol=crlf`, and Task 3's check validates **every** newline rather than asking whether the file contains any CR.

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
~/.claude/skills/session-build/scripts/gate.sh repo-only-after-mirror bash scripts/check-drift.sh --repo-only
```

Expected: `EXIT 0`. A red here means the new `.ps1` landed with LF or mixed endings; fix the file, not the check.

- [ ] **Step 7: Document it with the exact settings.json entry, and commit**

Append to the README section Task 6 wrote:

````markdown
**Se a sua máquina não carrega skill symlinkada.** `hooks/mirror-skills.ps1` copia pro repo cada arquivo de skill editado, normalizando fim de linha na ida e copiando binário byte a byte. Ele é enviado **desligado** — você liga em `settings.json`, igual ao `reap-orphans.ps1`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File ~/.claude/hooks/mirror-skills.ps1 -SourceRoot ~/.claude/skills -RepoSkills C:/caminho/para/claude-setup/skills"
          }
        ]
      }
    ]
  }
}
```

Duas limitações honestas: ele só enxerga edição feita pelas ferramentas do Claude Code, e ele copia — commitar continua sendo seu.
````

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && git add hooks/mirror-skills.ps1 README.md
git commit -m "feat(hooks): mirror skill edits into the repo when symlinks will not do

Shipped switched off, like reap-orphans.ps1, with the exact settings.json
entry in the README rather than a description of one.

It reads the PostToolUse event from stdin, which is how the harness
actually calls a hook; refuses any path that does not canonicalise
beneath SourceRoot; copies bytes for anything that is not text, because
ReadAllText corrupts a PNG; normalises lone CR as well as CRLF; and
writes through a temp file so no reader ever sees half a file -- atomic
replacement, not serialisation, and the header says which."
```

---

## Final verification, after every task

- [ ] **Full gate order, read rather than inferred**

```bash
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902"
PYBIN="$(for c in python3 python; do [ "$("$c" -c 'print("PY_OK")' 2>/dev/null)" = "PY_OK" ] && { echo "$c"; break; }; done)"
[ -n "$PYBIN" ] || { echo "no working python interpreter"; exit 2; }
~/.claude/skills/session-build/scripts/gate.sh final-install-parse bash -n install.sh
~/.claude/skills/session-build/scripts/gate.sh final-drift-parse bash -n scripts/check-drift.sh
~/.claude/skills/session-build/scripts/gate.sh final-statusline node --check statusline/statusline.mjs
~/.claude/skills/session-build/scripts/gate.sh final-settings-json node -e "JSON.parse(require('fs').readFileSync('settings.example.json','utf8'));console.log('valid')"
~/.claude/skills/session-build/scripts/gate.sh final-repo-only bash scripts/check-drift.sh --repo-only
~/.claude/skills/session-build/scripts/gate.sh final-oracle-parse bash -n scripts/symlink-oracle.sh
~/.claude/skills/session-build/scripts/gate.sh final-yml-structure "$PYBIN" scripts/validate-workflow.py .github/workflows/lint.yml
~/.claude/skills/session-build/scripts/gate.sh final-oracle bash scripts/symlink-oracle.sh
```

Every skill `*.sh` and `*.{js,mjs}` also parses — run those loops as CI does, one gate each, and read the logs.

- [ ] **The installer smoke tests, as CI runs them**

Run the `install-smoke` job's steps against `CLAUDE_CONFIG_DIR="$(mktemp -d)"`: dry-run writes nothing · unknown argument fails · install and every target exists · reinstall re-syncs · a user file is preserved without `--force` · `--settings` preserves the rest · `--uninstall` removes only what it installed. **These now exercise the symlink path for the first time on this machine**, so a failure here is Task 2's, not CI's.

- [ ] **Confirm the shared tree was never dirtied**

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" status --porcelain
```

Expected: empty, or only this task's intended files. Anything under `skills/**` means a test mutated the shared tree — stop and report.

- [ ] **Push**

```bash
git -C "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" branch --show-current
cd "C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902" && git push -u origin fix/skill-propagation-20260902
```

Never `--force`, never `--no-verify`. Confirm the ref landed with `git ls-remote`, not with the exit code.

---

## Self-Review

**Spec coverage.** The `MSYS` root cause → Task 2, both sites, with Task 6 Step 2 failing loudly if only one was done. The gating precondition → Task 1, automated attempt required before any manual claim. The drift check and its two modes → Tasks 3 and 5, with Task 4 the Windows job that alone can fail on the original bug. The README trade-off → Task 6. The mirroring fallback → Task 7, conditional. The spec's sequencing section is a constraint on `/session-end`, carried in Global Constraints as the fence forbidding a real `install.sh --skills` this run.

**Placeholder scan.** No `TBD`, no "similar to Task N", no "add error handling".

**No shell variable crosses a fenced-block boundary.** Round 2 caught this as a lifecycle impossibility in Task 1 and as a latent one everywhere else: each fenced block may run in its own shell, so a `$TESTDIR` or `$PROBE_ROOT` set in one step is simply absent in the next, and a trap armed in one step fires at the end of *that step* rather than at the end of the task. Every dependent sequence is now a single script at a **fixed** path under `/tmp/skillprop/`, written in one step and invoked by path in the others. The only state shared between steps is a file on disk.

**Type consistency.** `check-drift.sh` is invoked identically everywhere and its three exit codes (0 clean / 1 drift / 2 usage-or-precondition) are used consistently, including exit 2 for a missing root, zero skills, and a missing installed tree. `mirror-skills.ps1` takes exactly `-SourceRoot` and `-RepoSkills` in its definition, its test, and the README's `settings.json` entry — the per-event path arrives on stdin, so it is not a parameter anywhere.

**Changes made in response to round 3.** Four findings, all accepted, and the first was a real ordering bug of mine: `validate-workflow.py` asserts that `symlink-probe-windows` exists, but I had put the validator in the task that ran *before* the task adding that job, so its green check could never have passed. The Windows job is now Task 4 and the CI task is Task 5, so every job exists before anything validates it; Task 4 sanity-checks its own YAML with the parser alone rather than with a validator that does not exist yet. Second, the oracle passed vacuously on a runner with no symlink capability at all — `oracle=no` and `installed=no` agree — so the CI invocation now passes `--require-capable` and the job goes red with a precondition error instead, which is the honest outcome when regression coverage disappears. Third, the prove-red's `grep -c winsymlinks` counted the explanatory comment as well as the code, so the expected count of `1` was simply false; it now asserts the specific probe command is absent and the specific real-link command is still present. Fourth, the mutation itself was unguarded — if the `sed` pattern ever stopped matching, the test would run without simulating the regression and its red would mean nothing — so it is now a Python rewrite that aborts unless exactly one occurrence is replaced.

**Changes made in response to round 2.** Eleven findings, all accepted, and one of them withdrew a round-1 decision of mine. The Windows CI job was rejected in round 1 on the claim that `[ -L "$dst" ] || die` catches a regression at runtime; that is false in the exact failure mode being fixed, because an under-reporting probe sends the installer down the copy branch where the guard never executes. Citing a safeguard that does not run in the scenario it is cited for was the error, and I had also costed a proposal nobody made — the counter-proposal was one small dedicated job, not Windows variants of `install-smoke`. Task 4 is that job, built around an **independent oracle** rather than a probe-versus-behaviour consistency check, because the consistency version is vacuous against this very regression: delete `MSYS` and probe and behaviour agree with each other while both are wrong.

The rest: Task 1's lifecycle was internally impossible (traps and variables spread across fenced blocks that may each be a separate shell) and is now one script with signal-specific traps that terminate, and explicit cleanup before the final assertions; no shell variable crosses a block boundary anywhere in the plan; `find | head -n 1` under `pipefail` can exit 141 on SIGPIPE and is now `-print -quit`; the `.ps1` discovery used `2>/dev/null || true` while the surrounding prose promised status-checked discovery, and now builds a root list and fails closed; `yaml.safe_load` does **not** reject duplicate keys, so the round-1 rejection overclaimed and the validator now uses a loader that raises on them; that validator moved into `scripts/validate-workflow.py` so CI runs it too, with PyYAML **pinned** rather than assumed present on the runner image; the mirror's concurrency claim was broader than its code and is narrowed to atomic replacement without ordering; and the installer test's skip now exits 3 rather than 0, so no caller can read an abstention as a pass.

**Changes made in response to round 1, and the two declined at that point.** Twenty-one of twenty-three findings are incorporated: the CRLF test's `.bak` inside the compared tree; the platform-dependent prove-red, now an explicit `SKIPPED` rather than a false green; the "undetected drift impossible" overclaim, now a table of what each mode can and cannot prove; the file-versus-directory symlink probe; `MSYS` appended rather than assigned; the `ABORT` that did not abort; the missing trap; unsafe cleanup; the guessable magic string, now a per-run nonce; vacuous loops over missing roots; zero skills passing; the `.ps1` check that asked only whether a CR was present; `grep -U` portability; the fake YAML validation, now a real parse plus a structural assertion; Task 4 not proving the step is inside the job; the deliberate mutation of a peer-owned tracked file, now done on a copy so no trap and no `git checkout --` is needed at all; the hook's invocation contract; path traversal; binary corruption; non-atomic writes; and lone CR. The two declined — a Windows CI job, and `actionlint` — are argued in **Considered and rejected** above, with what this plan does instead.

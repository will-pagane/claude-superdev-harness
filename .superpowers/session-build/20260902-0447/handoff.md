# Handoff — session-build run `20260902-0447` → `/session-end`

Written at close-out, 2026-09-02. **This file says what to measure, never what is still true.**
`/session-end` re-measures everything it acts on; the point of this document is that it should not
have to re-derive *which* things.

## Project profile (from step-01, unchanged all run)

| Field | Value |
|---|---|
| `merge_path` | `pr` — the repo's `CLAUDE.md` gives PR and merge to `/session-end`; this run stopped at pushed branches |
| `repo_shape` | `docs-and-shell` — markdown skills, `install.sh`, one `.mjs`. **No application code, no test suite, no `package.json` anywhere.** |
| `migration_tool` | none. No database, no `supabase/`. Steps 2 and 8's migration legs do not apply. |
| `deploy_wrapper` | none. Nothing in this repo is deployed. Step 3 and Step 8's deploy leg do not apply. |
| `gate_order` | `bash -n install.sh` → `node --check statusline/statusline.mjs` → `bash -n` on every `skills/**/*.sh` and `scripts/**/*.sh` → `node --check` on every `skills/**/*.{js,mjs}` → `JSON.parse` on `settings.example.json` → the installer integration tests in `.github/workflows/lint.yml` |
| Local git hooks | **NONE.** `core.hooksPath` unset, `.git/hooks` holds only samples. A clean commit proves nothing here; every gate is one someone runs explicitly. |

## Branches — FOUR

**A fourth branch was added after the close-out**, on a separate user request, and it is not part of
this run's ledger: `feat/brainstorm-visual-companion-20260902` — `74d6571`, cut from `origin/main`,
worktree `C:/dev/Projects/claude-setup/.claude/worktrees/brainstorm-visual-companion-20260902`.

It touches exactly two files, `skills/session-build/steps/step-01-preflight-and-brainstorm.md` and
`skills/session-build/SKILL.md`. **Both are untouched by the three branches below** — verified with
`git diff --name-only origin/main...<branch>` against each. It merges in any order, before or after
them. Gates: the repo's three parse gates EXIT 0; there is nothing else to run on a markdown change.

The three branches this run produced:

Both feature branches were cut from `docs/session-skills-specs-20260902`, which carries the specs
and the run ledger. That branch then advanced by one commit the feature branches do **not**
contain, so it needs merging too.

Measured 2026-09-02T09:0xZ.

### 1. `refactor/session-end-router-fork-lane-20260902` — `0fac8c5`
- **Range vs `origin/main`:** 20 commits · worktree `C:/dev/Projects/claude-setup/.claude/worktrees/session-end-router-fork-lane-20260902`
- **Ships:** `session-end` split into a router plus just-in-time step files; a fork lane for
  multi-branch close-out; 21 findings from all 20 real `session-end` ledgers; `gate.sh --expect`
  (four files — the two `gate.sh` and two `gate.ps1` copies are byte-identical across both skills);
  the `ledger.py` fork-init fix; and the baseline landing of text that had lived only in `~/.claude`.
- **Gates, read from real output by the orchestrator, not accepted from the fork:** `all-gates.sh`
  EXIT 0 across 30 · `assert-findings` 50/50 · `budgets` EXIT 0 · `xrefs` EXIT 0 · `ledger-probe`
  9/9 · `expect-flag` EXIT 0 on both `gate.sh` copies and both `gate.ps1` copies under
  PowerShell 5.1.26100.9278 · `reconstruct` EXIT 0.
- **Migration:** none. **Deploy:** none.
- **Fork:** alive at close-out. `agentId` for revival: `aa4c9af61017a902c`.

### 2. `fix/skill-propagation-20260902` — `8ab0509`
- **Range vs `origin/main`:** 9 commits · worktree `C:/dev/Projects/claude-setup/.claude/worktrees/skill-propagation-20260902`
- **Ships:** the `install.sh` symlink-probe fix (`MSYS=winsymlinks:nativestrict` in the probe and in
  the real `ln -sfn`), `scripts/check-drift.sh`, `scripts/symlink-oracle.sh`,
  `scripts/validate-workflow.py`, two new CI jobs, and the README's statement of what the symlink
  buys and what it charges.
- **Gates, read from real output:** full gate order green · `check-drift.sh --repo-only` EXIT 0
  ("repo-only clean (5 skills)") · `check-drift.sh` full EXIT 1 naming exactly the 5 real drifts ·
  `symlink-oracle.sh` "probe and reality agree (both yes)" · 7 installer smoke tests including
  `install created symlinks`.
- **Migration:** none. **Deploy:** none.
- **Fork:** alive at close-out. `agentId` for revival: `aba233005b82d4182`.

### 3. `docs/session-skills-specs-20260902` — `53af3b7`, plus whatever this close-out adds
- **No worktree.** It is the branch the main checkout stands on.
- **Ships:** the two specs, the run-evidence document, the run ledger and both fork ledgers, and
  this handoff.
- **Contains nothing the other two need**, and they contain nothing of it after `17eaae9`.

## Topology — two distinct deliverables, plus the record branch

Tested by ancestry at 2026-09-02T09:0xZ, not assumed from the spec count:

- `0fac8c5` and `8ab0509` are different SHAs.
- Neither is an ancestor of the other (`git merge-base --is-ancestor`, both directions: NO).
- The only files on both diffs are the four they inherited from their shared base — the three spec
  documents and `ledger.md` at `17eaae9`. Identical content on both sides.

So `/session-end` runs **once per branch**, on all three. Neither collapsed.

**Independence carries a shorter shelf life than any dependency would.** It is a claim about the
whole world, and anything merging anywhere can falsify it. Re-test before acting if time has passed.

## Merge order, and the one real constraint

There is **no code dependency** between the two feature branches. The order below is driven by the
installer, not by the graph.

1. **`refactor/session-end-router-fork-lane-20260902` first.** It rewrites `skills/session-end/**`.
2. **`fix/skill-propagation-20260902` second.**
3. **`docs/session-skills-specs-20260902` last** — the run record.

**Why the order binds, and it is not about git.** Spec B's real install step —
`./install.sh --skills` against the user's actual `~/.claude` — must not run while the rewritten
`session-end` lives only in a worktree: a symlinked `~/.claude/skills/session-end` resolves to the
**main checkout**, so installing early would silently pin the pre-restructure version. That install
was deliberately **not run during this build**; it is the first thing to do after all three merge.

## Applied in production

**Nothing.** No database exists, no migration was applied anywhere, and nothing is deployed from
this repo. The two sections that usually matter most here are genuinely empty.

## `PENDINGS-SOURCE`

**This run consumed NO pendings entry.** The repo carries no pendings file — no `PENDINGS.md`, no
`docs/PENDINGS.md`, no `docs/PENDENCIAS.md` — and both specs came from the user's request in the
originating session. Stated explicitly rather than omitted, because an absent section reads as a
forgotten one.

Consequence for `/session-end` Step 4: **Half A has no existing file to reconcile against.** Half B
still runs, and the `PARKED` entries below are its input. If it creates `PENDINGS.md`, it copies
`pendings-template.md` verbatim and writes nothing above the header.

## Locks

All released. `ledger.py sweep` at close-out: `forks=2 grants=0 outstanding=0 ungranted=0`. No
false positives to inherit — both forks named the branch as the resource on every `LOCK verify`,
which is what makes a grant matchable.

## Gitignored artifacts — none stranded

Both codex-review run directories are **committed on their branches**, not gitignored:
- `docs/codex-review/session-end-router-fork-lane-20260902-0420/` (3 files)
- `docs/codex-review/skill-propagation-20260902-0417/` (3 files)

The run ledger and both fork ledgers live in the **main checkout** and are committed on the specs
branch. So removing either worktree strands nothing that this handoff or the pendings cite.

## PARKED — carried from both forks, and one from the orchestrator

Draft pendings entries. Density is deliberate: whoever closes these cannot re-open the
investigation.

1. **ACCEPTED — the fork lane ships unexercised.** No real `N ≥ 2` `session-end` close-out has run
   it, and nothing in this repo can. Stated in the lane file's own text. Blast radius is the lane
   itself; the inline and sequential lanes are unchanged. Unblocks: the next multi-branch close-out.

2. **GATED — the Windows CI job's coverage is unproven until its first run.**
   `.github/workflows/lint.yml`, job `symlink-probe-windows`, passes `--require-capable`, so a
   runner that cannot create a directory symlink turns the job red with a precondition error rather
   than passing vacuously. Whether `windows-latest` *can* is not knowable from here. Gate: the first
   CI run. **Read whether it printed `oracle: directory symlink possible here = yes`** before
   describing the job as covering the regression.

3. **OPEN — the full-run context load is 45% above the monolith it replaced.** Measured
   2026-09-02T09:0xZ: old monolith 36,761 bytes; router now 8,943; a docs-only run loads 25,280
   (−31%); a full application-repo run loads **53,599 (+45%)**. The split made the partial case
   cheaper and the full case dearer, because the corpus grew by 21 findings. ~6.0 KB of genuinely
   trigger-gated material was already moved into `references/traps.md`. A further **~3 KB** is
   available by routing Step 1's triage table behind a `gate red →` pointer; that is a second split
   and was deliberately not taken. Exposure meanwhile: a full close-out costs more context than
   before, on a skill whose whole purpose is running when context is scarce.

4. **OPEN — `.claude/` is not gitignored, and it holds both worktrees.**
   `git check-ignore -v .claude/worktrees` returns nothing; `.gitignore:5` carries `.claude.json`,
   which matches a naive `^\.claude` grep and ignores no directory. So `git add -A` or `git add .`
   in this repo would stage two entire worktrees. **This was caught by a false-positive grep during
   this close-out and re-measured with `git check-ignore`** — the check that could actually fail on
   the claim. Fix shape: add `.claude/worktrees/` to `.gitignore`. Not done here: it is outside both
   specs' surfaces and no one in this run owned that file. Exposure: one careless `git add -A`.

5. **ACCEPTED, and not reproducible off this machine — `python3` is the Microsoft Store stub here.**
   `command -v python3` succeeds and points at `…/WindowsApps/python3`, which prints
   "Python nao foi encontrado" and exits 49; `python` is a real 3.12.10. Every resolver written this
   run requires the exact string `PY_OK` on stdout rather than trusting a name or an exit status.
   **A Linux box resolves `python3` on the first try and never exercises the fallback**, so this
   proof cannot be re-run elsewhere.

6. **ACCEPTED, and it is a reading — the drift count moves when branch 1 merges.**
   `check-drift.sh` currently prints exactly 5 `DIFFERS:` lines. Those five are the files that were
   ahead in `~/.claude`; branch 1 lands three of them and branch 2 lands none. Re-read the list
   before treating a changed count as a script defect.

## Two corrections this run made to its own record, kept because they are the useful part

- **The orchestrator generalised a file symlink to a directory symlink** and wrote it into a spec.
  Windows distinguishes them. Fork B measured the directory case separately and it happened to hold
  — but the reasoning was the wrong-instrument failure the skill's own fourth invariant names,
  committed by the session that had just written that invariant into the spec.
- **The orchestrator read a piped exit status twice** — once reading `tail`'s status as
  `check-drift.sh`'s and reporting exit 0 over a real EXIT 1, once with a `grep` that could not fail
  on the claim it was testing. Both caught and re-run through `gate.sh` or the right tool. This is
  the trap `gate.sh` exists to remove, hit by the session enforcing it.

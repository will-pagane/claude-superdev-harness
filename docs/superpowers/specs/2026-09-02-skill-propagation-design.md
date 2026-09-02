# Propagating the session skills from `~/.claude` to the public repo

**Date:** 2026-09-02
**Status:** design approved, ready to plan
**Repo:** `claude-setup` (published as `will-pagane/claude-superdev-harness`)
**Touches:** `install.sh`, `scripts/check-drift.sh` (new), `.github/workflows/lint.yml`, `README.md`

## Problem

`install.sh` installs the repo's skills into `~/.claude/skills/` by symlink where the system
allows it and by copy where it does not. On this machine it copies. Under copy, `~/.claude` is the
live edge — every edit is made there, against the running skill — and the repo receives those
edits only when someone remembers to carry them across. Nothing detects that they have not been.

Measured on 2026-09-02, before this work: `session-end`'s Step 4 had been rewritten that day and
existed in `~/.claude/skills/session-end/` only, committed nowhere, with no history and no backup.

**A second failure sits on top of the first: the drift is unreadable.** A byte comparison of the
23 skill files reports **23 differences**. A comparison that strips `\r` first reports **five**.
`.gitattributes` forces `eol=crlf` on `*.ps1` and `eol=lf` on `*.sh`, and Windows checkout
normalisation does the rest, so every honest attempt to answer "what has actually drifted?"
returns noise unless it normalises. This session initially concluded from that noise that the
repo was months behind. It was four commits behind.

## Root cause

`install.sh`'s `can_symlink()` probe is honest about the wrong thing. Its comment is correct —
Git Bash's `ln -s` copies and returns 0, so the only reliable reading is to write a probe symlink
and ask `test -L` what landed on disk. But Git Bash does not create a native symlink at all
unless `MSYS=winsymlinks:nativestrict` is set, and the probe does not set it.

Measured, with Windows Developer Mode confirmed on
(`HKLM:\...\AppModelUnlock\AllowDevelopmentWithoutDevLicense = 1`):

```
ln -s …                                  → not a symlink
MSYS=winsymlinks:nativestrict ln -s …    → symlink
```

So the installer concludes "this system cannot symlink" on a system that can. Enabling Developer
Mode alone changes nothing — that is exactly the state measured above.

## Decision — fix the installer, then verify the harness follows symlinks

**Primary path: symlink.** With `MSYS=winsymlinks:nativestrict` exported for both the probe and
the real `ln -sfn`, `~/.claude/skills/session-end` becomes the repo's `skills/session-end`.
Editing either edits the same file. Propagation stops being a task and becomes `git add`.

**One precondition, unverified, and it gates the whole path.** It is not yet known whether Claude
Code discovers and loads a skill whose directory is a symlink. This is the **first task of the
implementation plan**, run before anything depends on it:

1. Record the current state of `~/.claude/skills/session-end` (it is a copy; the repo holds the
   same content plus this branch's).
2. Replace it with a symlink into the repo.
3. Restart Claude Code and confirm the skill loads and its files resolve.
4. On failure, restore the copy and take the fallback below.

**Fallback: a mirroring hook.** A `PostToolUse` hook on Write/Edit under
`~/.claude/skills/{session-build,session-end}` copies the file into the repo checkout. It works
without Developer Mode. It has two honest weaknesses, stated rather than discovered: it **must**
normalise line endings on write or it will reproduce the 23-versus-5 noise, and it does not see
edits made outside Claude Code.

**Either way: a drift check that fails loudly.** `scripts/check-drift.sh` compares
`skills/**` against `~/.claude/skills/**` with `\r` stripped, prints only real differences, and
exits non-zero when any exist. Under the symlink path it is a cheap tautology that catches a
partial install; under the hook path it is the thing that catches what the hook missed. Wired into
`.github/workflows/lint.yml` it cannot run against a developer's `~/.claude`, so **in CI it runs in
repo-only mode**: it verifies that every skill directory holds the files the installer expects and
that no `*.sh` carries CRLF. The `~/.claude` comparison is the local mode, run by hand or by the
hook.

## Non-goals

- No change to what `install.sh` installs, only to how it decides between symlink and copy.
- No automatic commit. The hook and the check mirror and report; committing stays the user's.
- No attempt to make the repo the live edge by convention alone. Convention is what failed.

## Sequencing against the other spec

The sibling spec `2026-09-02-session-end-router-and-fork-lane-design.md` rewrites
`skills/session-end/**`. If `install.sh --skills` flips `~/.claude` to symlinks while that work is
in a worktree, `~/.claude/skills/session-end` resolves to the **main checkout**, not the worktree
— so the running skill would be the pre-restructure version while the branch holds the new one.
That is harmless (no self-modification), but it must be a stated ruling rather than a surprise:
**this spec's install step runs after the sibling branch has merged.** The installer and drift-check
edits themselves are independent and can proceed concurrently.

## Verification

- **The probe.** On this machine, `can_symlink()` returns true after the fix and returned false
  before it. Run both, read both.
- **The install.** After `./install.sh --skills`, `test -L ~/.claude/skills/session-end` succeeds
  and the target resolves into this repo.
- **The harness.** Claude Code restarted, `session-end` listed, its `steps/` files readable
  through the symlinked path. If this fails, the fallback is taken and the failure is recorded in
  the README rather than silently worked around.
- **The drift check.** Introduce a deliberate one-line difference and confirm a non-zero exit;
  remove it and confirm zero. A check never proven capable of failing is not a check.
- **The noise.** `check-drift.sh` reports 0 differences on a clean install, not 23.

## Risks

| Risk | Response |
|---|---|
| Claude Code does not load symlinked skill directories | Gated by task 1 with an explicit rollback; the hook fallback is fully specified. |
| A symlinked `~/.claude` means an uncommitted repo edit is live immediately | That is the point, and it is also the hazard. The README says so plainly: on the symlink path, a broken edit in the repo is a broken skill in every session. |
| `MSYS=winsymlinks:nativestrict` changes behaviour for non-Windows users | It is inert outside MSYS. Export it in the two places that need it, not globally. |
| CI cannot see `~/.claude` | Repo-only mode in CI, comparison mode locally. Stated in the script's own help output so the difference is not inferred. |

---
name: session-end
description: Use when branch work is finished and the user asks to close the session out — "/session-end", "encerra a sessão", "fecha essa branch", "vamos encerrar aqui", "abre o PR e faz o merge", "leva até o merge e limpa a branch", "finaliza e limpa o worktree". Also OFFER it (do not auto-run it) when the user signals closure without naming it — "deixa tudo pronto", "o que falta a gente fazer?", "zera esses pendings". NOT for work still in progress, NOT when the user only asked to push, and NOT for building anything new: if the invocation carries an argument that is really a build request ("pega os pendings e faz três specs"), refuse the build, hand off to /session-build, and do not do the cheap half of it anyway.
---

# Session End

Finished branch in → merged default branch, production in sync, pendings recorded, branch and worktree gone.

**Announce at start:** "Using session-end to take `<branch>` from pushed to merged and cleaned up."

**This run has two human gates** (Step 0 ambiguity, and escalations). Everything between them happens without asking. That is a gate count, not a duration promise.

## Authorization

The invocation authorizes, **for the work already on this branch only**: committing what is left, applying its migrations, deploying its edge functions, writing the pendings file, pushing, opening the PR, merging into the default branch, and deleting the branch + worktree afterwards. This is the one place where the standing "never open a PR / never merge without an explicit ask" rule is satisfied — **the invocation *is* the ask.**

**Not authorized:** new features, refactors, fixing unrelated findings, force-pushing, squashing, rewriting history, deleting anything outside the branch and its worktree.

**Also not authorized — tree-mutating recovery.** `git stash` with a merge or rebase in progress, `git reset --hard`, `git rm --cached -r .`. These destroy state you did not create. Observed: a `git stash push -u` with `MERGE_HEAD` live and six hand-resolved files staged, and a `git rm --cached -r . && git reset --hard` on a shared main checkout with no human gate. Both are escalations, not moves.

**Out-of-scope arguments: refuse and hand off — do not do the cheap part anyway.** Invoked with "take enough pendings to make three specs", the right answer is that `/session-build` owns that, and to stop. A run that refused the execution but cut the three specs regardless got the reply *"pode rodar o session build em cima"* — the specs were unwanted work in the wrong skill.

Human gates — only these:
1. **Step 0** — confirm the branch and the pendings list when either is ambiguous.
2. **Escalations** — a red gate triaged as `regression`, an unapplied migration, a **semantic** merge conflict, an unverified deploy, a mid-run instruction that contradicts project law.
3. Nothing else. Do not ask "should I continue?" between steps, and do not invent a third gate.

## Never bypass a gate — and here is what counts as one

A bypass is any of: `--no-verify`; `-n` on commit; `--force`, `-f` or `--force-with-lease` on push; `-c core.hooksPath=<anything>`; `HUSKY=0`; `SKIP_HOOKS`; `--no-gpg-sign`; **or any flag or environment variable whose effect is that a hook does not run.** The enumeration is not the rule — that last clause is. A failing hook is an escalation, not an obstacle.

**Retrying a denied command in a cleaner shape is not a bypass; reaching the same effect through a different door is.** A permission classifier is transient and shape-sensitive — the same `gh` call is denied piped and allowed bare. So **retry once, bare**: no pipe, no redirect, body via `--body-file`.

**What follows a second refusal depends on whether the project has another sanctioned route.**

- **It does** — the merge steps do: `merge_path: local-merge` is a first-class path some projects use by default. Take it, announce it, report it. That is a route change, not a bypass. **Step 6 owns this ladder; do not escalate before climbing it.**
- **It does not** — then escalate with three named options: grant the permission / the user runs the command / abandon this step and report what is left undone.

Never reach the denied effect through a tool the project does not sanction, and never reason around missing evidence: **a check that could not run is not a check that ran green.** Evidence on all sides: `references/traps.md#classifier-denials`.

## Run gates through `scripts/gate.sh`

Never `cmd | tail`, `cmd | grep`, `cmd; echo ok`. `scripts/gate.sh <label> <command...>` captures output to a file, reads `$?` from the command itself, and prints `GATE <label> EXIT <code> LOG <path> LINES <n>`. Two shell traps this removes: a pipe hands you the pipe's status, not the command's; and `grep -c` exits **1** when the count is 0, so a verification whose whole point is "zero orphan commits" reports failure at the moment it succeeds.

## Project rules win

Read the project's `CLAUDE.md` / `AGENTS.md` at Step 0 and obey it over any default here.

- **Merge strategy follows the project.** History-preserving projects merge with `--merge`; **never `--squash`** unless the project asks for it.
- **Deploy through the project's wrapper**, never a bare deploy command that skips the gate.
- **Migrations follow the project's discipline** — file-first via the migration CLI, preflight evidence where required. Use the CLI, not an MCP write tool, where the project says so: MCP tools stamp their own ledger version and desynchronise the repo from the database.
- **Generated/hook-owned files** are not committed on a branch when the project forbids it. They get regenerated after the merge (Step 8).

<!-- split-addition -->

## Entry points

| Situation | Lane |
|---|---|
| A feature branch, or the default branch with a `handoff.md` naming one branch | **inline** — Steps 0–10, `steps/step-00-inventory.md` |
| Default branch **and** `handoff.md` with `N ≥ 2` branches | **fork lane** — `steps/lane-fork-orchestrator.md` |
| Default branch with worktrees and **no** `handoff.md` | **sequential** — `steps/step-00-inventory.md`, once per branch, entering each worktree |

The fork lane **requires** `handoff.md`. Without it there is no branch list, no merge order and no project profile, and improvising those is exactly what the handoff exists to prevent.

## Loading discipline

One step file at a time, read to completion, then its named successor. Never load a later step early. Files under `references/` load **only** when their stated trigger fires — they are failure-path material.

## FIRST STEP

Route at the table above, then read fully and follow **`steps/step-00-inventory.md`**.

<!-- /split-addition -->
<!-- moved -->
## Ledger

`.superpowers/session-end/<YYYYMMDD-HHMM>/ledger.md`, first line `# session-end — branch: <name>`. Append after every step: inventory → verification output → migration state → deploy + verification method → pendings written → PR number → merge state → cleanup. Context does not survive compaction; the ledger does. On resume, trust the ledger, `git log` and the forge over recollection, and restart at the first step with no completion line.

<!-- moved -->
## Common mistakes

| Mistake | Reality |
|---|---|
| "Tests passed earlier in the session" | Re-run the full suite at Step 1. Nothing else gates the merge. |
<!-- moved -->
| "Report from memory" | Compose from the ledger. Compaction eats what you did not write down. |
<!-- moved -->
| "The command exited 0" | Did you pipe it? And `grep -c` exits 1 on a zero count, which is the answer you wanted. |
<!-- moved -->
## Red flags — stop

<!-- moved -->
- About to `--squash`, `--force`, `--no-verify`, `core.hooksPath=…`, or amend on a shared branch.
- About to `git stash`, `git reset --hard` or `git rm --cached` against state you did not create.
<!-- moved -->
- About to fix a newly-found bug instead of writing it to pendings — this skill closes work out, it does not open new work.
- About to build something because the invocation asked for it. Refuse and hand off; do not do the cheap half.

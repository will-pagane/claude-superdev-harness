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

**Retrying a denied command in a cleaner shape is not a bypass; reaching the same effect through a different door is.** A permission classifier is transient and shape-sensitive — the same `gh` call is denied piped and allowed bare. Retry **once**, bare: no pipe, no redirect, body via `--body-file`. If refused again, escalate with three named options (grant permission / the user runs it / the project's non-`gh` path). **A check that could not run is not a check that ran green.** Evidence on all sides: `references/traps.md#classifier-denials`.

## Run gates through `scripts/gate.sh`

Never `cmd | tail`, `cmd | grep`, `cmd; echo ok`. `scripts/gate.sh <label> <command...>` captures output to a file, reads `$?` from the command itself, and prints `GATE <label> EXIT <code> LOG <path> LINES <n>`. Two shell traps this removes: a pipe hands you the pipe's status, not the command's; and `grep -c` exits **1** when the count is 0, so a verification whose whole point is "zero orphan commits" reports failure at the moment it succeeds.

## Project rules win

Read the project's `CLAUDE.md` / `AGENTS.md` at Step 0 and obey it over any default here.

- **Merge strategy follows the project.** History-preserving projects merge with `--merge`; **never `--squash`** unless the project asks for it.
- **Deploy through the project's wrapper**, never a bare deploy command that skips the gate.
- **Migrations follow the project's discipline** — file-first via the migration CLI, preflight evidence where required. Use the CLI, not an MCP write tool, where the project says so: MCP tools stamp their own ledger version and desynchronise the repo from the database.
- **Generated/hook-owned files** are not committed on a branch when the project forbids it. They get regenerated after the merge (Step 8).

## Step 0 — Pre-flight inventory

Everything downstream reads from this inventory. Build it once; never re-derive it from memory.

1. **Where am I.** `git rev-parse --show-toplevel`, `git branch --show-current`, `git worktree list`.
   **Check for someone else's work in progress before entering anything:** if `.git/MERGE_HEAD` or `.git/REBASE_HEAD` exists, or `git status` shows `UU` paths, a parallel session is mid-operation in this checkout. **Stop and report.** Following this step literally in that state has come within one command of destroying another session's merge.
   If the current branch is the default one **and there is no worktree to close**, stop — there is nothing here. **Two lanes out of that stop:**
   - *Orchestrator lane.* Being on the default branch is the correct starting state for a session closing several branches. `git worktree list` shows the branches waiting; enter each (`EnterWorktree` with its path), run this skill through once per branch, return with `ExitWorktree` between them. One orchestrator did exactly this for five, in sequence, with no refusal.
   - *Docs-only lane.* If there is genuinely nothing to close but the user wants documentation landed, **branch first** per the global `CLAUDE.md` — never commit straight to the default branch — run the formatter the project's CI runs, skip the code suite **explicitly and say so**, and take the docs-only report shape at Step 10.
2. **Read the handoff if there is one.** `.superpowers/session-build/<RUN_ID>/handoff.md` names the branches, worktree paths, merge order and reasons, deploy set, migrations applied and whether their branch merged, and the project profile. **Honour its stated values verbatim where they are decisions** — merge order, ownership — **and re-measure everything that is a reading.** The handoff tells you *what* to measure; it never tells you what is true now.
3. **Classify the repo** — read `references/repo-shapes.md` if this is not a plain application repo with a test suite, migrations and deployables. It names what verification means for a docs-only, no-suite, no-migrations or CI-applies-migrations project, so those steps are *routed past* rather than improvised or run as dead weight.
4. **Resolve `merge_path` now, not at Step 6.** The project's `CLAUDE.md` decides `pr` or `local-merge`. Two runs hit the identical classifier block on `gh pr create` 36 hours apart and reached opposite outcomes; the one that halted for ~46 minutes called its own blocker fictional afterwards, because the project had always mandated local merge and the PR was only this skill's default.
5. **Base and diff.** `BASE=$(git merge-base HEAD origin/<default>)`; then `git diff --name-only $BASE...HEAD` and `git status --porcelain`. Record both.
6. **Derive from the diff:** migration files; edge/serverless function dirs — plus **every consumer** if a shared module changed, since shared code is bundled, not referenced; generated files the project forbids committing.
7. **Uncommitted work.** Untracked or modified files in the diff scope get committed at Step 5. Files clearly outside the branch's purpose are **left alone** and named in the final report — never swept into the commit.
8. **Collision check.** If the project shares one database/runtime across sessions, run its gate before applying anything.
9. **Create the ledger** (see below) and one todo per step.

**Inside a worktree, compound bash is refused**: no `cd X && …`, no redirects, no `for` loops, no `;`-joined pairs, and no `-C` aimed at a different worktree. Every command becomes simple and one per call. Nothing announces this; it changes how every step below is written, and it has cost runs dozens of refused calls — including one *during this step*. Re-read this line at Steps 1, 5, 7 and 9.

## Step 1 — Verify before anything irreversible

Run the project's full lint, typecheck, build and test suite **yourself**, through `scripts/gate.sh`, and read the actual output.

**A red gate is not automatically a stop. Triage it into exactly one lane and name the proof:**

| Lane | Proof required | Response |
|---|---|---|
| `regression` | The same gate is green on the base and the failure signature is new | **Escalate.** Never migrate, deploy or merge off it. |
| `pre-existing-on-base` | Run the same gate on the base ref and compare signatures; or byte-compare the failing files against the base | Record with evidence, report at Step 10, continue |
| `environmental` | Name the missing or stale artifact — dependencies not installed, a stale dependency tree | Repair **without touching branch content**, re-run, continue |

Without these lanes the rule is an absolute that correct behaviour has to break: one run proved eight failures pre-existing over 35 minutes and merged, correctly; another repaired a stale dependency tree and continued, correctly. Each unlaned violation teaches that this skill's absolutes are advisory.

**Scope the suite to the diff when the diff cannot reach the rest.** A markdown-only change runs the formatter the project's CI runs, not the type checker — say so explicitly in the report. This is a lane, not a shortcut: name why the skipped gate could not have gone red on this diff.

**When a failure's justification may have aged out, prove the merge resolves it without merging.** `git merge-tree --write-tree origin/<default> <branch>` computes the merged tree and mutates nothing — exit 0 plus the corrected blob in the resulting tree is proof, and it costs no branch state. Observed: a branch's last failing test was justified as "this file is byte-identical to the default branch" — true when measured, falsified when a neighbouring session merged the fix afterwards.

**A check that was blocked is not a check that passed.** If `merge-tree` (or any preflight) could not run, that is missing evidence, not permission to reason around it.

## Step 2 — Migrations

For every migration file in the inventory, confirm it is actually applied to the target database, then confirm against the remote ledger. "It was probably applied earlier in the session" is not confirmation. A migration file on the branch that is **not** in the remote ledger is a hard stop on the merge.

**Match by NAME, and let object existence outrank a ledger row.** Where a tool stamped its own version numbers, every local file reads as unapplied with the remote column blank; verifying by name found an applied migration with no file of its own at all. When the ledger and the database disagree, query the database for the objects.

**A migration that compiles is not a migration that runs.** `plpgsql` and SQL validate syntax at definition time. Smoke-execute every RPC the branch creates — one migration applied cleanly to production and failed at runtime on its first real call.

**Before believing "none of mine were applied", read `references/traps.md#pre-merge-migrations`.** That reading has come one step from undoing production.

## Step 3 — Edge functions

For every changed function in the inventory, deploy through the project's wrapper, preserving auth settings. **Verify by re-downloading and grepping for the change** — a version bump proves nothing. Run the project's drift check afterwards if it has one.

**A deploy target can be shared with another live session.** Before deploying, download the live bundle and diff it against your commit. Never redeploy merely to invert which slice is broken; where two merges are involved, deploy once from a base containing both. See `references/traps.md#shared-deploy-target`.

Note in the ledger that this deploy will likely be **undone by the merge** (Step 8 redeploys).

## Step 4 — Pendings

Collect what the session leaves behind: deferred review findings, cut scope, TODOs added to the diff, verification only a human can do, anything parked with a ruling. Sources are the session ledger and the diff — not recollection.

**When the work was built by someone else — a fork, an earlier session — ask for density explicitly, or the default answer is useless.** Left unasked, a hand-off reports *"found X, deferred"*. Use the phrasing that worked, close to verbatim:

> *"Send me the parked findings with enough density that I can transcribe them straight into the pendings file without reopening the investigation — file and line, the number you measured and how you measured it, the shape of the fix, and the exposure that stays open meanwhile."*

That request produced **13 items transcribed almost directly** in a five-branch close-out. Require one more field it does not cover: **any proof that cannot be reproduced.** An equivalence established before a migration that now makes the old path raise is not re-runnable, and an entry that does not say so sends the next reader chasing a break that is not there.

**Nothing deferred → skip this step entirely.** Do not create an empty file, do not invent filler items.

Otherwise, find the pendings file (`PENDINGS.md` at the repo root, else `docs/PENDINGS.md`, else the project's named equivalent). **If none exists, create `PENDINGS.md` at the repo root by copying [pendings-template.md](pendings-template.md) verbatim** — header plus the `---`, nothing else. That header is load-bearing: never edit it, never drop it, never write items above it.

**The file's own header outranks this skill, and that header is the spec.** `pendings-template.md` states the section shape, the entry shape, the three statuses, the 3–6 line target and the exactness rule — **read it there; it is not repeated here.** A pendings file created from an older template carries a different shape: do not convert it, do not mix formats, read its header and write what it prescribes. Language and voice always follow the file.

Two consequences of that spec worth naming, because runs get these two wrong:

- **Something genuinely resolved is deleted, never re-tagged `DONE`/`FIXED`/`CLOSED`.** The file is not a graveyard — and a resolved item left in has had to be caught by the user rather than by this step.
- **An entry with no "why it was not done" is a task you should have done, not a pending. An entry with no unblock is a wish.**

**This file is subject to the project's own formatter and CI.** Run the formatter on it before committing — one run wrote it, pushed, opened the PR and had **CI fail on it**, then watched the formatter corrupt the very sentence describing formatter corruption. Two extra commits and a CI cycle, on this skill's own output artifact.

**Write it with the Write tool, never a shell heredoc.** Multi-paragraph prose through a heredoc has failed twice on the terminator and once by leaking PowerShell quoting into a commit message, costing a `git reset --soft` and two rewritten commits.

## Step 5 — Commit and push

Commit the remaining branch work (conventional commit, project language, one per logical unit — not one per file). Then `git push -u origin <branch>`. Never force-push.

## Step 6 — Pull request

**Only if Step 0 resolved `merge_path: pr`.** If the project mandates a local merge, skip to Step 7 and say so in one line — do not halt on a `gh` classifier block for a path the project never wanted.

`gh pr create --base <default>`, title = the branch's purpose, body = the Step 10 report via `--body-file` (inline bodies correlate with classifier denials). Include the harness attribution footer if the project uses one.

## Step 7 — Merge

Hard-gated. Re-check immediately before merging: gates green or laned, every branch migration in the remote ledger, no unresolved load-bearing review finding, working tree clean.

**Conflicts with the default branch have two lanes:**

| Kind | Test | Response |
|---|---|---|
| `additive-vs-additive` | Both sides only add, at the same location, and neither removes or reinterprets the other's lines | Resolve in-pass by taking **both**. And **recompute every derived counter as a union — never pick a side's number.** |
| `semantic` | Either side changes the meaning of what the other relies on | **Escalate.** |

A run that met six additive-vs-additive conflicts resolved them by hand, correctly, against a rule that then read "no conflicts → stop; never merge anyway".

Then merge per the project's strategy (**never `--squash`** on a history-preserving repo). **Do not pass `--delete-branch`** — the worktree still has the branch checked out and the delete will fail or strand the worktree.

**`gh pr merge` prints nothing on success**, so silence is not evidence either way. Confirm with **`git branch -r --contains <sha>`**, never with `gh pr view --json state`. That query held when `gh` was refused by a classifier twice during this very step, and when the forge returned a **504 Gateway Timeout** indistinguishable from a refusal — the git query proved the merge had landed. `MERGED` — however you establish it — is the only acceptable state before Step 8.

**If you merged the default branch into your branch first, read `references/traps.md#merge-ours` before resolving anything.** The middle step of that trap looks correct and breaks the default branch.

## Step 8 — Post-merge sync

The merge changed the default branch; production usually needs a second pass.

1. **Redeploy every changed function** through the project's wrapper and re-verify by download. On hosts that redeploy in bulk on a push, the merge silently reverted the Step 3 deploy. Re-run the drift check. **Deploy is the last action after the last push.** Details and the revert-versus-your-own-bug test are in `references/traps.md#deploy-reverts`.
2. **Regenerate hook-owned generated files** on the main checkout if the schema changed, especially when the merge resolved them `ours`.
3. `git pull origin <default>` on the main checkout so it reflects the merge.
4. **Run the full suite on the merged default branch.** This is the measurement nobody else takes — every branch measured itself, none measured the combination. In one run it exposed that the main checkout had been carrying a stale dependency tree for days, meaning every suite anyone had run there was measuring the wrong tree.

## Step 9 — Cleanup

Only after Step 7 confirmed `MERGED`.

1. **Leave the worktree first.** You cannot remove the directory you are standing in — `ExitWorktree`, or `cd` to the main checkout. Skipping this is the most common failure of this step. Note that `ExitWorktree`'s removal path measures against the branch name the worktree was **created** with, so it fails after a project-mandated `git branch -m`; remove with `git worktree remove` in that case.
2. **Relocate or de-reference every gitignored artifact the pendings cite.** Review directories, execution ledgers and run transcripts living **inside** the worktree are not in git history either, so removing the worktree turns every reference to them into a dead pointer. The stranding check below sees neither.
3. Confirm nothing is stranded: `git log <branch> --not origin/<default> --oneline` returns empty, and `git -C <worktree> status --porcelain` is clean. Non-empty → **stop and report**; never delete unmerged commits or uncommitted files.
4. `git worktree remove <dir>` → **delete the remote ref** → `git branch -d <branch>` (lowercase `-d`, which refuses unmerged work).
5. Confirm: `git fetch --prune`, then `git worktree list` and `git branch -a` no longer show it.

**`git branch -d` needs BOTH preconditions: the remote ref gone, and the local default branch containing the merge.** It measures against the branch's **upstream**, not `HEAD`, so it refuses a fully-merged branch while either is missing. Never read that refusal as "use `-D`". If pulling the default branch is unsafe because a parallel session has colliding uncommitted work, **stop and report**.

**`git worktree remove` refuses a dirty tree, and Step 7 may have made it dirty on purpose** — never `--force`. `git checkout` the *generated* file only, and only because a command reproduces it. Anything else dirty: stop and report.

**A remote branch already deleted by the forge is not a failure.** If the session ran on the main checkout with no worktree, the worktree steps do not apply.

Details and the runs behind all three: `references/traps.md#cleanup`.

## Step 10 — Report

Read `assets/report-template.md` and use the variant matching how this branch actually landed. Compose from the ledger, never from memory, in the user's language. **Delete every section with nothing in it.**

**Say the shape explicitly when there is no PR and no branch to delete.** A report reading "no PR to open and no branch to delete" was read by the user as the merge having been skipped — *"mas porque voce nao mergeou?"* — and cost a whole turn proving ancestry. Two other runs improvised the same missing line.

**Re-read the pendings file after writing it**, and check whether anything that *survived* was invalidated by this session's own work. Your own diff is the most likely thing to have falsified the list you are leaving behind. See `references/traps.md#stale-survivors`.

## Ledger

`.superpowers/session-end/<YYYYMMDD-HHMM>/ledger.md`, first line `# session-end — branch: <name>`. Append after every step: inventory → verification output → migration state → deploy + verification method → pendings written → PR number → merge state → cleanup. Context does not survive compaction; the ledger does. On resume, trust the ledger, `git log` and the forge over recollection, and restart at the first step with no completion line.

## Common mistakes

| Mistake | Reality |
|---|---|
| "Tests passed earlier in the session" | Re-run the full suite at Step 1. Nothing else gates the merge. |
| "The migration went in when I wrote it" | Confirm against the remote ledger. An unapplied migration merged in breaks production. |
| "Deploy returned a new version, so it shipped" | Re-download and grep. A version bump proves nothing. |
| "I deployed at Step 3, so production is current" | The merge push can revert branch deploys. Redeploy at Step 8. |
| "`gh pr merge --delete-branch` saves a step" | The worktree holds the branch. It fails, or strands the worktree. |
| "`git worktree remove` from inside the worktree" | You cannot delete your own cwd. Exit first. |
| "`git branch -d` refuses, so I need `-D`" | `-d` compares against the **upstream**. Prove containment, delete the remote ref, make the local default current, then `-d` passes. `-D` discards silently if you were wrong. |
| "I deployed after the merge, so production is current" | Any later push to the default branch reverts it — a docs-only commit will do. Deploy last. |
| "The migration list shows none of mine, so nothing was applied" | Pre-merge migrations appear only in the **remote** column, local blank. Acting on that reading undoes production. |
| "Nothing deferred, but the file should exist" | No pendings, no file. An empty pendings file is noise. |
| "Squash keeps history tidy" | History-preserving projects lose the per-phase commits. |
| "Report from memory" | Compose from the ledger. Compaction eats what you did not write down. |
| "The gate is red, so I stop" | Triage it first. Only `regression` stops the run; the other two lanes are recorded and continued. |
| "The classifier refused, so this path is closed" | Retry once, bare. A denial is transient and shape-sensitive. Then escalate — do not route around it. |
| "The command exited 0" | Did you pipe it? And `grep -c` exits 1 on a zero count, which is the answer you wanted. |
| "I closed those pendings, nothing to report" | Closed items are the invisible half. Report them; the user has no other way to know. |

## Red flags — stop

- About to act in a checkout where `.git/MERGE_HEAD` or `REBASE_HEAD` exists, or `git status` shows `UU`.
- About to merge with a `regression`-laned gate, or with a branch migration missing from the remote ledger.
- About to `--squash`, `--force`, `--no-verify`, `core.hooksPath=…`, or amend on a shared branch.
- About to `git stash`, `git reset --hard` or `git rm --cached` against state you did not create.
- About to `git branch -D` or `git worktree remove --force` with unmerged commits or a dirty tree.
- About to delete the branch before the merge was confirmed with `git branch -r --contains`.
- About to edit or drop the pendings file's header.
- About to sweep unrelated working-tree files into the branch commit.
- About to remove a worktree holding gitignored artifacts the pendings still cite.
- About to fix a newly-found bug instead of writing it to pendings — this skill closes work out, it does not open new work.
- About to build something because the invocation asked for it. Refuse and hand off; do not do the cheap half.

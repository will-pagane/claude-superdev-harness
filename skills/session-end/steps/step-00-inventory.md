# Step 0 — Pre-flight inventory

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

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

<!-- split-addition -->

## Red flags — stop

<!-- /split-addition -->
<!-- moved -->
- About to act in a checkout where `.git/MERGE_HEAD` or `REBASE_HEAD` exists, or `git status` shows `UU`.

## NEXT

`step-01-verify.md`

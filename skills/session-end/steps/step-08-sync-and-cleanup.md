# Step 8 and 9 — Post-merge sync and cleanup

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 8 — Post-merge sync

The merge changed the default branch; production usually needs a second pass.

1. **Redeploy every changed function** through the project's wrapper and re-verify by download. On hosts that redeploy in bulk on a push, the merge silently reverted the Step 3 deploy. Re-run the drift check. **Deploy is the last action after the last push.** Details and the revert-versus-your-own-bug test are in `references/traps.md#deploy-reverts`.
2. **Regenerate hook-owned generated files** on the main checkout if the schema changed, especially when the merge resolved them `ours`.
3. `git pull origin <default>` on the main checkout so it reflects the merge.
4. **Run the full suite on the merged default branch.** This is the measurement nobody else takes — every branch measured itself, none measured the combination. In one run it exposed that the main checkout had been carrying a stale dependency tree for days, meaning every suite anyone had run there was measuring the wrong tree.

<!-- moved -->
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

## Production is not "up", it is "running what we merged"

**Verify production serves the **merged SHA, by identifier** — the deployment id, the image version, the commit the host reports — not that a health endpoint answers 200.

Measured: a post-merge deploy failed, its cause was fixed, and the host redeployed **the old image** on its own. Production was healthy and still not running the merged code. *"It is up and green"* and *"it is running the code we merged"* are different claims, and only the second was the goal. The run caught it, re-ran the failed job, and confirmed the new version by id.

## Three cleanup facts the runs paid for

**`git branch -d` has two predicates, not one.** It measures against the branch's **upstream** *and* against the **HEAD of the checkout you run it in**. Different runs hit each half, and neither refusal means "use `-D`":

- Upstream behind → prove containment with `git log <branch> --not origin/<default>` empty, **delete the remote ref first**, then `-d` succeeds on its own.
- The shared checkout's HEAD is a peer's branch and cannot be moved → create `git worktree add --no-checkout --detach <merge-sha>` and run `-d` from there. **The deletion succeeding there is itself the containment proof.** A `--no-checkout` tree only *looks* dirty, so removing it afterwards needs no `--force`.

**`-D` keeps its prohibition, with exactly one escape.** A branch whose commit is not an ancestor of the default branch but whose **tree is identical** — `git diff origin/<default> <branch>` empty — carries no content to lose. Record that tree-level proof, per file, in the ledger. Never `-D` on age, on a hunch, or to clear a refusal you have not diagnosed.

**`git worktree remove` fails for reasons that are not git refusals.** `Permission denied`, `Directory not empty`, `Filename too long` — on Windows these are filesystem path limits over deep dependency trees, and `git worktree list` will show the worktree **already deregistered**. Confirm that, run `git worktree prune`, then remove the directory.

**And confirm removal by listing, not by the exit code.** One run's background `rm -rf` **exited 0 while leaving the directory in place**, and it was caught by listing the directory. That run then left a lock-held cache tree alone on purpose — gitignored, regenerable, and *"killing processes blind to remove cosmetic residue is a worse trade."*

**Partial cleanup is a legitimate terminal state.** If the default branch cannot be made current safely — a peer holds it, or pulling would collide with their uncommitted work — stop, leave the branch, and report. To resume: confirm the peer released it, `git checkout <default>` and `git pull`, prove containment with `git merge-base --is-ancestor <sha> HEAD`, then delete the remote ref and the local branch. One run closed exactly this way, a turn later. It is not a failure and it is never a reason to force anything.

<!-- split-addition -->

## Common mistakes

| Mistake | Reality |
|---|---|
<!-- /split-addition -->
<!-- moved -->
| "`gh pr merge --delete-branch` saves a step" | The worktree holds the branch. It fails, or strands the worktree. |
| "`git worktree remove` from inside the worktree" | You cannot delete your own cwd. Exit first. |
| "`git branch -d` refuses, so I need `-D`" | `-d` compares against the **upstream**. Prove containment, delete the remote ref, make the local default current, then `-d` passes. `-D` discards silently if you were wrong. |
<!-- split-addition -->

## Red flags — stop

<!-- /split-addition -->
<!-- moved -->
- About to `git branch -D` or `git worktree remove --force` with unmerged commits or a dirty tree.
- About to delete the branch before the merge was confirmed with `git branch -r --contains`.
<!-- moved -->
- About to remove a worktree holding gitignored artifacts the pendings still cite.

## NEXT

`step-10-report.md`

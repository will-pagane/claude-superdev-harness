# Step 7 — Merge

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 7 — Merge

Hard-gated. Re-check immediately before merging: gates green or laned, every branch migration in the remote ledger, no unresolved load-bearing review finding, working tree clean.

**Conflicts with the default branch have two lanes:**

| Kind | Test | Response |
|---|---|---|
| `additive-vs-additive` | Three conditions, all required: (a) both sides only add and neither removes or reinterprets the other's lines; (b) **the added identifiers are provably disjoint** — no duplicated key, route, migration version, enum member or config field; (c) **order does not change meaning**. Then run the affected parser, linter or gate **on the union** and see it pass. | Resolve in-pass by taking **both**, and **recompute every derived counter as a union — never pick a side's number.** |
| `semantic` | Either side changes the meaning of what the other relies on | **Escalate.** |

A run that met six additive-vs-additive conflicts resolved them by hand, correctly, against a rule that then read "no conflicts → stop; never merge anyway". **Text that merely looks additive is not enough**: two pure insertions can still collide on a duplicate key, a repeated migration version or two routes claiming one path. If any of the three conditions is unproven, it is `semantic`.

Then merge per the project's strategy (**never `--squash`** on a history-preserving repo). **Do not pass `--delete-branch`** — the worktree still has the branch checked out and the delete will fail or strand the worktree.

### Local merge — the `merge_path: local-merge` default, and Step 6's fallback

The same lane serves both: a project whose `CLAUDE.md` forbids autonomous pull requests, and a `pr` project whose `gh` call the classifier refused twice.

1. Leave the worktree if you are in one (`ExitWorktree`, or `cd` to the main checkout).
2. `git checkout <default>` then `git pull origin <default>` — **and if that pull is unsafe** because a parallel session has colliding uncommitted work in the shared checkout, stop and report. Do not merge onto a stale or dirty default branch.
3. `git merge --no-ff <branch>` — `--no-ff` deliberately, so the branch keeps a merge commit and history stays readable. Never `--squash` on a history-preserving repo.
4. Re-run the project's gates on the merged result through `scripts/gate.sh`. **This is the measurement nobody else takes**: the branch measured itself and the default branch measured itself, and neither measured the combination.
5. `git push origin <default>`.
6. Confirm with **`git branch -r --contains <sha>`**, exactly as the PR path does. The confirmation is identical because it never depended on `gh`.

Then say in the report which lane ran and why — Step 10's Variant B exists for this and names the reason as a required field, because a report that simply omits the PR reads as a merge that did not happen.

**`gh pr merge` prints nothing on success**, so silence is not evidence either way. Confirm with **`git branch -r --contains <sha>`**, never with `gh pr view --json state`. That query held when `gh` was refused by a classifier twice during this very step, and when the forge returned a **504 Gateway Timeout** indistinguishable from a refusal — the git query proved the merge had landed. `MERGED` — however you establish it — is the only acceptable state before Step 8.

**If you merged the default branch into your branch first, read `references/traps.md#merge-ours` before resolving anything.** The middle step of that trap looks correct and breaks the default branch.

<!-- split-addition -->

## Common mistakes

| Mistake | Reality |
|---|---|
<!-- /split-addition -->
<!-- moved -->
| "Squash keeps history tidy" | History-preserving projects lose the per-phase commits. |
<!-- split-addition -->

## Red flags — stop

<!-- /split-addition -->
<!-- moved -->
- About to merge with a `regression`-laned gate, or with a branch migration missing from the remote ledger.

## NEXT

`step-08-sync-and-cleanup.md`

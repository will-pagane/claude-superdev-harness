# Step 10 — Report

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 10 — Report

Read `assets/report-template.md` and use the variant matching how this branch actually landed. Compose from the ledger, never from memory, in the user's language. **Delete every section with nothing in it.**

**Say the shape explicitly when there is no PR and no branch to delete.** A report reading "no PR to open and no branch to delete" was read by the user as the merge having been skipped — *"mas porque voce nao mergeou?"* — and cost a whole turn proving ancestry. Two other runs improvised the same missing line.

**Re-read the pendings file after writing it.** Step 4's Half A is where the reconciliation happens; this is the check that it actually ran — every entry your diff touches should now be deleted, rewritten or deliberately left, and none should still describe a world your branch ended. See `references/traps.md#stale-survivors`.


## NEXT

Terminal. The branch is merged, production is in sync and the worktree is gone.

# Step 2 and 3 — Production state

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 2 — Migrations

For every migration file in the inventory, confirm it is actually applied to the target database, then confirm against the remote ledger. "It was probably applied earlier in the session" is not confirmation. A migration file on the branch that is **not** in the remote ledger is a hard stop on the merge.

**Match by NAME, and let object existence outrank a ledger row.** Where a tool stamped its own version numbers, every local file reads as unapplied with the remote column blank; verifying by name found an applied migration with no file of its own at all. When the ledger and the database disagree, query the database for the objects.

**A migration that compiles is not a migration that runs.** `plpgsql` and SQL validate syntax at definition time. Smoke-execute every RPC the branch creates — one migration applied cleanly to production and failed at runtime on its first real call.

**Before believing "none of mine were applied", read `references/traps.md#pre-merge-migrations`.** That reading has come one step from undoing production.

<!-- moved -->
## Step 3 — Edge functions

For every changed function in the inventory, deploy through the project's wrapper, preserving auth settings. **Verify by re-downloading and grepping for the change** — a version bump proves nothing. Run the project's drift check afterwards if it has one.

**A deploy target can be shared with another live session.** Before deploying, download the live bundle and diff it against your commit. Never redeploy merely to invert which slice is broken; where two merges are involved, deploy once from a base containing both. See `references/traps.md#shared-deploy-target`.

Note in the ledger that this deploy will likely be **undone by the merge** (Step 8 redeploys).

<!-- split-addition -->

## Common mistakes

| Mistake | Reality |
|---|---|
<!-- /split-addition -->
<!-- moved -->
| "The migration went in when I wrote it" | Confirm against the remote ledger. An unapplied migration merged in breaks production. |
| "Deploy returned a new version, so it shipped" | Re-download and grep. A version bump proves nothing. |
| "I deployed at Step 3, so production is current" | The merge push can revert branch deploys. Redeploy at Step 8. |
<!-- moved -->
| "I deployed after the merge, so production is current" | Any later push to the default branch reverts it — a docs-only commit will do. Deploy last. |
| "The migration list shows none of mine, so nothing was applied" | Pre-merge migrations appear only in the **remote** column, local blank. Acting on that reading undoes production. |

## NEXT

`step-04-pendings.md`

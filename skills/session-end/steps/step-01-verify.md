# Step 1 — Verify before anything irreversible

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 1 — Verify before anything irreversible

Run the project's full lint, typecheck, build and test suite **yourself**, through `scripts/gate.sh`, and read the actual output.

**A red gate is not automatically a stop. Triage it into exactly one lane and name the proof:**

| Lane | Proof required | Response |
|---|---|---|
| `regression` | The same gate is green on the base and the failure signature is new | **Escalate.** Never migrate, deploy or merge off it. |
| `pre-existing-on-base` | **Reproduce the same normalised failure on a clean checkout of the base ref.** Byte-comparing the failing file against base is *not* proof on its own — an unchanged test can fail from a changed caller, config, schema or generated input; it is admissible only alongside a stated argument that nothing in your diff reaches that file. | Record with the reproduction, report at Step 10, continue |
| `environmental` | Name the missing or stale artifact — dependencies not installed, a stale dependency tree | Repair **without touching branch content**, then re-run. **Continue only if the identical gate now returns green**; if the failure survives the repair it was never environmental — re-triage it. |

Without these lanes the rule is an absolute that correct behaviour has to break: one run proved eight failures pre-existing over 35 minutes and merged, correctly; another repaired a stale dependency tree and continued, correctly. Each unlaned violation teaches that this skill's absolutes are advisory.

**Scope the suite to the diff when the diff cannot reach the rest.** A markdown-only change runs the formatter the project's CI runs, not the type checker — say so explicitly in the report. This is a lane, not a shortcut: name why the skipped gate could not have gone red on this diff.

**When a failure's justification may have aged out, prove the merge resolves it without merging.** `git merge-tree --write-tree origin/<default> <branch>` computes the merged tree and mutates nothing — exit 0 plus the corrected blob in the resulting tree is proof, and it costs no branch state. Observed: a branch's last failing test was justified as "this file is byte-identical to the default branch" — true when measured, falsified when a neighbouring session merged the fix afterwards.

**A check that was blocked is not a check that passed.** If `merge-tree` (or any preflight) could not run, that is missing evidence, not permission to reason around it.

<!-- split-addition -->

## Common mistakes

| Mistake | Reality |
|---|---|
<!-- /split-addition -->
<!-- moved -->
| "The gate is red, so I stop" | Triage it first. Only `regression` stops the run; the other two lanes are recorded and continued. |

## NEXT

`step-02-production-state.md`

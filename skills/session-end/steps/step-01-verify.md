# Step 1 — Verify before anything irreversible

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 1 — Verify before anything irreversible

Run the project's full lint, typecheck, build and test suite **yourself**, through `<skill-dir>/scripts/gate.sh`, and read the actual output.

**A red gate is not automatically a stop. Triage it into exactly one lane and name the proof.** A lane is defined by **the proof it demands**, not by its name — a run that cannot produce the proof falls back to `regression`, which stops the merge, so the failure mode is conservative by construction.

| Lane | Proof required | Response |
|---|---|---|
| `incomplete` | `gate.sh` reported **`UNDECIDED`** — the log carries no summary line from the runner itself | **Not a red, and not a green.** Re-run scoped, split or in the background. Never merge off it and never report it as a failure. |
| `regression` | The same gate is green on the base and the failure signature is new | **Escalate.** Never migrate, deploy or merge off it. |
| `pre-existing-on-base` | **Reproduce the same normalised failure on a clean checkout of the base ref.** Byte-comparing the failing file against base is *not* proof on its own — an unchanged test can fail from a changed caller, config, schema or generated input; it is admissible only alongside a stated argument that nothing in your diff reaches that file. | Record with the reproduction, report at Step 10, continue |
| `flaky-under-load` | **All three, not two:** green in isolation, green on a clean checkout of the base, and green on an identical re-run. Fewer than three is a different lane. | Record all three readings, continue |
| `foreign-dirty-tree` | `git show HEAD:<path>` proves the committed file is clean and the red comes from a **peer's uncommitted state** in a shared checkout | **Touch nothing.** Report it. It is not yours to fix and not yours to triage further. |
| `environmental` | Name the missing or stale artifact — dependencies not installed, a stale dependency tree. **Sub-case `missing-artifact`:** a gate run before the one that generates its input, such as a type check ahead of the build that writes the types it reads. That is a *gate order* problem, not an installation one, and the project profile's `gate_order` is the fix. | Repair **without touching branch content**, then re-run. **Continue only if the identical gate now returns green**; if the failure survives the repair it was never environmental — re-triage it. |

**`incomplete` is the lane runs did not have and most needed.** Seven of twenty observed close-outs met a gate that was killed — by a tool timeout, by the harness, by memory pressure — and `EXIT 1` is exactly what a real red looks like. Two triaged the corpse as a failing test. One run put it in the words this lane exists to preserve: *a gate that did not finish did not decide.* Name a fragment of the runner's own summary line in `gate_order` and let the flag decide:

```
<skill-dir>/scripts/gate.sh --expect 'Test Files' test npm test
```

Pick a fragment a **complete** run always prints and a killed run never reaches. One that also appears in ordinary progress output is worthless: it will match a corpse.

**A cached green is not a green.** Where the project uses a build cache — turbo, nx, bazel — run the Step 1 gates with the cache disabled and record the cache-miss evidence. A cached exit code is a recording of an older tree. One run re-ran every gate with `--force` and recorded `Cached: 0` beside each.

**Report what the suite did not run.** `344 passed, 13 deselected` overstates coverage until the deselection is named, and one run said so about its own output rather than quoting the headline number.

Without these lanes the rule is an absolute that correct behaviour has to break: one run proved eight failures pre-existing over 35 minutes and merged, correctly; another repaired a stale dependency tree and continued, correctly. Each unlaned violation teaches that this skill's absolutes are advisory.

**Scope the suite to the diff when the diff cannot reach the rest.** A markdown-only change runs the formatter the project's CI runs, not the type checker — say so explicitly in the report. This is a lane, not a shortcut: name why the skipped gate could not have gone red on this diff.

**When a failure's justification may have aged out, prove the merge resolves it without merging.** `git merge-tree --write-tree origin/<default> <branch>` computes the merged tree and mutates nothing — exit 0 plus the corrected blob in the resulting tree is proof, and it costs no branch state. Observed: a branch's last failing test was justified as "this file is byte-identical to the default branch" — true when measured, falsified when a neighbouring session merged the fix afterwards.

**A check that was blocked is not a check that passed.** If `merge-tree` (or any preflight) could not run, that is missing evidence, not permission to reason around it.

## Verify the tree that will land, not the branch tip

The branch tip is not what merges. **Gate the merged tree.** *How* you obtain that tree is a second, separate decision, and conflating the two is what produced the wrong rule the first time this was written.

**Default, and always available: compute it without materialising it.**

```
git merge-tree --write-tree origin/<default> <branch>
```

It computes the merged tree, mutates nothing, costs no branch state and pollutes no pull-request diff. Step 1 already recommends it for the neighbouring question of whether an aged-out justification still holds; it is the same instrument.

**Materialise the merge on the branch only when something downstream must re-run against the new base.** Two cases, both observed:

- **CI whose green would otherwise answer the wrong question.** MCPlace `20260822-2020` merged `origin/main` into a branch on a **`pr`** project and pushed, deliberately: the pull request's CI had started *before* a sibling merged, so it had validated against a base with no drift guard. The run refused that green as evidence — *"a check that is structurally incapable of failing on the thing it is being cited for"* — merged the current default branch in, and re-ran. Merging was the correct fix, and a flat rule of "never materialise on a `pr` project" would have forbidden it.
- **A correctness proof that only holds on the merged tree**, where computing the tree is not enough because something has to execute against it.

**Say which of the two ran, and why, in the report.** A verification whose subject is unstated is a verification of something.

One run went further still and made the merged default branch the **decisive** run rather than an extra one. It went red, and the red was real: the main checkout had been carrying a stale dependency tree for days, so every suite anyone had run there was measuring the wrong tree.

**Under the fork lane a fork materialises nothing on its own**, because a fork performs no merge it was not ordered to perform. The orchestrator issues `MERGE origin/<default> BEFORE verify` alongside `GO <slug> verify <branch>`, having just re-fetched, so it names the SHA — and it issues that directive only in the two cases above. Otherwise the fork computes.

<!-- split-addition -->

## Common mistakes

| Mistake | Reality |
|---|---|
<!-- /split-addition -->
<!-- moved -->
| "The gate is red, so I stop" | Triage it first. Only `regression` stops the run; the other two lanes are recorded and continued. |

## NEXT

`step-02-production-state.md`

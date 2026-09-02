# Step 4 — Pendings

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 4 — Pendings: RECONCILE first, then collect

**This step has two halves and the first one is the one runs skip.** Collecting what the branch leaves behind is the obvious half. Closing what the branch just *resolved* is the half that decides whether the file is worth reading next month — and it is skipped so reliably that users have had to ask *"esse defeito já foi registrado no pendings?"* about work the run had finished hours earlier.

**Half A — reconcile the existing file against your own diff. This half runs on EVERY invocation, including one that defers nothing.** The most likely thing to have falsified an entry in that file is the branch you are about to merge.

It is mechanical, so do it mechanically rather than from memory:

1. Read the pendings file in full. It is the input to this step, not just its output.
2. Take the identifiers your branch actually touched — file paths from `git diff --name-only $BASE...HEAD`, plus function, RPC, table, migration, function-slug and cron-job names from the diff — and grep the pendings file for each one.
3. **If the run consumed a spec derived from pendings entries, close those by NAME, not by inference.** `/session-build` records them (`PENDINGS-SOURCE` in its ledger and handoff); a run started straight from the file should have recorded them at Step 0.
4. Rule every hit into exactly one lane, and **report the count of each in the report, including zero** — a reconciliation with no residual bucket cannot tell you it missed something:

| Lane | What it means | Response |
|---|---|---|
| `resolved` | The branch did the thing the entry asked for | **Delete the entry.** Not re-tagged, not annotated — deleted. Report it under *Pendências fechadas*. |
| `stale-cause` | The entry's *stated cause or unblock* is no longer true, but the defect survives for a different reason | **Rewrite it** with the measured cause, today's number, and the real unblock. Say plainly that the previous text was wrong. |
| `moved` | Still true, but its numbers, file paths or branch-state claims aged | **Update those fields in place.** Do not leave "not pushed, not deployed" on a branch that merged an hour ago. |
| `untouched` | Your diff does not reach it | Leave it exactly as it is. |

**`stale-cause` is the lane worth naming separately, because it is worse than a missing entry and it looks like a healthy one.** Observed: an entry said a handler was unreachable *because a file did not exist*. The run created that file, deployed it and drained the queue — and the handler was still unregistered, for an unrelated reason. Every unblock the entry named had happened, so the next reader would have ticked it off and the live defect would have vanished from the file. An entry whose stated cure has been administered, while the disease survives, is a trap the file itself sets.

**Do not resolve an entry from the fact that you did the work — resolve it from a measurement.** "I redeployed the worker" is not "the rows drained"; query the thing the entry is about. Half of what makes this step worth running is that the measurement is available now, on merged code, and will not be later.

**Half B — collect what this branch leaves behind:** deferred review findings, cut scope, TODOs added to the diff, verification only a human can do, anything parked with a ruling. Sources are the session ledger and the diff — not recollection. **Nothing deferred → skip Half B only.** Half A still runs.

**When the work was built by someone else — a fork, an earlier session — ask for density explicitly, or the default answer is useless.** Left unasked, a hand-off reports *"found X, deferred"*. Use the phrasing that worked, close to verbatim:

> *"Send me the parked findings with enough density that I can transcribe them straight into the pendings file without reopening the investigation — file and line, the number you measured and how you measured it, the shape of the fix, and the exposure that stays open meanwhile."*

That request produced **13 items transcribed almost directly** in a five-branch close-out. Require one more field it does not cover: **any proof that cannot be reproduced.** An equivalence established before a migration that now makes the old path raise is not re-runnable, and an entry that does not say so sends the next reader chasing a break that is not there.

Do not create an empty pendings file and do not invent filler items to justify one.

Otherwise, find the pendings file (`PENDINGS.md` at the repo root, else `docs/PENDINGS.md`, else the project's named equivalent). **If none exists, create `PENDINGS.md` at the repo root by copying [pendings-template.md](pendings-template.md) verbatim** — header plus the `---`, nothing else. That header is load-bearing: never edit it, never drop it, never write items above it.

**The file's own header outranks this skill, and that header is the spec.** `pendings-template.md` states the section shape, the entry shape, the three statuses, the 3–6 line target and the exactness rule — **read it there; it is not repeated here.** A pendings file created from an older template carries a different shape: do not convert it, do not mix formats, read its header and write what it prescribes. Language and voice always follow the file.

Two consequences of that spec worth naming, because runs get these two wrong:

- **Something genuinely resolved is deleted, never re-tagged `DONE`/`FIXED`/`CLOSED`.** The file is not a graveyard — and a resolved item left in has had to be caught by the user rather than by this step.
- **An entry with no "why it was not done" is a task you should have done, not a pending. An entry with no unblock is a wish.**

**This file is subject to the project's own formatter and CI.** Run the formatter on it before committing — one run wrote it, pushed, opened the PR and had **CI fail on it**, then watched the formatter corrupt the very sentence describing formatter corruption. Two extra commits and a CI cycle, on this skill's own output artifact.

**Write it with the Write tool, never a shell heredoc.** Multi-paragraph prose through a heredoc has failed twice on the terminator and once by leaking PowerShell quoting into a commit message, costing a `git reset --soft` and two rewritten commits.

<!-- split-addition -->

## Common mistakes

| Mistake | Reality |
|---|---|
<!-- /split-addition -->
<!-- moved -->
| "Nothing deferred, but the file should exist" | No pendings, no file. An empty pendings file is noise. |
<!-- moved -->
| "I closed those pendings, nothing to report" | Closed items are the invisible half. Report them; the user has no other way to know. |
| "Nothing was deferred, so Step 4 does not apply" | Half A always runs. A branch that defers nothing can still have **resolved** three entries and falsified two more. |
| "The entry's unblock happened, so it is resolved" | That is `stale-cause`, not `resolved`, until you measure the thing the entry is about. An entry whose stated cure was administered while the defect survives is the trap the file sets for the next reader. |
<!-- split-addition -->

## Red flags — stop

<!-- /split-addition -->
<!-- moved -->
- About to edit or drop the pendings file's header.
- About to write new pendings without having reconciled the existing ones against your own diff (Step 4, Half A).

## NEXT

`step-05-push-and-pr.md`

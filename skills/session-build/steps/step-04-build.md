# Step 4 — Build

**Invariants recap** (full text in `../SKILL.md`): no PR, no delivery merge (the ONE exception is a peer-branch integration merge an orchestrator ordered by name), no branch/worktree deletion, no tree-mutating recovery. Five human gates only — never ask "should I continue?". A bypass is *any* flag or env var whose effect is that a hook does not run. Every measurement is a reading. Gates run through `../scripts/gate.sh`. One step file at a time.

**If you are a fork, read `../references/fork-contract.md` first.** This file is the work; that file is who you are.

The plan is the unit of work. Whoever writes it — inline or in a fork — obeys this.

## 4.1 The plan

- Written with `superpowers:writing-plans`, saved to `docs/superpowers/plans/YYYY-MM-DD-<spec-slug>.md`. **Never** a repo-root `PLAN.md` — concurrent sessions collide there.
- **Migrations and deploys are explicit tasks in the plan**, each with its own verification: apply the migration and confirm it against the remote ledger; deploy through the project's wrapper and verify by re-downloading and grepping for the change. A version bump proves nothing. A shared module changing means every consumer redeploys.
- **Order them as late as the plan allows.** Git is disposable; the database is not. A branch can be abandoned after a failure — the migration it already applied cannot, and there is one shared database with no staging behind it. So a migration task sits after the code that depends on it is written and verified, never as an opening move, and a migration that would break the currently-deployed code if its branch never merges is a design the plan must avoid, not a risk it may take. Any migration applied on a branch later abandoned is reported to the user by name at step-06.
- **Every Definition of Done must be checkable in this repo.** Check what actually triggers the project's CI before writing a CI-shaped DoD. Observed: an orchestrator ruled "CI validate job green on the pushed branch" for a workflow that triggers only on push-to-main and PR-to-main — and this skill opens no PRs. Its own verdict: a DoD no fork could ever satisfy. It had to invent a calibrated local instrument mid-run.
- **A fact the spec asserts is not evidence.** Any plan step encoding a fact about the existing system — a column's nullability, an external contract, what a CLI does — reads that fact **from the system** before shipping. A whole review loop can pass over a wrong one, because everyone downstream quotes the same upstream sentence; the database is what finally disagrees, in production.

## 4.2 Codex review

Hardened through the `codex-review` adversarial loop, invoked with **`rounds=until-approved`**, to `VERDICT: APPROVED`. **There is no cap and no deadlock exit in this skill.** The default 5-round cap ends in a human tie-break, which parks the whole fan-out on someone who may be asleep — and two of three forks in one run reached APPROVED only at round 6. The loop runs as long as it takes, resuming the same Codex thread every round, and never pauses to ask permission to continue.

**Runner hygiene** (the details live in `codex-review`; these are the ones that cost this skill whole rounds): run it in the background, close stdin, and **confirm the event stream is non-empty before waiting on it**. Then sanity-check that Codex actually read the plan before counting the round — a verdict returned by a runner whose first command died on shell quoting is a round wasted, not a round.

**The critical wiring:** codex-review works inside its own `$RUN_DIR/PLAN.md`. When the loop converges the hardened plan **must be copied back over** `docs/superpowers/plans/<...>.md`, because implementation reads only that path. Verify the file's content actually changed before implementing.

> **NO GATE HERE.** Codex returned APPROVED and the plan is copied back. Dispatch implementation in this same turn. Do not ask the user whether to proceed — this transition has stalled runs before, with the rule forbidding it in context verbatim.

## 4.3 Implement

**By whom, and how, depends on who owns the branch:**

- **`N = 1`, this session builds:** run `superpowers:subagent-driven-development` to completion. The main session can spawn implementer subagents, so use them. This is not optional — a run that implemented inline instead had the user name the mechanism for it, and loaded SDD fifty minutes into the implementation phase.
- **`N ≥ 2`, a fork builds:** **implement inline. SDD is not merely discouraged for a fork — it is unavailable, and no directive can enable it.** A fork's boilerplate carries `"Do NOT spawn subagents with the Agent tool"` as a hard, non-overridable rule, so SDD's fan-out cannot run there no matter what the directive says. The fork works the plan **directly, one task at a time, with verification per task and nothing marked done without reading real output** — SDD's discipline, minus its parallelism. Budget for it: this is the slowest part of an `N ≥ 2` run.

**In both cases, override SDD's ending:** it finishes by calling `superpowers:finishing-a-development-branch`. Do **not** run it — it opens PRs and merges, which this skill forbids. Verification plus push replaces it.

**Review each task before advancing to the next.** A per-task review caught a live privilege escalation that every task test had passed — two `SECURITY DEFINER` apply-functions executable by any authenticated user. Task tests answer "does it do what the task said"; the review answers "and what else does it now allow".

## 4.4 Migrations

- File-first via the project's migration CLI, with the required preflight evidence on any redefinition, committed with the code that needs it.
- **Re-stamp the filename to the current UTC timestamp immediately before applying.** Tools name the file at *creation*; a fork that scaffolds its migration and then queues behind the migration lock will, by the time its `GO` arrives, hold a file older than the remote ledger's newest entry, because a peer applied in between. The push then demands the "apply everything pending" flag — the one that is forbidden because it would sweep up someone else's work. This hits **every fork except the first in the queue**. Read UTC, not the local clock.
- **Expect the migration tool to refuse because of *other people's* migrations, and never take its suggested way out.** Where concurrent sessions apply from unmerged branches, a remote ledger holding entries with no local file is the **normal** state. The remedies such tools suggest are destructive — marking someone else's applied migration as reverted, or pulling their in-flight schema down as if it were yours. Do neither. The borrow-and-restore recipe that works, and the fact that it belongs at the top of the **apply** sequence rather than the push sequence, are in `../references/fork-contract.md` — put them in the dispatch prompt, because discovering the ordering live costs a fork a blocked task and an escalation.
- **Never carry a derived count forward — re-derive it at the moment of use.** Observed: the number of remote migrations without a local file went 9 → 13 → 14 → 15 → 16 within hours, because peers kept applying.
- **Match the ledger by name, not by version, and let object existence outrank a ledger row.** A tool that stamps its own version numbers leaves every local file reading as unapplied with the remote column blank; verifying by name found an applied migration with no file of its own at all. When the ledger and the database disagree, query the database for the objects.
- **A function that compiles is not a function that runs.** `plpgsql` and SQL validate syntax at definition time; execution is the real test. Smoke-execute every RPC you create before calling the task done — one migration applied cleanly to production and failed at runtime on the first call.

**Generated and hook-owned files are not committed on a branch when the project forbids it.** Check before staging; a hook that regenerates a file on commit will happily produce a diff that is not yours.

## 4.5 Deploy

Deploy through the project's wrapper, never a bare deploy command that skips the gate. **Deploy is the last action after the last push** — otherwise a later docs commit sends you round the deploy cycle again.

**A version bump proves nothing: re-download the deployed artifact and grep it.** This is the highest-value single rule in the family and it has fired repeatedly. Once it surfaced a cross-session clobber that no gate, test or version number could have shown — the live bundle carried none of the branch's handlers and plenty of another branch's. Before deploying a target another live session may also own, download the current bundle and diff it against your commit; never redeploy merely to invert which slice is broken; and where two merges are involved, deploy once from a base containing both.

## 4.6 Verify, triage, push

Run the project's **full** lint, typecheck, build and test suite through `../scripts/gate.sh`, and read the actual output — a subagent's report does not count. Then `git push -u origin <branch>`. Never force-push.

**A red gate is not automatically an escalation. Triage it into exactly one of three lanes, and name the proof:**

| Lane | Proof required | Response |
|---|---|---|
| `regression` | The same gate is green on the merge base, and the failure signature is new | **Escalate.** This is human gate 3. |
| `pre-existing-on-base` | **Reproduce the same normalised failure on a clean checkout of the base ref.** Nothing weaker counts — byte-comparing the failing file against base is *not* proof, because an unchanged test can fail from a changed caller, config, schema or generated input. Byte comparison is admissible only alongside a stated argument that nothing in your diff can reach that file. | Record in the ledger with the reproduction, report at close-out, continue |
| `environmental` | Name the missing or stale artifact — dependencies not installed, a stale dependency tree, a container holding another branch's state | Repair **without touching branch content**, then re-run. **Continue only if the identical gate now returns green**; if the same failure survives the repair, it was never environmental — re-triage it. |

Only `regression` stops the run. Without these lanes the rule reads as an absolute, the correct action requires violating it, and every correct violation teaches that this skill's absolutes are advisory.

**Scope verification to the change, then gate the branch on the full suite.** Per-task verification runs what the task can break; the branch-level gate before push runs everything. As a suite grows this distinction stops being an optimisation — a suite of a few thousand tests taking tens of minutes, run three times in one close-out, is most of the wall clock of the run.

**Match the gate's invocation to how the hook invokes it, in both directions.** Run standalone, a gate can print a confident refusal it would never produce in the real path — one only sees files once they are *staged*, so invoked directly it rejects with total conviction while never actually firing, which is perfect material for talking yourself into a bypass over a gate that was never going to block. And the reverse: a check the hook runs with a relaxing flag looks alarming raw while being structurally unable to block anything. **Read the line in the gate script that decides pass/fail and satisfy that** — never its printed help text, which states an intention and drifts from the condition.

**If a gate returns something you cannot attribute** — a green you distrust, a red you cannot explain, or a suite whose failures move between runs — read `../references/verification-epistemology.md` before you report or act. Do not read it on a clean pass.

## Red flags — stop

- About to report a gate result obtained through a pipe rather than `../scripts/gate.sh`.
- About to escalate a red gate without having triaged it into a named lane with its proof.
- About to apply a migration whose filename you have not just re-stamped to current UTC.
- About to follow a migration tool's suggested remedy that touches another session's ledger row.
- About to deploy without re-downloading and grepping the result.
- About to tell a fork to run `subagent-driven-development`.
- About to run `finishing-a-development-branch`.
- A plan file unchanged after its codex-review returned APPROVED.

## NEXT

**N = 1** → `step-06-closeout.md`
**A fork** → report `DONE <slug>` to the orchestrator and stop. Step 5 and step 6 are not yours.

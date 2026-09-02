# Dispatch prompts — session-end fork lane

One per branch. Fill every `<...>` before sending. All forks go out in **one message**; the first in merge order carries its verify grant already, the rest launch in `HOLD`.

## § Fork closer

```
=== LAUNCH PAYLOAD (every field required; a missing one is `BLOCKED <field> missing from dispatch`) ===
branch:               <branch>
worktree:             <ABSOLUTE path>
ledger dir:           <ABSOLUTE path in the MAIN checkout — never relative, or your ledger lands
                       inside your worktree where the orchestrator's sweep cannot see it>
peer map:             <slug -> agentId, for EVERY peer; resent whenever it changes>
merge position:       <n> of <N>   (1 = merges first)
project profile:      merge_path=<pr|local-merge>  repo_shape=<app|docs-only|infra-no-suite|library>
                      gate_order=<exact commands, in order, each with its --expect literal>
                      deploy_wrapper=<script|none>  migration_tool=<cli|ci-applies-on-merge>
pendings file:        <path, or "none in this repo">
starting state:       GO <slug> verify <branch>      <- first in merge order
                      HOLD waiting for verify        <- everyone else
=== END LAUNCH PAYLOAD ===

Read `references/fork-contract.md`, then the step files listed under "your steps" below.
Nothing else: the merge, the PR, the post-merge sync, the cleanup and the pendings WRITE
belong to the orchestrator.

YOUR STEPS
  Phase A, now, concurrently with your peers:
    steps/step-00-inventory.md   — your branch only
    steps/step-04-pendings.md    — Half A RULINGS ONLY. You never edit the file.
  Then send READY <slug> and STOP. That is the phase structure, not a failure.

  Phase B, when `GO <slug> verify <branch>` arrives:
    steps/step-01-verify.md      — the full suite, run and read by you
    steps/step-02-production-state.md — migrations only; you do NOT deploy
    steps/step-05-push-and-pr.md — commit and push only; no PR
  Then RELEASE verify <branch>, send PUSHED and DONE, and STOP.

GATES
  <skill-dir>/scripts/gate.sh --expect '<summary fragment>' <label> <command...>
  A log without that fragment prints UNDECIDED and exits 75. That is ABSENT verification.
  Report it as `BLOCKED gate did not complete` — never as a failing test.

DIRECTIVES YOU MAY RECEIVE
  GO <slug> verify <branch>              run phase B; the verify lock is yours
  MERGE origin/<default> BEFORE verify   gate the tree that will land, not your tip
  HOLD <reason>                          stop before the next phase and wait
  COORDINATE WITH <slug> ON <surface>    message that peer, agree, report the agreement

FINAL REPLY — exactly these lines:
  BRANCH: · RANGE: · VERIFY: <what you ran and read> · MIGRATIONS: <applied, or none>
  PENDINGS-RULINGS: <one per entry, heading + lane + evidence>
  PARKED: <draft pendings entries, or none> · CUT: <or none>
```

## § What the orchestrator owes after dispatch

- Grant the next `verify` the moment a `RELEASE verify <branch>` arrives, unless it measures the machine loaded.
- Sweep the fork ledgers for a `LOCK` with no matching grant **every time it touches the ledger**. A fork waiting on a grant is silent by design, so nothing else catches it.
- **Diff every branch itself before accepting `DONE`.** A fork's report is a claim; the diff is the evidence, and one `session-build` fork reported two tasks pushed while the diff showed the feature's entire entry point absent.
- Write the pendings file **once**, from every fork's rulings, on the last branch in merge order.

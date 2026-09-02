# session-end: router + steps, and a fork lane for multi-branch close-out

**Date:** 2026-09-02
**Status:** design approved, ready to plan
**Repo:** `claude-setup` (published as `will-pagane/claude-superdev-harness`)
**Touches:** `skills/session-end/**`, `skills/session-build/{steps/step-06-closeout.md,scripts/ledger.py}`, `docs/cadeia-session.md`

## Problem

Two defects, one structural and one behavioural.

**Structural.** `skills/session-end/SKILL.md` is a 36.7 KB monolith loaded in full on every
invocation. Ten steps sit inline. A docs-only branch that will never touch a migration, an edge
function or a pull request still pays for all of them. `session-build` solved this on 2026-08-26
by splitting into a 17 KB router plus six step files loaded just in time; `session-end` was left
on the old shape. Measured section weights:

```
6.3KB  Step 4  Pendings          3.6KB  Step 7  Merge
3.8KB  Step 0  Inventory         3.1KB  Common mistakes
```

**Behavioural.** `session-build` with `N ≥ 2` ends with an orchestrator session holding N pushed
branches, N worktrees and a `handoff.md`. Nothing in `session-end` knows what to do with that.
`docs/cadeia-session.md:209` states the trap plainly: *no session in the run is inside its own
worktree* — the orchestrator sits in the main checkout and the forks are refused `EnterWorktree`
— so neither can run `session-end` and land on the right branch by itself. The current answer is
a bullet inside Step 0 telling the orchestrator to enter each worktree in sequence. That works
(one orchestrator did it for five branches) and it dies on context: closing five branches in one
session means carrying five inventories, five suite logs and five diffs at once.

## Non-goals

- No change to the inline path. A single feature branch closes exactly as it does today.
- No renumbering of Steps 0–10. Fourteen cross-references to `Step N` live outside `SKILL.md`
  (eight in `references/traps.md`, plus `assets/report-template.md` and `session-build`'s own
  step-06). Renumbering breaks all of them silently.
- No parallel merging. See *Why not literal fork-runs-session-end* below.

## Decision 1 — split into a router plus step files

`SKILL.md` becomes a router carrying only what is true for every run: entry points, the
authorization block, the closed list of human gates, the bypass definition, `gate.sh`, the
"project rules win" block, the ledger, and the cross-cutting red flags. Target ~11 KB.

Each step file opens with the compressed invariant recap `session-build`'s step files use, and
names its successor. Files group steps; **the prose keeps saying "Step 4", "Step 7"**, so every
existing cross-reference stays valid.

| File | Steps it owns | ~size |
|---|---|---|
| `SKILL.md` | router | 11 KB |
| `steps/step-00-inventory.md` | Step 0, plus the compound-bash-refused rule | 4 KB |
| `steps/step-01-verify.md` | Step 1 and its three triage lanes | 2.5 KB |
| `steps/step-02-production-state.md` | Steps 2 and 3 | 2 KB |
| `steps/step-04-pendings.md` | Step 4 in full | 6.5 KB |
| `steps/step-05-push-and-pr.md` | Steps 5 and 6, the classifier ladder, *Making this deterministic* | 4.5 KB |
| `steps/step-07-merge.md` | Step 7, conflict lanes, the local-merge lane | 3.7 KB |
| `steps/step-08-sync-and-cleanup.md` | Steps 8 and 9 | 3.2 KB |
| `steps/step-10-report.md` | Step 10 | 1 KB |
| `steps/lane-fork-orchestrator.md` | the fork lane, decision 2 | new |
| `references/fork-contract.md` | the fork side of the fork lane | new |
| `dispatch-prompts.md` | the dispatch payload | new |

The *Common mistakes* table splits: rows that belong to one step move into that step, because
that is where the reader is standing when they make the mistake. The cross-cutting rows — "tests
passed earlier in the session", "report from memory", "the command exited 0" — stay in the router.

**Step 4 moves verbatim.** It was rewritten on 2026-09-02 and that text is the reason this spec
exists at all; see *What must survive* below.

## Decision 2 — three entry lanes, routed at Step 0

| Situation | Lane |
|---|---|
| A feature branch, or the default branch with a `handoff.md` naming one branch | **inline** — Steps 0–10 exactly as today |
| Default branch **and** `handoff.md` with `N ≥ 2` branches | **fork lane** |
| Default branch with worktrees and **no** `handoff.md` | **sequential** — today's `EnterWorktree` lane, kept verbatim |

The fork lane requires `handoff.md`. Without it there is no branch list, no merge order and no
project profile, and improvising those is what the handoff exists to prevent.

### The fork lane

**Single dispatch.** All forks go out in one message. The first in merge order carries
`GO <slug> verify <branch>` in its dispatch prompt; the rest launch in `HOLD`. A fork is one-shot
— it reports once and its turn ends — so this costs ~N revivals instead of 2N.

**What a fork does while holding**, concurrently and safely:

- Step 0 inventory for its own branch: base, diff, migration files, changed function dirs,
  uncommitted work, generated files.
- Step 4 **Half A rulings only**. It reads the pendings file, greps every identifier its diff
  touches, and emits one `PENDINGS-RULING <entry heading> <lane> <evidence>` line per hit.
  **It never edits the file.**
- Step 4 Half B dossier, drawn from its own `PARKED` lines in `fork-<slug>.md`, at the density
  `session-end` Step 4 already specifies: file and line, the number measured and how, the shape
  of the fix, the exposure left open, and a mark on any proof that cannot be re-run.
- Then `READY <slug>`, and the turn ends.

**Under `GO <slug> verify <branch>`, one fork at a time:** the full gate suite through
`gate.sh`, red-gate triage into the three lanes, migration confirmation against the remote
ledger, commit, push. Then `RELEASE verify <branch>`. The orchestrator grants the next fork on
that release.

**The orchestrator keeps everything global:** pull request, merge, post-merge sync, cleanup, and
the pendings file.

### Why the verify lock, restated

This is not caution. `session-build` imposed `LOCK verify` mid-run from a measurement — 12 logical
CPUs at 71% load with another session on the machine — and recorded the reason: CPU contention
returns *no* answer rather than a wrong one, and the natural misreading is that the red belongs to
the fork's own branch. Across two runs it measured load average 80.61 peaking at 98.88 on ~10
cores, a `git push` stuck 43 minutes in its pre-push hook, and a lint-plus-typecheck that did not
finish in 600 s on a branch touching no application code.

**The orchestrator takes the same lock for itself** at Step 7's post-merge union suite, and logs
the grant. That suite competes for the same cores as any fork still verifying. `session-build`'s
fourth orchestrator rule — *you are not exempt from the rules you enforce* — applies literally.

**Every `LOCK verify` names a resource.** The MCPlace handoff records two permanently outstanding
locks in `ledger.py sweep` that are false positives: both forks sent a bare `LOCK verify`, and a
grant with no resource matches nothing, so the pairs can never close. `LOCK verify <branch>`.

### Four changes that fall out of the lane

1. **The orchestrator never enters a worktree.** It merges from the main checkout — `git checkout
   <default>`, `git pull`, `git merge --no-ff <branch>` — and runs `git worktree remove` from
   there. This removes both the Step 0 default-branch stop and the compound-bash-refused trap for
   the orchestrator, which today costs runs dozens of refused calls.
2. **No fork-side deploy.** Step 3 leaves the fork lane. Deploy runs once, at Step 8, after the
   last merge. This is already the skill's own rule — *deploy is the last action after the last
   push* — and it removes the shared-deploy-target hazard for free.
3. **The pendings file is written once**, by the orchestrator, from the N forks' rulings,
   committed on the **last branch in merge order** before that branch merges. No extra `chore/`
   branch, and nothing committed straight to the default branch.
4. **`handoff.md` gains `spec slug → agentId`.** The real handoff read for this design says
   `Fork: alive, worktree untouched` and nothing more. Without the agentId the orchestrator
   cannot revive a fork at all.

### Degradation, because the failure is on record

In the MCPlace run the forks became unavailable mid-run and `session-build` fell back to running
`N = 1` twice, serially. The fork lane degrades the same way:

- **agentIds alive** (same orchestrator session) → `SendMessage` revives each fork with context.
- **agentIds dead, or the orchestrator restarted** → spawn a fresh `subagent_type: "fork"` whose
  dispatch payload points at disk: `handoff.md` plus `.superpowers/session-build/<RUN>/fork-<slug>.md`.
  Never assume a fork remembers anything.
- **Forks unavailable entirely** → fall back to the sequential lane and say so in one line.

### Why not literal fork-runs-session-end

The literal reading — each fork runs the whole of `session-end` on its branch — fails on three
measured facts, not on taste:

- `EnterWorktree` is refused for forks specifically, reproduced by three independent forks across
  two runs.
- A fork cannot remove the worktree it is standing in.
- Step 7 requires re-measuring immediately before merging. With N concurrent merges into the
  default branch, every such measurement is falsified by the neighbour that merged in between.

## Decision 3 — interface changes outside `session-end/`

- **`session-build/steps/step-06-closeout.md`**: `handoff.md` must carry the `spec slug → agentId`
  map explicitly, not the current prose `Fork: alive`.
- **`session-build/scripts/ledger.py`**: extend the shared checkpoint vocabulary with `READY`,
  `PENDINGS-RULING` and `CLOSED`. `session-end` **references** this script at
  `../session-build/scripts/ledger.py` rather than shipping a copy. The sweep's grep format
  drifting between two copies is exactly the failure that file exists to prevent, and the coupling
  is already real: `session-end` Step 0 already reads `session-build`'s handoff.
- **`docs/cadeia-session.md`**: lines 207–209 describe the old constraint ("open a session *from*
  the worktree") as the only path. Rewrite against the three lanes.

## What must survive, verbatim

`session-end` Step 4 was rewritten on 2026-09-02 to make pendings reconciliation consistent, and
that text exists in `~/.claude/skills/session-end/` **only** — it is committed nowhere. Every
piece below is load-bearing and moves into `steps/step-04-pendings.md` unchanged:

- the title *"Pendings: RECONCILE first, then collect"*;
- Half A runs on **every** invocation, including one that defers nothing;
- the four-lane table `resolved` / `stale-cause` / `moved` / `untouched`;
- resolved entries are **deleted**, never re-tagged `DONE`/`FIXED`/`CLOSED`;
- an entry is resolved from a **measurement**, not from the fact that the work was done;
- *"Nothing deferred → skip Half B only."*;
- Step 10's re-read of the pendings file, framed as the check that Half A actually ran;
- the two new *Common mistakes* rows and the new red flag;
- `assets/report-template.md`'s *Pendências reconciliadas* section with its four counts, every one
  stated even when zero.

**The first commit of the implementation is this text landing in the repo unchanged.** If it goes
in as part of the restructure, the split's diff swallows it and nobody reviews it.

### One thing the fork lane changes about it, deliberately

Execution and writing separate: N forks produce rulings, the orchestrator performs one write.
Today, closing N branches in sequence runs Half A N times against the same file, and each pass can
reopen what the previous one closed. A single write holding all N rulings is strictly more
consistent — which is what the 2026-09-02 edit was reaching for.

### Named limitation, not a silent one

"Resolve from a measurement" is weaker for the last branch in merge order. Entries touched by
branches 1..N-1 are measured against a default branch that already carries those merges; the last
branch's own entries are measured against its tree before merging. This residual exists in today's
per-branch lane too. It is written into the skill as a stated limitation rather than left to be
rediscovered.

## Verification

- **The router's byte count.** `SKILL.md` ≤ 12 KB; no step file above 7 KB.
- **No orphaned cross-reference.** Every `Step N` mentioned in `references/traps.md`,
  `assets/report-template.md`, `docs/cadeia-session.md` and `session-build/steps/step-06-closeout.md`
  resolves to a step some file owns. Checked mechanically, not by eye.
- **Step 4 preserved.** Diff `steps/step-04-pendings.md` against the 2026-09-02
  `~/.claude` text and read the result: the only permitted differences are the invariant recap
  header and the fork-lane paragraph.
- **The fork lane is a dry read, not a live run.** Nothing in this spec is verified by merging
  real branches. It is verified by the four checks above plus a walk-through of the lane against
  the MCPlace handoff, naming for each field whether the lane would have found it.

## Risks

| Risk | Response |
|---|---|
| The fork lane cannot be exercised without a real `N ≥ 2` run | Ship it, and say in the router that the lane is unexercised. The inline and sequential lanes are unchanged, so the blast radius is the lane itself. |
| Splitting a 36.7 KB file loses a sentence | Verify by reconstruction: concatenate the step files and diff against the original, then account for every removed line. |
| `ledger.py` is edited by this spec and by a concurrent `session-build` run | Single-writer: only this branch touches it. Declared in the surface manifest. |

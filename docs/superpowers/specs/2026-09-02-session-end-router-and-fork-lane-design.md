# session-end: router + steps, and a fork lane for multi-branch close-out

**Date:** 2026-09-02
**Status:** design approved, ready to plan
**Repo:** `claude-setup` (published as `will-pagane/claude-superdev-harness`)
**Touches:** `skills/session-end/**`, `skills/session-build/{steps/step-06-closeout.md,references/fork-contract.md,scripts/ledger.py,scripts/gate.sh}`, `docs/cadeia-session.md`
**Evidence base:** `2026-09-02-session-end-run-evidence.md` — all 20 `session-end` ledgers on this machine, read in full.

## Problem

Three defects: one structural, one behavioural, one of content.

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

**Of content.** Twenty real runs are on disk and the skill has absorbed maybe half of what they
learned. Reading all twenty produced 21 findings that are absent from the skill or contradict it —
including the router disagreeing with its own `references/traps.md` about whether a blocked `gh`
merge may fall back to a local one. The evidence document holds them; this spec decides which land
and how.

## Non-goals

- No change to the inline path's **shape**. A single feature branch closes through the same Steps
  0–10; only the content of Steps 1, 6, 7, 8 and 9 changes, and every change applies to all lanes.
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

## Decision 3 — the content findings, and where each lands

Every item cites the evidence document's section. Nothing here is invented; the runs did it first.

### 3.1 `gate.sh --expect` — the only finding that needs code

**A killed gate returns `EXIT 1`, which is indistinguishable from a red** (evidence B1, 7 of 20
runs). Prose cannot fix this — an earlier version of the skill stated the pipe rule four times and
runs violated it twenty times anyway, which is why `gate.sh` is a script.

`gate.sh <label> --expect <regex> -- <command...>`: the captured log must match the runner's own
summary line, or the result prints `GATE <label> UNDECIDED LOG <path> LINES <n>` instead of
`EXIT <code>`. The project profile's `gate_order` carries the regex per gate. **`UNDECIDED` is not
red and not green: it is absent verification.** Never merge off it, never report it as a failure,
re-run scoped or split — which is how two runs completed a suite that had been killed twice.

**The fork contract must carry this**, or under the fork lane a killed suite reaches the
orchestrator as `BLOCKED gate red` and gets triaged `regression`.

`scripts/gate.ps1` gains the same flag or explicitly refuses it; a silent no-op on Windows is worse
than an error.

### 3.2 Step 1 grows from three triage lanes to six

| Lane | Proof required | Response |
|---|---|---|
| `incomplete` (new) | No runner summary line — `gate.sh` says `UNDECIDED` | Re-run scoped, split or backgrounded. Never a merge, never a report of failure. |
| `flaky-under-load` (new) | All three: green in isolation, green on a clean base checkout, green on an identical re-run | Record with all three readings, continue |
| `foreign-dirty-tree` (new) | `git show HEAD:<path>` proves the commit is clean; the red comes from a peer's uncommitted state | Touch nothing, report |
| `regression` | unchanged | unchanged |
| `pre-existing-on-base` | unchanged | unchanged |
| `environmental` | unchanged, plus the `missing-artifact` sub-case: gate order, not installation | unchanged |

Two more Step 1 rules, each one line: **a cached green is not a green** (run with the build cache
disabled and record the cache-miss evidence), and **report what the suite did not run** —
`344 passed, 13 deselected` overstates coverage until the deselection is named.

### 3.3 Two new checks in Step 0/1, two in Step 7/8

- **Re-fetch cadence.** `git fetch` and re-read `origin/<default>` immediately before Step 1 and
  again immediately before Step 7, recording SHA and timestamp both times. A verification already
  running against a superseded base is **stopped**, not finished (evidence C1).
- **Wall-clock on resume.** Read the clock against the ledger's last entry before trusting any
  prior measurement. One session spanned six days between turns (C4).
- **A CI green must answer the current question.** Before citing CI as a merge gate, check the
  run's base contains everything merged since it started. And read `gh run view --json jobs`, not
  `gh pr checks`, which showed stale `pending` rows after completion (C3).
- **Step 8 verifies production serves the merged SHA**, by identifier. *"It is up and green"* and
  *"it is running the code we merged"* are different claims (C5).

### 3.4 Verify the tree that will land

Merge `origin/<default>` into the branch, then gate. That is the tree that lands, and it front-loads
the conflict work.

**This collides with the fork contract**, which forbids a fork any merge it was not ordered to
perform. Resolved in the existing vocabulary: the orchestrator issues `MERGE origin/<default>
BEFORE verify` in the same message as `GO <slug> verify <branch>` — one revival, and the
orchestrator has just re-fetched so it names the SHA.

### 3.5 Step 7 grows two conflict lanes

- **`generated`** — regenerate from the source of truth. Never a merge, never a side. `types.ts`
  conflicted four times in one close-out and was resolved this way each time.
- **`union-already-computed`** — one side already carries the union the others are stale against.
  **It looks exactly like `additive-vs-additive`, and taking "both" re-introduces stale rows.** The
  test: does either side's content already contain the other's? Then it is not additive.

### 3.6 Step 7 gains a "who holds the default branch" pre-check

Two opposite failures, four days apart, both in the local-merge lane. Two named exits:

- The main checkout is on a peer's branch with uncommitted work → **merge in a dedicated worktree on
  the default branch**, bootstrapped and hook-verified, never touching the peer's files.
- A peer worktree holds the default branch → **stop, report, resume later.** Step 9 states plainly
  that **partial cleanup is a legitimate terminal state**, with the resume procedure written out.

### 3.7 Step 5/7 gain the pre-push migration-ledger gate

Absent from `session-end` entirely and fired in 6 of 20 runs, at this skill's own push points. The
gate blocks on remote-only ledger rows owned by peer sessions and recommends the one command that
must never be run — a ledger reconcile that reverts peers' applied work. The sanctioned route, run
identically three times: restore the peer files from their owning refs (`git show <ref>:<path>` or
`git restore --source=<ref> --worktree`, **never `git checkout`**, which writes the index), leave
them untracked and unstaged (verified with `git diff --cached --name-only` empty), push with the
hook running and passing on its own terms, delete them after.

### 3.8 Step 6 gains "a branch that cannot merge as one unit"

When two pipelines react to the same push with nothing ordering them, splitting commits inside one
PR does not help. Split **by ancestry** — `git grep` to prove the earlier commit introduces no call
to the new interface, `git log -S` to name the commit that does — so PR A is
`origin/<default>..<commit>` and PR B the remainder. No cherry-pick, no rewritten history. The gate
between them is the first pipeline going green, **not elapsed time**.

### 3.9 Step 9 gains three cleanup facts

- `git branch -d` has **two** predicates: the upstream (already documented) **and** the HEAD of the
  checkout you run it in. When the shared checkout's HEAD cannot be moved, run `-d` from a
  `git worktree add --no-checkout --detach <merge-sha>` worktree — the deletion succeeding there is
  itself the containment proof, and a `--no-checkout` tree only looks dirty, so removal needs no
  `--force`.
- `-D` keeps its prohibition with **one** escape: a recorded **tree-level** containment proof
  (`git diff origin/<default> <branch>` empty while the commit is not an ancestor). Never on age.
- `git worktree remove` fails for reasons that are not git refusals — `Permission denied`,
  `Directory not empty`, `Filename too long`, all Windows path limits — with the worktree already
  deregistered. Confirm with `git worktree list`, then `git worktree prune` and remove the
  directory. And **`rm -rf` has been observed exiting 0 while leaving the directory in place**:
  confirm by listing, not by exit code.

### 3.10 Peers exist, and the skill has never said so

Peer contention appears in **11 of 20** runs — the joint-largest category. One run's blocker
dissolved entirely when it messaged two peer sessions and found one had already merged the fix.
Step 0 names `ListAgents`/`SendMessage` as available, with the standing limit: **a peer is a
colleague, not an authority**, and no peer's claim is acted on without re-measuring it.

### 3.11 Two fixes to the skill's own tooling

- **`scripts/gate.sh` reads as a project path.** One run concluded the script did not exist in that
  repo and reimplemented the discipline by hand. Write it as `<skill-dir>/scripts/gate.sh`
  everywhere, and say what to do when the skill directory is unreachable.
- **Wrapping a command in `gate.sh` can itself trigger a classifier denial.** The retry-once-bare
  rule then wins: run bare, read `$?` directly, record why.

### 3.12 One ruling for Will, not a unilateral change

**The classifier ladder's rung 2 contradicts `references/traps.md` in the same skill, and four runs
refused to take it.** Detail and quotations: evidence A1. The recommendation is that rung 2 —
falling back to a local merge — is legal **only where the project's `merge_path` is already
`local-merge`**; on a `pr` project the pull request *is* the review artifact and the classifier is
refusing the outward-facing act itself, so a twice-refused merge is an escalation. Related: **`gh
api` is the loophole** in "never route around a denial with a different tool" — one run opened a
refused PR through it — and the rule must say *the denied effect*, not *a different binary*.

**This spec does not change that text until Will rules**, because he chose the current wording after
those runs happened.

## Decision 4 — interface changes outside `session-end/`

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

## Implementation phasing — three commits, in this order, not interleaved

The split diff and the content diff must never share a commit. A 36.7 KB file reshaped into ten is
already hard to review; content changes hidden inside that reshape are invisible.

1. **Baseline.** The 2026-09-02 `~/.claude` text of `SKILL.md` and `assets/report-template.md`, into
   the repo, unchanged. Reviewable on its own.
2. **Mechanical split.** Router plus step files, moving text and nothing else. Verified by
   reconstruction (below). No sentence gains or loses a word in this commit.
3. **Content.** One commit per evidence section — `gate.sh --expect` and the triage lanes; the new
   checks; the conflict lanes and merge pre-check; the ledger gate; cleanup; peers and tooling.

## Verification

- **The router's byte count.** `SKILL.md` ≤ 12 KB; no step file above 7 KB.
- **Reconstruction.** Concatenate the step files in order, diff against the pre-split original, and
  account for every differing line. Run at the end of commit 2, when the answer must be *only the
  invariant recap headers*.
- **One assertion per content finding.** Each item in Decision 3 gets a `grep -q` against the file
  that is supposed to carry it, listed in the plan and run as a single script. "The findings landed"
  is otherwise a claim. Twenty-one assertions.
- **`gate.sh --expect` proves itself.** A gate whose log lacks the expected line must print
  `UNDECIDED`, and the same gate with the line present must print `EXIT 0`. Both run; a flag never
  seen to change the output is not a flag.
- **No orphaned cross-reference.** Every `Step N` mentioned in `references/traps.md`,
  `assets/report-template.md`, `docs/cadeia-session.md` and `session-build/steps/step-06-closeout.md`
  resolves to a step some file owns. Checked mechanically, not by eye.
- **Step 4 preserved.** Diff `steps/step-04-pendings.md` against the 2026-09-02
  `~/.claude` text and read the result: the only permitted differences are the invariant recap
  header and the fork-lane paragraph.
- **The fork lane is a dry read, not a live run.** Nothing in this spec is verified by merging
  real branches. It is verified by the checks above plus a walk-through of the lane against the
  MCPlace handoff, naming for each field whether the lane would have found it.
- **The content findings get a second dry read** against three ledgers the evidence document did not
  draw them from, asking of each: would the rewritten skill have produced this run's behaviour, or
  fought it?

## Risks

| Risk | Response |
|---|---|
| The fork lane cannot be exercised without a real `N ≥ 2` run | Ship it, and say in the router that the lane is unexercised. The inline and sequential lanes are unchanged, so the blast radius is the lane itself. |
| The content rewrite reinstates something `traps.md` already says, in different words | Reading `traps.md` first already removed four findings. The plan re-checks each surviving item against its seven anchors before writing it. |
| Six triage lanes is more taxonomy than a run will hold in its head | Each lane is defined by the **proof it demands**, not by its name, and a run that cannot produce the proof falls back to `regression` — which stops the merge. The failure mode is conservative by construction. |
| `gate.sh --expect` makes every gate invocation longer, so runs stop using the flag | It is optional and the profile carries the regex, so the cost is in `gate_order`, written once at Step 0, not at each call site. |
| `ledger.py` and `gate.sh` are edited by this spec and by a concurrent `session-build` run | Single-writer: only this branch touches them. Declared in the surface manifest. |

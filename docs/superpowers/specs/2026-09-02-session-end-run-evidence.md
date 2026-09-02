# session-end: what twenty real runs did that the skill does not describe

**Date:** 2026-09-02
**Sources:** all 20 `.superpowers/session-end/*/ledger.md` on this machine, every one read in full —
Kidsy Hub 10, Projeto Polo Fenix 5, MCPlace 4, Hermes Agent 1. Dates span 2026-08-11 to 2026-09-02.
**Status:** evidence base for `2026-09-02-session-end-router-and-fork-lane-design.md`.

Ledgers, not transcripts. The skill's Step 10 says to compose from the ledger rather than from
memory; the same rule makes the ledger the honest record of what a run actually did.

**Already covered, and deliberately not repeated here.** `references/traps.md` carries seven
anchors, and reading it first removed four findings from this document: the `merge=ours` three-step
trap (it carries a fourth step this reading missed), the docs → docs → deploy ordering and the
`git status`-on-download test that distinguishes a revert from your own bug, `git branch -d`
measuring against the upstream with the peer-holds-`main` second precondition, and the branch-sweep
question *"does production run code that exists in no merged ref?"* — which one run answered yes to,
finding a function live since 2026-07-07 whose source was in no merged ref. Findings below are
either absent from that file or correct something in it.

---

## A. The skill contradicts itself

### A1. The classifier ladder tells `pr` projects to do what four runs deliberately refused

Step 6's ladder says: `gh` refused → retry bare → **fall back to the local merge lane** → escalate
only if `git merge` is refused too. Added in `5e29c85`, *after* the runs below, and in reaction to
two of them.

`references/traps.md#classifier-denials` says the opposite in the same skill: *"Two runs correctly
refused to work around a denial by switching tools."* **The router and its own reference file
disagree.**

Four runs refused the fallback, in writing:

> *"A local `git merge` followed by a push to `main` would perform exactly the irreversible
> outward-facing action the block exists to guard, through a different command."* — MCPlace `20260826-0420`

> *"Reconstructing the merge with plumbing (`commit-tree` + `update-ref`) would be precisely the
> bypass the denial exists to prevent."* — Kidsy `20260826-0330`

> *"Not attempting a local merge+push to main: that bypasses the denial's intent."*
> — Hermes `20260822-1915`

> *"the classifier is inconsistent, and I will not insist nor route around it by another door"*
> — cited in `traps.md` itself

**The distinction the ladder loses is the project's own `merge_path`.** Falling back to `git merge`
is a route change only where local merge is *already* the project's sanctioned path. Where the
project mandates a pull request, the PR **is** the review artifact and the classifier is refusing
the outward-facing act itself.

This is a ruling for Will, not a defect to fix unilaterally — he chose the current text. The
recommendation is: **rung 2 conditional on `merge_path: local-merge`.** On a `pr` project a
twice-refused merge is an escalation, and the run hands over with the branch pushed, the PR open and
CI green. Every one of those four handovers landed within hours once the user ran the command.

### A2. `gh api` is the loophole in "do not route around a denial with a different tool"

Hermes `20260822-1915`, in the same run that refused the local merge:

> *"`gh pr create` refused by the auto-mode classifier twice — **opened via `gh api` instead**: PR #2"*

Then, correctly, for the merge: *"`gh api PUT .../merge`: refused by classifier. STOPPED."*

The rule says *different tool*. `gh api` is the **same** tool, which is how it got through. **The
rule is about reaching the denied effect, not about the binary you type.**

### A3. `--body-file` is not the cure the empirical pattern claims

`traps.md#classifier-denials` states: *"`gh` write commands issued bare — no pipe, no redirect, body
via `--body-file` — correlate with success."* Kidsy `20260823-0100` refutes it as a reliable fix:

> *"`gh pr create` refused twice by the classifier — once with an inline `--body` heredoc, **once
> with `--body-file`**. Stopped rather than trying further variants."*

Keep the pattern as a first retry; drop any implication that it resolves the denial.

### A4. `git branch -d` has two predicates, not one

`traps.md#cleanup` documents the upstream predicate, and Polo Fenix `20260812-1930` confirms it
verbatim (*"not yet merged to `refs/remotes/origin/…`, even though it is merged to HEAD"*). Kidsy
`20260826-1900` hit the other half:

> *"the refusal was **not** about containment. It measures against **HEAD**, and the shared
> checkout's HEAD was the peer's branch, which does not contain these merges."*

Its remedy is the reusable part, and it is not in the skill: `git worktree add --no-checkout
--detach <merge-sha>`, run `-d` from there — *"both deleted cleanly, which is itself the containment
proof"* — then remove it. A `--no-checkout` tree only *looks* dirty, so removal needs no `--force`.

### A5. `-D` has one proven exception, and the skill's absolute hides it

MCPlace `20260825-1914`:

> *"`git diff origin/main <branch> -- <file>` is **EMPTY**. The trees are identical … containment
> here is proven at the **tree** level, not the commit level. `-D` discards a commit whose content
> `main` already has, byte for byte."*

Keep the default absolute; add the single escape — `-D` only with a recorded tree-level containment
proof, never on age.

### A6. Per-branch pendings is already known to be wrong for a multi-branch close-out

MCPlace `20260825-1914`, flagged by the run itself as a deviation from the skill:

> *"Writing pendings on all three branches would have created three conflicts in one file for no
> gain, so the tracker additions were made **on the infra branch**, which already owns it."*

Kidsy `20260901-0530` paid the other side: `PENDINGS.md` conflicted **three times** in one close-out.
And Kidsy `20260823-0100` invented the fork lane's exact protocol on its own:

> *"STALE SURVIVOR FOUND — **reported, NOT edited** (PENDINGS.md is orchestrator-owned and editing
> it here would collide with its docs pass)."*

---

## B. Step 1's triage has three lanes and needs six

Current lanes: `regression`, `pre-existing-on-base`, `environmental`.

### B1. `incomplete` — the gate that never finished

The highest-frequency finding in the corpus, and the most dangerous, because **`gate.sh` reports
`EXIT 1` for a killed run and that is indistinguishable from a red.**

> *"The FULL suite was KILLED mid-run TWICE — once after 2189 log lines, once after 963, neither
> with a summary line — and `gate.sh` reports EXIT 1 for that, **which reads exactly like a red and
> is not one**."* — Kidsy `20260901-0530`

> *"Two earlier attempts at that confirming run were killed — one by this session's 10-minute tool
> timeout, one by the harness — and were recorded as *undecided*, not as red. **A gate that did not
> finish did not decide.**"* — Kidsy `20260826-1900`

**Prose is the wrong instrument for this, which is the whole reason `gate.sh` exists.** The
mechanism: `gate.sh --expect <regex>` — the captured log must match the runner's own summary line or
the result prints `GATE <label> UNDECIDED LOG <path>` instead of `EXIT 1`. The project profile's
`gate_order` carries the regex per gate. **The fork contract must carry this too**: under the fork
lane a killed suite otherwise reaches the orchestrator as `BLOCKED gate red` and gets triaged
`regression`.

### B2. `flaky-under-load`

> *"passed isolated on the merged tree AND passed on a clean base worktree, and the identical gate
> returned green on re-run — flaky under 306-file parallel load, not a regression."*
> — Kidsy `20260902-0300`

Distinct from `environmental` (which has an artifact to repair) and from `pre-existing-on-base`
(which is red on the base). **Proof required, all three:** green in isolation, green on a clean base
checkout, green on an identical re-run.

### B3. `foreign-dirty-tree` — the red belongs to another session's uncommitted state

> *"`tsc exit=2` and lint 3 errors are `TS1185` 'merge conflict marker' from the **dirty tree of the
> parallel session**, NOT from the commit: `git show HEAD:<file>` returns 0 markers in all three.
> HEAD is intact. Nothing was touched."* — Kidsy `20260819-0600`

Step 0's `MERGE_HEAD` check catches the state; nothing tells Step 1 what to do with the red it
produces. **Proof: `git show HEAD:<path>`. Response: touch nothing, report.**

### B4. `missing-artifact`

> *"typecheck ran before build had generated `.next/types/` and failed with `TS6053: File … not
> found`. **Not a type error — a missing artefact.**"* — MCPlace `20260825-1914`

The repair is ordering, not installation — which is why the project profile's `gate_order` must
record the **order**, not only the commands.

### B5. A cached green is not a green

Same run: every gate re-run with `--force`, *"each confirming `Cached: 0`"*. `gate.sh` reads an exit
code, and a cached exit code is a recording of an older tree. Where the project uses a build cache,
Step 1 runs with it disabled and the ledger records the cache-miss evidence.

### B6. Report what the suite did not run

> *"`pytest -q` → **344 passed, 13 deselected** … **'344 passed' alone overstates coverage.**"*
> — MCPlace `20260825-1914`

---

## C. Measurements the skill never takes

### C1. `origin/<default>` moves during the run

Measured moving mid-run in 4 of 20. Kidsy `20260826-0330` had it move **twice**, the second time
caught by accident:

> *"Caught only because a `git log --merges origin/main` run for an unrelated reason printed a merge
> above the SHA measured minutes earlier. … The first verification run was already testing a
> superseded tree, so it was **stopped** rather than left to finish."*

**Required:** `git fetch` and re-read `origin/<default>` immediately before Step 1 and again
immediately before Step 7, recording SHA and timestamp both times.

### C2. Verify the tree that will land, not the branch tip

The same run merged `origin/main` into the branch and then gated — *"on the tree that would land"*.
Kidsy `20260825-2115` went further and made the merged default branch the *decisive* run instead of
three branch runs; it went red and exposed that the main checkout had carried a stale `node_modules`
for days, *"so any suite run there was measuring the wrong tree."*

**Collides with the fork contract**, which forbids a fork any merge it was not ordered to perform.
Resolution: the orchestrator issues `MERGE origin/<default> BEFORE verify` alongside
`GO <slug> verify <branch>` — same vocabulary, one revival, and the orchestrator has just re-fetched
(C1) so it can name the SHA.

### C3. A green CI run can be answering a question nobody asked

> *"PR #15's green answered the wrong question, and was refused as evidence. Its CI run had started
> *before* #14 merged, so it validated against a `main` with no drift guard … a check that is
> structurally incapable of failing on the thing it is being cited for."* — MCPlace `20260822-2020`

Tool trap from the same run: **`gh pr checks` showed stale `pending` rows after the run had
completed**; `gh run view --json jobs` was the reliable read.

### C4. Wall-clock moves between turns

> *"`select now()` returned **2026-09-01**, not 2026-08-26: this session spanned nearly a week
> between user turns. Detected by a count that looked wrong — 1575 worker ticks where ~50 were
> expected. Every measurement taken before that point was re-taken."* — Kidsy `20260826-1900`

On resume, read the clock against the ledger's last entry before trusting any prior measurement.

### C5. "Healthy" and "running the merged code" are different claims

> *"But that redeployed the OLD image … Production was healthy and still not running the merged
> code. *'It is up and green'* and *'it is running the code we merged'* are different claims, and
> only the second was the goal."* — MCPlace `20260825-1914`

Step 8 verifies production serves the **merged SHA**, by identifier — not that it answers 200.

---

## D. Lanes the skill has no room for

### D1. Somebody else holds the default branch

`traps.md#cleanup` covers the *stop-and-report* half. The other exit is not in the skill, and it
worked:

> *"The main checkout was on `fix/repo-pre-push-peer-migrations-20260831`, another session's branch,
> with uncommitted work. Running the local-merge lane's `git checkout main` there would have yanked
> the branch out from under a live session. **Merged in a separate worktree on `main`** instead,
> bootstrapped and hook-verified."* — Kidsy `20260826-1900`

And the resume half, which the skill treats as an incomplete run rather than a terminal state: Kidsy
`20260901-0030` stopped at cleanup, reported, and **completed Step 9 in a later turn** once the peer
released `main`. **Partial cleanup is a legitimate terminal state with a written resume procedure.**

### D2. Two conflict lanes are missing, and one of them silently corrupts

The skill has `additive-vs-additive` and `semantic`. Kidsy `20260901-0530` resolved four kinds in one
close-out:

- **`generated`** — `types.ts` conflicted **four times**, *"resolved by REGENERATING from the
  database rather than picking a side."* Never a merge, never a side.
- **`union-already-computed`** — `_status-matrix.md` *"NOT additive — HEAD carried the union
  worker-orders computed across all four branches while every other side was the stale base table,
  so HEAD won."* **This looks exactly like `additive-vs-additive` and taking "both" re-introduces
  stale rows.**

A third shape, correctly escalated rather than resolved: Polo Fenix `20260812-1830` met a conflict
where **both sides had independently closed the same pendings entry** with different
implementations. Merging cost a real accessibility test, named in the report. That is an argument
for A6 as much as for the conflict lanes.

### D3. The pre-push migration-ledger gate is absent from this skill entirely

Fired in 6 of 20 runs, at Step 5 and Step 7 — this skill's own push points. It blocks on remote-only
ledger rows belonging to peer sessions and recommends the one command that must never be run:

> *"`npm run db:doctor`, which the hook's own message recommends, would have reconciled the ledger
> by **reverting peers' applied work**."* — Kidsy `20260826-1600`

The sanctioned route, executed identically in three runs: restore the peer files from their owning
refs (`git show <ref>:<path>`, or `git restore --source=<ref> --worktree`, never `git checkout`,
which writes the index), leave them **untracked and unstaged** — verified with
`git diff --cached --name-only` empty — push with the hook running and passing on its own terms, then
delete them. `session-build`'s fork contract carries this; `session-end`, where the push happens,
does not.

### D4. A branch that cannot merge as one unit

MCPlace `20260822-2020`. Two pipelines react to the same push with nothing ordering them:

> *"Splitting commits inside one pull request does not help — **the race is between two pipelines
> reacting to one push.**"*

The split was by **ancestry**, not cherry-pick: `git grep` proved commit 8 introduced no call to the
new RPCs and `git log -S` named commit 9 as the one that did, so PR A was `origin/main..<commit 8>`
and PR B the remainder — *"full history preserved, no duplicated commit."* The gate between them was
the migrate job going green: *"That is the gate — not elapsed time."*

### D5. Worktree removal failures that are not git refusals

`traps.md#cleanup` covers the dirty-tree refusal. These are different: `Permission denied`,
`Directory not empty`, `Filename too long` — **Windows filesystem limits on deep `node_modules`
paths**, with `git worktree list` confirming the worktree already deregistered. And the trap inside
it:

> *"the background attempt before it **exited 0 while leaving the directory in place** … caught by
> listing the directory rather than trusting the exit code."* — MCPlace `20260825-1914`

That run left a locked `.next/cache/webpack` tree in place deliberately — gitignored, regenerable,
and *"killing processes blind to remove cosmetic residue is a worse trade."*

### D6. Peers are reachable, and talking to them dissolved a blocker

Polo Fenix `20260811-1420` escalated a red pre-push gate caused by another session's applied
migration; the user ruled *"coordinate first"*; the run messaged two peer sessions. One had **already
merged the fix**, verified independently on `origin/main`. The blocker dissolved without touching
anyone's files. The skill never mentions that peers exist. Peer contention appears in **11 of 20**
runs.

---

## E. What the corpus confirms about the fork-lane design

Precedents the sibling spec should cite rather than argue.

- **The orchestrator working from the main checkout, deliberately.** *"Working from the MAIN checkout
  throughout rather than entering each worktree … which also avoids the compound-bash restriction
  that applies inside a worktree."* — Kidsy `20260901-0530`, four branches. Same reasoning in
  MCPlace `20260822-2020`, three branches.
- **`LOCK verify` already crosses into `session-end` in practice.** *"Suite deliberately NOT re-run:
  bling-cron-auth holds LOCK verify and the orchestrator vetoed retaking it."* — Kidsy `20260823-0100`
- **The union suite is the measurement nobody else takes, and it earns its keep.** Kidsy
  `20260825-2115`.
- **The sequential `EnterWorktree` lane works and stays.** MCPlace `20260825-1914` entered three
  worktrees in turn; Polo Fenix `20260812-1830` did five and recorded the correction to
  `session-build`'s premise: *"A recusa observada valia para os **forks**, não para o orquestrador."*

---

## F. Two defects in the skill's own tooling

### F1. `scripts/gate.sh` reads as a project path

> *"**`scripts/gate.sh` does not exist in this repo.** Gates are run directly, one command per call,
> output redirected to a log, `$?` read immediately and never through a pipe."* — Kidsy `20260826-1900`

The path is relative to the skill directory, not the repo. That run resolved it against the repo,
found nothing, and reimplemented the discipline by hand — correctly, but it should not have had to.
Write it as `<skill-dir>/scripts/gate.sh` everywhere, and say what to do when the skill directory is
not reachable.

### F2. Wrapping a command in `gate.sh` can itself trigger a denial

> *"Three classifier denials this run, all cleared by retrying in a simpler shape … and `npm run
> build` under `gate.sh` (re-issued **bare**)."* — Kidsy `20260826-1600`

The retry-once-bare rule and the always-use-`gate.sh` rule collide. When they do, the bare run wins,
the exit code is read directly, and the reason is recorded.

---

## G. Frequency

Counted mechanically over all 20 ledgers with `grep -qiE` per file, not from recall. Patterns are
recorded so the numbers can be re-derived; they are lower bounds, since a run can hit a trap without
naming it.

| Pattern | Runs |
|---|---|
| `origin/<default>` movement explicitly measured | 4 |
| …and actually moved mid-run | 4 |
| Peer-session contention (main checkout, `main`, or a shared file) | 11 |
| Classifier refusal on a `gh` or merge call | 11 |
| Used `gh` for a PR or merge at all | 10 |
| Explicitly refused to route around a denial | 4 |
| A gate that did not finish, or was called non-conclusive | 7 |
| Exit status swallowed by a pipe, caught | 7 |
| Pre-push ledger gate / borrowed peer migration rows | 6 |
| Deploy verified by downloading the bundle | 7 |
| Migration reading as unapplied because the local column was blank | 3 |
| `git worktree remove` failing for a non-git reason | 3 |

The two largest — peer contention and classifier refusals, 11 each — are both about **things outside
this branch moving while the run works**, and neither has a step that owns it.

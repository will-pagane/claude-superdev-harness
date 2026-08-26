# Step 3 — Isolate

**Invariants recap** (full text in `../SKILL.md`): no PR, no delivery merge (the ONE exception is a peer-branch integration merge an orchestrator ordered by name), no branch/worktree deletion, no tree-mutating recovery. Five human gates only — never ask "should I continue?". A bypass is *any* flag or env var whose effect is that a hook does not run. Every measurement is a reading. Gates run through `../scripts/gate.sh`. One step file at a time.

Branch `<type>/<spec-slug>-<YYYYMMDD>`, worktree `.claude/worktrees/<spec-slug>-<YYYYMMDD>` — one pair per spec, named from that spec, never a combined slug and never a harness-generated random name.

**N = 1:** use `superpowers:using-git-worktrees`, then build inline. This is not optional and it is not implied by anything else in this step — a run that skipped it built on branches switched in place inside the main checkout, while another session was working in the same repo.

**N ≥ 2:** the orchestrator creates every worktree itself, up front, and **stays on the main checkout** — so it can always inspect all of them.

```bash
git worktree add -b <type>/<spec-slug>-<YYYYMMDD> \
  .claude/worktrees/<spec-slug>-<YYYYMMDD> origin/<default-branch>
```

For a **total** dependency the base ref is the dependency's branch instead, and that worktree is created only after the dependency reports `PUSHED`. An **ordered** dependency still branches from the default branch and starts immediately.

## 3.1 Bootstrap checklist — run it in this order, per worktree

**Bootstrapping is a correctness step, not a convenience: an unbootstrapped worktree has NO GATES AT ALL, silently.** Do all five, then dispatch:

1. **Install dependencies.** A fresh worktree has none of the previous one's local state.
2. **Copy the gitignored environment file** the project needs (`.env` and friends). Missing it does not fail fast — one run spent 22 minutes and three full test runs discovering it from a log line two thousand lines down, and another hit the same wall at the most irreversible moment of its run.
3. **Run the project's per-checkout link step**, if it has one — for a Supabase project that is `supabase link --project-ref <ref>`, **once per worktree**. Never copy another checkout's `supabase/.temp/` in: one run copied it into five worktrees and armed the pre-push ledger gate against all five, including the branch that only touched documentation.
4. **Confirm `core.hooksPath` resolves to a directory that exists.** Hook managers commonly point it at a **relative** directory their own install script creates. A worktree that never had dependencies installed resolves that path to nothing — and git runs **no hooks and reports nothing**. Not one gate skipped: every gate, quietly, while commits and pushes succeed and nothing goes red. This is the most complete false green the run can produce, and this step is what creates the opportunity. One `ls` per worktree.
5. **Prove a gate can go red.** Run one gate through `../scripts/gate.sh --prove-red` against a known-bad input. An inventory of green checks is not coverage until you know which of them could have returned non-zero.

Treat a fork reporting "all gates green" from a worktree that did not pass all five as reporting nothing at all.

## 3.2 What `EnterWorktree` actually does — three separate facts

An earlier version of this skill collapsed these into one contradictory claim. They are independent:

- **A fork cannot enter its worktree.** Reproduced by three independent forks across two runs: calling `EnterWorktree` with the correct absolute path is refused, and it is not a path-normalisation bug — `git worktree list --porcelain` reports the exact path and `pwd -P` inside it matches byte-for-byte.
- **A plain session can.** One orchestrator entered five worktrees in sequence with no refusal and returned to the main checkout with `ExitWorktree`. So the refusal is specific to forks. The practical consequence lands in step-06: the close-out must **not** tell the user that a fresh session is the only way to run `/session-end`.
- **`EnterWorktree` fails outright when the session's working directory is not inside a git repository** — a different failure with a different message, and nothing to do with forks.

There is a fourth, for later: **`ExitWorktree`'s removal path measures against the branch name the worktree was created with**, so it fails after the project-mandated `git branch -m`. Removal is `/session-end`'s job, not this skill's, but the fork contract mentions it so nobody is surprised.

## 3.3 Isolation is a discipline, not a tool call

Because a fork cannot enter, the fork contract states isolation as rules:

- every `Read`/`Write`/`Edit` takes an absolute path under the fork's worktree — never a relative one;
- **every `Bash` call `cd`s into the worktree in the same command** — this applies to a fork, whose session is *not* inside the worktree. A session that **is** inside a worktree has compound bash refused and must do the opposite: one simple command per call, no `cd X && …`. Know which of the two you are before writing a command.
- `git -C <worktree-abs-path> branch --show-current` is checked before **every** commit and must print that fork's branch.

The repo's own branch gate is the **backstop**, not the primary guard. The orchestrator, on the main checkout, **watches `git status` there for stray writes** — a file it did not touch appearing dirty means a fork lost its discipline, and that is an escalation.

Do not spend a round-trip letting each fork rediscover this. Tell them at dispatch.

## 3.4 Ledger cadence — and the premise behind the number

Append to the ledger the moment anything happens; that is what survives compaction, because compaction destroys context, not the filesystem. **Commit** it at three milestones only: end of this step's predecessor (step-02 close), after the manifest intersection, and at close-out.

**State the premise, or the rule gets reversed as noise.** The number three exists because every commit runs the repo's pre-commit hooks — in one run a full code-graph rebuild over the whole tree, per ledger line, on a machine already saturated by N concurrent forks. **In a repo with no hooks the rule buys nothing**, and a run that applied it there called it actively harmful and nearly lost a working tree to it. So: three milestones where commits are expensive; commit freely where they are not; and either way keep `commit` and `push` separate decisions, because in some repos every push to the default branch triggers a production deploy.

During a containment window this stops being an economy and becomes correctness — see `../references/orchestration-deadlocks.md`.

## Red flags — stop

- About to dispatch a fork into a worktree whose hook directory you have not seen with your own eyes.
- About to dispatch without having proved one gate can go red.
- About to build an `N = 1` run without a worktree.
- About to create a total-dependency branch before its dependency reported `PUSHED`.
- About to put two sessions in one worktree, for any reason.

## NEXT

**N = 1** → `step-04-build.md`
**N ≥ 2** → `step-05-orchestrate.md` (which dispatches forks into `step-04-build.md`)

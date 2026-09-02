# Step 6 — Close-out

**Invariants recap** (full text in `../SKILL.md`): no PR, no delivery merge (the ONE exception is a peer-branch integration merge an orchestrator ordered by name), no branch/worktree deletion, no tree-mutating recovery. Five human gates only — never ask "should I continue?". A bypass is *any* flag or env var whose effect is that a hook does not run. Every measurement is a reading. Gates run through `../scripts/gate.sh`. One step file at a time.

## 6.1 The close-out is a handoff, not an ending

Measured once: a close-out went out with every branch pushed and everything green; the user ran the app and **found ten defects in about twenty minutes, two of them security**. None was reachable by anything the run had spent its time on — not 24 rounds of adversarial plan review across three specs, not eleven gates, not ~1,500 tests. Capture rate of the whole automated funnel against a human opening the screen: **zero**. The same machinery had, in that run, caught a dead-code type error and a migration that aborted in production — which nothing human was going to find. **Disjoint classes.** So:

- **`PUSHED` is not a point of no return.** It is the moment the branch becomes good enough for someone to look at.
- **Frame the report as the handoff to the only reviewer who sees the class of defect nothing automated sees.** A user who reads "done, all green" opens the app expecting confirmation; a user who reads "this is now worth your twenty minutes, and here is what I could not check" opens it hunting.
- **Reopening after close-out is routine, not failure.** A fork that reports DONE is not closed until you have diffed its branch yourself; if the diff contradicts the report, reopen. That is the normal path, not an exception.

## 6.2 Measure the topology at the moment you write the instruction

**Check how many branches actually carry distinct work before saying "one per branch".** Verify it, do not assume it from the count of specs: `git rev-parse` each branch and test ancestry between them. A run that pushed three branches ended with **two at the identical SHA and the third an ancestor of both** — three branches, one deliverable. Telling the user to close each would have produced two empty pull requests. When they collapse, say *run it once, on this branch*, and name which one.

**And re-check, because the answer moves.** In that same run a later push shifted one branch six commits ahead of the other two within the hour: the collapse went from *any of the three delivers everything* to *only this one does*. A close-out naming the wrong branch after such a shift instructs the user to merge something incomplete.

**The two claims do not decay at the same rate.** *"These are independent"* ages far faster than *"this one depends on that one"*, because independence is a claim about **the whole world** and dependence is a claim about **two objects**. Anything merging anywhere falsifies the first. Observed: a close-out stating "no mandatory merge order, all five are independent" — verified against real commits when written — was false within the hour, when an unrelated branch merged, touched a shared file, and turned one pull request into a conflict resolved by shrinking that branch's scope. **State independence with its timestamp and a shorter shelf life than any dependency printed beside it.**

## 6.3 Before you call any step human-only, prove it

A close-out that hands the user five manual panel steps is a claim about tooling, not a fact. Observed: five "only you can do this" steps in a hosting and repository panel; the user asked whether the vendor CLI could do it; the CLI was already authenticated, could list projects and fetch identifiers, and **four of the five collapsed into one**. Check the CLI before writing the manual step.

The same test gates human gate 5: a runbook step is manual only after you have looked for the automatable path and not found one.

## 6.4 Write the report

Read `../assets/closeout-report-template.md` and fill it. **Delete every section with nothing in it** — never write "N/A", "nenhum", or an empty heading. Compose from the ledger, never from memory, and print inline in the user's language.

Before releasing it, relocate or de-reference every gitignored artifact the report or the pendings cite. Review directories, execution ledgers and run transcripts that live **inside a worktree** and are git-ignored are not in history either — when `/session-end` removes that worktree they become dead pointers, and its stranding check sees neither.

## 6.5 Who the user talks to

State this explicitly in the report — it is not obvious from outside.

**During the run: the orchestrator, always.** It is the only session holding the whole picture and the only one granting locks. A directive sent straight to a fork bypasses that: the orchestrator still believes the fork is holding and may grant the lock to someone else.

**After the run: `/session-end`, once per branch, in merge order — and it needs a session whose *working directory* is the worktree.** This is mechanical: `session-end` reads `git branch --show-current` at its step 0 and must leave the worktree to remove it at step 9, so it assumes cwd, not `-C` flags.

**The orchestrator can do it, and this is the cheapest path.** The `EnterWorktree` refusal binds **forks**, not a plain session — one orchestrator entered all five of its worktrees in sequence, closed each branch, and returned with `ExitWorktree`. Offer that first: it already holds the whole picture and every fork's close-out, and needs no context transfer.

**Two things about `/session-end` break in that mode and it must be told about them.** Its step 0 stops when the current branch is the default one — which is exactly the orchestrator's correct starting state, so read that as *"enter each worktree"*, not *"abort"*. And a session inside a worktree has **compound bash refused**: no `cd X && …`, no redirects, no `for`, no `;`-joined pairs, and no `-C` pointing at a different worktree. Every command becomes simple and one per call.

**A fresh session launched from the worktree remains a valid option**, not a requirement. Everything that step needs is in the ledger; each fork's `PARKED` and `CUT` entries exist precisely so a session that did not build the branch can still write honest pendings.

## 6.6 Hand off to `/session-end` with what it would otherwise re-derive

Write `.superpowers/session-build/<RUN_ID>/handoff.md` and name it in the report: branch list with commit ranges, worktree absolute paths, merge order **with the reason each branch holds its position**, the deploy set, migrations applied and whether their branch has merged, live-fork status, the project profile from step-01, **the `PENDINGS-SOURCE` list from step-02 — every pendings entry this run's specs were built from, quoted by heading — and the `spec slug → agentId` map for every fork.**

That last field is what `/session-end`'s fork lane addresses forks by, and it cannot be reconstructed. A real handoff recorded only *"Fork: alive, worktree untouched"* — true, and useless as an address, because names are not unique on this machine and only the agentId disambiguates. If a fork is dead, say so and give the id anyway: the lane spawns a fresh fork pointed at `fork-<slug>.md` on disk, and never assumes a fork remembers anything.

That last field is the one `/session-end` cannot reconstruct. Its Step 4 reconciles the pendings file against the branch diff, which catches entries naming a file you touched and misses entries describing a behaviour you fixed. Naming the entries closes that gap — and if this run consumed no pendings entry, say so in one line rather than omitting the field, because an absent section reads as a forgotten one.

`/session-end` **re-measures everything it acts on** — the handoff tells it *what* to measure, never what is true. Without it that checklist gets improvised from scratch, which is what happened in every observed run where the boundary was crossed by hand.

## Red flags — stop

- About to tell the user to run `/session-end` once per branch without having tested ancestry between them.
- About to state that branches are independent without a timestamp.
- About to write a manual step you have not tried to automate.
- About to leave a report section reading "N/A" instead of deleting it.
- About to abandon or park a branch whose migration already landed, without naming that migration.
- About to remove or hand over a worktree holding gitignored artifacts the pendings still cite.
- About to write `handoff.md` without the `PENDINGS-SOURCE` list, or without an explicit line saying this run consumed none.
- About to open a PR or merge. This skill does neither, ever.

## NEXT

Terminal. The branches are pushed and verified; the user reviews, then runs `/session-end`.

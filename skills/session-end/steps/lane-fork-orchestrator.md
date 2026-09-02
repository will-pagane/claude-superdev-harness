# Lane — fork orchestrator (N ≥ 2 branches)

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on these branches, including the merges — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

> **This lane is unexercised.** No real `N ≥ 2` close-out has run it end to end. The inline and sequential lanes are unchanged and carry every observed run, so the blast radius is this file. Read it as a design with evidence behind each rule, not as a path with mileage on it.

## When this lane runs

Step 0 routed here because the session is on the default branch **and** `.superpowers/session-build/<RUN_ID>/handoff.md` names two or more branches. Without that handoff there is no branch list, no merge order and no project profile, and improvising those is what the handoff exists to prevent — take the sequential lane instead.

**Why not simply run the inline lane N times in one session:** it works, and it dies on context. One orchestrator closed five branches that way, correctly; doing so means carrying five inventories, five suite logs and five diffs at once. The two context sinks are reading a failing suite log and grepping the pendings file per identifier, and both are per-branch. This lane moves them into the forks.

## The split, and the principle behind it

**Forks do the reading. The orchestrator does everything global.** A thing is global when doing it twice concurrently is wrong: the merge (each one moves the default branch and invalidates the next one's pre-merge measurement), the deploy, and the pendings file, which is one file.

### Dispatch — one message, first fork already granted

All forks in a single message. The first in merge order carries `GO <slug> verify <branch>` in its dispatch prompt; the rest launch in `HOLD`. A fork is one-shot, so this costs about `N` revivals instead of `2N`.

**Every fork's prompt carries what it cannot know:** its branch, its worktree absolute path, the **absolute** ledger directory in the main checkout, the `spec slug → agentId` map for its peers, the project profile with `gate_order`, and its position in the merge order.

### What a fork does while holding — safe to run concurrently

- **Its own Step 0 inventory:** base, diff, migration files, changed function directories, uncommitted work, generated files.
- **Step 4 Half A rulings only.** It reads the pendings file, greps every identifier its diff touches, and emits one line per hit:
  `PENDINGS-RULING <entry heading> <lane> <evidence>`, lane being `resolved` / `stale-cause` / `moved` / `untouched`.
  **It emits rulings and never edits the pendings file.** A real run invented this rule for itself, recording a stale survivor as *"reported, NOT edited"* because the file was owned by another session.
- **Its Step 4 Half B dossier**, from its own `PARKED` lines, at the density Step 4 already specifies: file and line, the number measured and how, the shape of the fix, the exposure left open, and a mark on any proof that cannot be re-run.
- Then `READY <slug>`, and its turn ends.

### Under `GO <slug> verify <branch>` — one fork at a time

The full gate suite through `gate.sh`, red-gate triage into the six lanes, migration confirmation against the remote ledger, commit, push. Then `RELEASE verify <branch>`, and the orchestrator grants the next fork.

**`LOCK verify` names the branch as its resource, always.** A real handoff records two permanently outstanding locks in `ledger.py sweep` that are false positives: both forks sent a bare `LOCK verify`, and a grant with no resource matches nothing, so the pairs can never close. `LOCK verify <branch>`, `RELEASE verify <branch>`.

**Why serialise at all.** `session-build` imposed this mid-run from a measurement — 12 logical CPUs at 71% load with another session on the machine — and recorded the reason: CPU contention returns *no* answer rather than a wrong one, and the natural misreading is that the red belongs to the fork's own branch. Across two runs it measured load average 80.61 peaking at 98.88 on ~10 cores, a `git push` stuck 43 minutes in its pre-push hook, and a lint-plus-typecheck that did not finish in 600 s on a branch touching no application code. It has already crossed into a real `session-end`: one run left its suite un-rerun because a peer held `LOCK verify` and the orchestrator vetoed retaking it.

**The orchestrator takes the same lock for its own post-merge union suite**, and logs the grant. That suite competes for the same cores. It is **not exempt from the rule it enforces**.

### Four consequences

1. **The orchestrator never enters a worktree.** It merges from the main checkout — `git checkout <default>`, `git pull`, `git merge --no-ff <branch>` — and runs `git worktree remove` from there. Two real runs chose exactly this and named the reason: worktree removal happens from the main checkout anyway, and staying out avoids the compound-bash restriction that applies inside one.
2. **No fork-side deploy.** Deploy runs once, at Step 8, after the last merge — already this skill's own rule, and it removes the shared-deploy-target hazard for free.
3. **The pendings file is written once**, by the orchestrator, from the N forks' rulings, and **committed on the last branch in merge order** before that branch merges. No extra branch, and nothing committed straight to the default branch. One run deviated toward this on its own, writing pendings on the single branch that owned the file because doing it per-branch *"would have created three conflicts in one file for no gain"* — and another paid that bill, conflicting on `PENDINGS.md` three times in one close-out.
4. **`handoff.md` carries `spec slug → agentId`.** Without it a fork cannot be addressed at all.

### Degradation, because the failure is on record

- **agentIds alive** → `SendMessage` revives each fork with its context intact.
- **agentIds dead, or this session restarted** → spawn a fresh fork whose dispatch points at disk: `handoff.md` plus `.superpowers/session-build/<RUN>/fork-<slug>.md`. It reads from disk and **never assumes a fork remembers anything.**
- **Forks unavailable entirely** → fall back to the sequential lane and say so in one line. `session-build` hit exactly this and ran `N = 1` twice, serially.

### A limitation, named rather than left to be discovered

*"Resolve from a measurement"* **is weaker for the last branch in merge order.** Entries touched by branches 1..N-1 are measured against a default branch that already carries those merges; the last branch's own entries are measured against its tree before merging. The residual exists in the per-branch lane too — it is not introduced here — but this lane is where someone will look for it.

## NEXT

`step-08-sync-and-cleanup.md` for the post-merge sync and cleanup, once every branch has merged.

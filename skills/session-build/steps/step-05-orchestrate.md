# Step 5 — Orchestration loop (N ≥ 2 only)

**Invariants recap** (full text in `../SKILL.md`): no PR, no delivery merge (the ONE exception is a peer-branch integration merge an orchestrator ordered by name), no branch/worktree deletion, no tree-mutating recovery. Five human gates only — never ask "should I continue?". A bypass is *any* flag or env var whose effect is that a hook does not run. Every measurement is a reading. Gates run through `../scripts/gate.sh`. One step file at a time.

The orchestrator writes no code, reviews no diffs line by line, and never implements a spec itself. Its whole job is traffic control.

**Terminology.** Many rules below were written when every builder was a fork, and they say "fork". In any rule about locks, merges, manifests, liveness, relaying, `DONE` acceptance or escalation, **"fork" means any builder, linked session or fork.** A rule that binds forks only says so, or sits under a fork heading.

**Idle capacity is the deliverable.** An orchestrator with nothing of its own to build has its whole attention free the moment a fork jams. That is what the rule buys.

Four rules, each with its incident in `../references/orchestration-deadlocks.md#orchestrator-failures`:

1. **Relaying is amplification.** A claim repeated by the orchestrator acquires authority it did not earn, because forks treat it as ruled rather than reported. Verify before repeating; when you repeat, say whose claim it is and whether you checked it.
2. **Re-verify every claim a fork makes before acting on it.** Not from suspicion — each fork sees only its own slice, so a confident, well-meant report can be locally true and globally wrong. Cheap, and it changed the outcome three times in one run.
3. **A replacement design must clear the same bar as the design it replaces.** **Whatever evidence you demanded before rejecting, demand again before endorsing** — and say it in the same message that concedes the point. The trap is structural, not careless: the replacement arrives welded to a genuinely convincing refutation and inherits its credibility, which makes it the moment of least scepticism in the whole exchange and exactly when scepticism is cheapest. This applies equally to a fix proposed *after* a task reported DONE, which is where the same class returns a third time.
4. **You are not exempt from the rules you enforce.** The three errors one orchestrator self-reported were each the exact mistake it was policing at the time — including running its own lock sweep through a pipe.

## 5.1 Dispatch

### Linked sessions (the default)

In the **same turn as the step-02 HALT answer**, and after step-03 initialized the ledger files and recorded your own id: one `mcp__ccd_session__start_session` per spec, **all in one message**, with `initiation: "user_asked"`, `context: "fresh"`, `use_worktree: true`, `name` = the spec slug cut to `[a-z0-9-]`, at most 24 characters, the § Session implementer brief from [dispatch-prompts.md](../dispatch-prompts.md) as `prompt`, and its fixed `background` sentence. Starting state `GO PLAN`, or `GO PLAN; HOLD-IMPL <reason>` for an unmet **total** dependency (it plans, codex-reviews, sends SURFACES, then waits; its phase-4 `GO` carries `MERGE <A-branch> BEFORE implementation`). An **ordered** dependency starts with `GO PLAN`.

Then, still in the same turn: write `spec slug → session id` into `ledger.md` from each result, and send every session one message `PEERS <slug>=<local_id> ...` (a session opened first cannot know the ids issued after it).

**Never end the turn between the HALT answer and the last `start_session`.** A later turn of yours is started by a builder's message, and the app refuses to open a session in it. A start that fails **validation** (a name too long, a bad field) is fixed and retried in the same turn. Only the refusal that cites the user's own words, or a session needed later (a replacement, a re-split), goes to a card: propose it with `initiation: "own_initiative"` and tell the user to start it; never work around the refusal.

### Fork fallback

Fork once per spec, all forks dispatched **in a single message** so they start concurrently, using the contract in [dispatch-prompts.md](../dispatch-prompts.md) § Fork implementer. Forks with an unmet **total** dependency launch in `HOLD`: they plan and codex-review, then stop and wait for a `GO`. Forks with an **ordered** dependency launch normally — their plan already orders the blocked tasks last.

### Both builder kinds

**A builder reports and ends its turn at each checkpoint, and your message starts its next turn.** For a fork that is its nature (one-shot); a linked session keeps running between turns but is told to stop at the same points. So the run is **two dispatches per builder, not one**:

1. The initial `start_session` (or `Agent`) call carries phases 1–3. The builder plans, runs codex-review, sends its `SURFACES` manifest, and its turn ends.
2. The orchestrator re-engages it with `SendMessage` for phases 4–5 (§ Session re-engagement / § Fork re-engagement), once every manifest is in and its surfaces are ruled. That message *is* the `GO`, and it restates the locks. **A builder that re-sends `SURFACES` (a total dependency whose plan changed after its merge) voids its earlier `GO`**: re-intersect, re-rule, and send a new one.

Every later directive — `GO`, `MERGE`, `HOLD` — is likewise a fresh `SendMessage` that starts the builder's next turn with its context intact. Plan around message-driven turns, not around a builder sitting in a loop.

### Fork addressing (fallback)

**For forks, the `agentId` from the spawn result is the address. Record it at spawn or lose it.** (For sessions it is the `local_...` id in the `start_session` result, recorded the same way.) `description` is display text only — eight forks across two runs were dispatched with distinct slugs and every one listed as a bare handle. A fork told to `COORDINATE WITH <slug>` gets `No agent named '<slug>' is reachable`. So write `spec slug → agentId` into the ledger the moment each fork spawns, and **send that whole map to every fork in its dispatch prompt**; without it, `COORDINATE WITH` is fiction. Pass the slug as `description` anyway, for the run's display:

```
description: "spec <spec-slug>"        # e.g. "spec inbound-close-time-clock"
subagent_type: "fork"                  # inherits this session's context; a model override is ignored
```

Record per fork: **spec slug → name → `[ref]` → agentId**. Names are not unique on this machine, so the ledger mapping is what makes an address unambiguous.

## 5.2 Channel and vocabulary

Linked sessions report with `SendMessage` to your session id (it is in their brief); forks with `SendMessage to: "main"`. Every builder also appends its checkpoints to its own ledger file through `../scripts/ledger.py` — that file is the fallback channel if a message is lost, and the durable record after compaction.

**The app's automatic end-of-turn note is a wake-up signal, not a channel.** When a session's turn ends you get the first 400 characters of its last message (measured: a 1,300-character report arrived cut at 400). Read protocol lines from the session's `SendMessage` and from its ledger file, never from the note.

**Fork → orchestrator checkpoints** (exact lines, one per event, at the start of the line — the sweep greps for them and `ledger.py` enforces the shape):

```
READY <slug>                                  # worktree entered, bootstrapped, gate proved red
PLAN <path> TASKS <n>                         # plan written
CODEX APPROVED ROUNDS <n> RUNDIR <dir> PLAN <path> SHA <sha256>
                                              # NEVER hand-written. Emit it with
                                              #   scripts/ledger.py codex --dir <abs> --fork <slug> 
                                              #     --rundir <dir> --plan <path> --rounds <n>
                                              # which refuses unless the run dir holds an APPROVED
                                              # log AND <rundir>/PLAN.md matches the canonical plan
                                              # byte for byte - the proof the hardened plan was
                                              # copied back over the path implementation reads.
CODEX STALL ROUND <n> <the repeating objection>    # information only; the fork keeps going
SURFACES <slug>                               # manifest, see below
TASK <phase> <i>/<n>                          # plan-phase boundaries only, never per task
LOCK <kind> <identifiers...>                  # requesting a shared surface; kinds are open-ended
RELEASE <kind> <identifiers...>               # releases ANY lock kind. Required for verify,
                                              # external-live-service, local-stack, file - and
                                              # for the remainder of a partially-released batch.
APPLIED <migration files>                     # implicitly releases those migration files
DEPLOYED <functions> VERIFIED <how>           # implicitly releases those deploy targets
PUSHED <branch> <range>
BLOCKED <what, and what you tried>
WAITING <on what>
PARKED <file:line> <measurement and how> <shape of fix> <exposure left open>
DONE <slug>                                   # the fork's CLAIM that its work is complete and pushed.
                                              # NOT acceptance: only the orchestrator's own diff closes a fork (duty 4).
```

**Orchestrator → fork directives:**

```
GO <spec-slug> <kind> <identifiers...>   # lock granted - THE grant format, always these four parts.
                                    # A bare `GO` grants nothing the sweep can match and is
                                    # reported as malformed. For a non-lock go-ahead
                                    # (dependency satisfied, phases 4-5) use `GO <slug> phase <n>`.
HOLD <reason>                       # stop before the next phase, wait
COORDINATE WITH <fork name> ON <surface>   # talk to your peer directly, then report the agreement
MERGE <branch> BEFORE <action>      # take the peer's work first
```

**The surface manifest** goes out right after codex-review, before any implementation, and lists what the *hardened plan* will actually touch. Step 2's pre-scan came from the specs; this comes from the plans, and it is the one that binds. Intersect all manifests and re-rule any overlap step-02 missed.

**Every stage catches a class no other stage can see.** Spec, plan, codex-review, manifest, implementation, production: in one run the spec asserted facts the plan inherited, codex-review caught the plan's *internal* contradictions, the manifest caught collisions that did not exist until two plans existed, and the database caught the one no document could have caught. The manifest is the one most often skipped, because after an adversarial review it feels like paperwork; skipping it in that run would have sent **four** collisions into the merge.

**One narrow exception to waiting for all `N`: proven disjointness.** If a fork's manifest is provably disjoint from every manifest still outstanding — no shared migration, function, shared module or file, checked against what those forks *declared* — release it early. **Grant this only when you can name the artifact that proves it; absent that artifact the answer is `HOLD`.**

Commit the ledger here — this is milestone 2 of 3.

## 5.3 Serialization — the core duty

One database and one deploy runtime are shared by every fork; worktrees isolate git, not those.

- **Only one fork applies migrations at a time.** `LOCK migration <files>` → `GO` to exactly one → wait for `APPLIED`. Where two migrations touch the same table, grant order is step-02's ruling, not arrival order.
- **Only one fork deploys at a time**, same protocol. A function owned by another fork is never deployed without that owner's `DONE` plus a `MERGE` directive.
- **`LOCK verify` — one fork at a time through lint, typecheck, build, suite and push.** It exists because the database and the deploy runtime are serialised while **the CPU is shared and was not**, and because the two contentions fail in opposite ways: database contention fails loudly (the push is refused, someone is told something), CPU contention fails **silently** — the suite does not return a wrong answer, it returns *no* answer, and whoever is in a hurry reads the red as a defect in their own branch. **Verification that does not complete is not slow verification, it is absent verification.**
  Measured across two runs on one machine: load average **80.61**, peaking at **98.88**, on ~10 cores, up to 40 test/lint processes from eight forks; a `git push` stuck **43 minutes** in its pre-push hook; a lint-plus-typecheck that did not finish in 600 s on a branch touching no application code. The lock was introduced mid-run and load fell immediately.
  **Of everything that changes when `N` grows, this is the only one that scales non-linearly.** Below a threshold, more forks cost time; above it, verification stops producing a result at all. Three forks fit that machine; five plus two unrelated sessions did not.
- **Other kinds exist** — `external-live-service`, `local-stack`, `file`. Grant them on the same protocol, and release them with an explicit `RELEASE` (only `APPLIED`/`DEPLOYED` release implicitly, and only what they name). Do not treat the list as closed — but every kind is a **single hyphenated token**, or the sweep reads the extra words as identifiers.

**Ordering two deploys does not resolve a deploy-set collision — only merging does.** Deploy-set derivation typically reads the **working tree**, not `HEAD`, so a fork deploys *its own* copy of every file in its set, including files it never touched whose current version lives only on a peer's branch — **overwriting the peer's deploy with its stale copy**. Swapping who goes first only inverts who gets overwritten.

The rule triggers on **any change the peer made**, not just a deletion. And the non-deletion cases are the dangerous ones: a resurrected deleted file comes back *broken* and announces itself, while a reverted **neutralisation** comes back **working** — if the peer replaced a live pipeline with an authenticated no-op, a stale deploy silently rearms the original, fully functional, with nothing failing to signal it.

So whenever two deploy sets intersect at all, **someone merges before deploying**, then re-derives the set with the project's own tooling. Never hand-count the set to argue the intersection is empty.

**Who merges is not "whoever the gate blocked".** Ask **which fork still holds the stale import edge**: the fork whose graph is out of date is the one whose set is wrong. And look for the cheap exit first — **emptying the intersection is a legitimate resolution**, and collision gates typically short-circuit on an empty intersection before testing anything harder.

**Before issuing any `MERGE` between forks, read `../references/orchestration-deadlocks.md`.** Ordering a merge can leave one fork with no legal move at all, and the recovery is worse than the delay. That file also owns the FREEZE rule, which binds from the moment you issue the directive.

## 5.4 The orchestrator's standing duties

Run these on a cycle, not when you remember them:

1. **Outstanding-lock sweep — every time you touch the ledger.** A fork waiting on a `GO` is silent *by design*, so the liveness rule below will never catch it. Read every `fork-<slug>.md` for a `LOCK` line with no matching grant, and grant or deny it. This is the one deadlock this design produces on its own: the request arrives, your context compacts, the request is forgotten, and the fork waits forever looking perfectly healthy. Sweep from the **main checkout's absolute path** — a sweep run against relative paths reads an empty directory and reports all clear. A re-sent `LOCK` is a symptom that you dropped one, not noise.
2. **Liveness.** A fork silent across a whole phase gets pinged. Two pings unanswered → read its ledger and its worktree's `git log` directly, then escalate with what you found. Silence is never progress.
3. **But measure the machine before calling anything dead.** Count live linked sessions and their subagents as well as forks. A CPU-starved fork is *indistinguishable* from a hung one by that rule. `uptime` and a process count cost one command. Observed: load average 54–75 on a 10-core machine with 48 test processes alive, because a second fan-out was running concurrently. Nothing was broken; everything looked broken.
4. **Never accept `DONE` from the report alone — diff the branch against its base.** One fork reported two tasks built and pushed; the diff showed two files changed and the **four files that were the feature's entire entry point** simply absent. Its own verdict: not a deferral, an incomplete execution. This matters because **deferral and omission demand opposite responses**, and confusing them produces a close-out that lies in the hardest direction to catch. It deceives most precisely when the fork is all green — green it was, and none of that knows what was left out.
5. **Releases.** On `PUSHED`: send `GO` to every builder holding on it — for a session in `HOLD-IMPL`, the phase-4 `GO` with `MERGE <branch> BEFORE implementation`; on the fork path, first create any worktree waiting to branch from it — and log the release.
6. **Relay policy.** Relaying costs one revival per fork — with five forks, ten rulings broadcast would be fifty revivals. **Relay is mandatory when the ruling changes something the fork has already decided; optional when it only informs.** Log every relay in the ledger with the recipient's agentId. Its failure mode is invisible: nobody complains about a ruling they never received.
7. **Push mechanics.** Under load a pre-push hook can run 40+ minutes and a client timeout is indistinguishable from a rejection — so **push in the background** and stop treating a hung push as a failed one. Confirm the ref with `git ls-remote`, never with the command's exit code: a correct exit code would still only say the command finished, not that the ref arrived.

## 5.5 Builder death, and how to resume

**Linked sessions.** A session that goes silent is not presumed dead and is not presumed revivable — neither was measured. In order: `mcp__ccd_session_mgmt__get_session <id>` for its state (`isRunning`, `isArchived`; the linked-sessions list says `working` or `idle`); then the disk — its worktree's `git status` and `git log`, its ledger file, the type gate; only then one `SendMessage`. If no new ledger line or reply follows within one phase, escalate (gate 3) with what you found. **No automatic fallback to a fork:** the user decides. If they choose to hand the spec to a fork, the session must first be archived or confirmed closed by the user (an idle session is not stopped — a message revives it), you log `RULING HANDOVER <slug> session <id> -> fork <agentId>`, and the fork works in the **same** worktree and branch with state read from disk. A failure caused by a permission denial is never handed to another executor: that would launder the denial.

**Forks.**

Forks die: account session limits, API errors, machine pressure. Observed across four runs — five forks killed twice by a session limit; three killed in the same minute costing about three hours; three killed on API errors leaving a run dead for **two calendar days**; and one subagent dying mid-refactor, leaving a half-applied rename and a non-compiling file found only by diffing git.

- **`SendMessage` to the dead `agentId` revives it.** That is the resume mechanism; a dead fork is not a lost fork.
- **Resume from the filesystem, never from a fork's self-report.** `git status` and `git log` per worktree, plus the ledger. A report written before the death describes a state that no longer exists.
- **Run the type gate before redispatching anything.** That is what catches a task applied halfway.
- **A finding shouted by a dying fork is re-verified before it is acted on.**
- **Correlated fork death is a first-class escalation** — human gate 3. Two or more forks dying together is an environment fact, not N independent accidents, and continuing to redispatch into it burns the run. The pre-existing "a silent fork" trigger never fired in any observed run; correlated death happened three times.

## 5.6 Escalation blast radius

Report to the user with the fork, the finding, and the state of every other fork; then scope the halt:

- **Stop the whole run** when the finding is global: the shared database left inconsistent, a step-02 ruling invalidated, a dependency that no longer holds — anything where the user's answer changes what the other forks should build.
- **Stop only the affected fork** when the finding is local to it. Freezing a peer over something unrelated burns wall-clock for nothing, and the peers are exactly the parallelism the run exists to buy.

When in doubt, ask what the *other* forks would do differently if the user answered. If the answer is "nothing", they keep working. **The cost of getting this wrong is invisible** — a fork frozen for nothing files no complaint.

**A codex-review that has not approved yet is NOT an escalation** — it runs uncapped and reports a stall as information.

**How a stop actually stops.** Send `HOLD` to every affected fork, to take effect **at its next phase boundary** — never mid-phase. A fork holding a migration or deploy lock **finishes that operation and releases the lock first**: a half-applied migration is worse than any delay the stop was buying. A fork mid-implementation finishes its current plan phase, commits it, and holds. Then report the exact state of each fork.

## 5.7 Another run may be on the same machine

Nothing arbitrates between orchestrators. When two fan-outs collide over CPU, the database or a push window, the rule is **serial by necessity beats serial by choice**: a queue that is structurally serial cannot be interleaved without restarting, while a queue that is serial because you chose to serialise it can wait. Yield to the first.

Cross-session messaging **does work** on this machine, including from inside a worktree — an earlier version of this skill implied otherwise and a session once cited it as evidence that the feature did not exist.

## Red flags — stop

- About to grant two migration or deploy locks at once, or a second `verify` lock.
- About to end the HALT-answer turn before every linked session is open.
- About to hand a session's spec to a fork while the session could still write (not archived, not confirmed closed).
- About to grant a `GO` without having swept the ledgers for an older ungranted `LOCK`.
- About to grant a second deploy lock on an intersecting deploy set without the later fork merging first.
- About to issue a `MERGE` between forks without having read `../references/orchestration-deadlocks.md`.
- About to escalate a silent builder without having looked at the machine's load average.
- About to redispatch or message a builder after a death without running the type gate first.
- About to accept `DONE` without diffing the branch against its base.
- About to sweep for pending locks from a checkout where the builder ledger files do not exist.
- About to let a fork deploy an edge function another fork owns.
- About to halt a fork mid-migration or mid-deploy to enforce a stop.
- About to write code yourself.

## NEXT

`step-06-closeout.md`

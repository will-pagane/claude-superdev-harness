# Step 2 — Scope, dependencies, collision plan

**Invariants recap** (full text in `../SKILL.md`): no PR, no delivery merge (the ONE exception is a peer-branch integration merge an orchestrator ordered by name), no branch/worktree deletion, no tree-mutating recovery. Five human gates only — this step **is** gate 2, and it is the last one before the run goes autonomous. A bypass is *any* flag or env var whose effect is that a hook does not run. Every measurement is a reading. Gates run through `../scripts/gate.sh`. One step file at a time.

This is the orchestration design. Do it before any branch exists.

**Terminology.** Many rules below were written when every builder was a fork, and they say "fork". In any rule about locks, merges, manifests, liveness, relaying, `DONE` acceptance or escalation, **"fork" means any builder, linked session or fork.** A rule that binds forks only says so, or sits under a fork heading.

## 2.1 Confirm the spec list

In one message. If the user named files, use exactly those.

Open the ledger now: `RUN_ID` = `<YYYYMMDD-HHMM>`, directory `.superpowers/session-build/<RUN_ID>/` in the **main checkout**, and write the project profile from step-01 into it as the first entry. Use `../scripts/ledger.py`.

**If any spec in scope came out of the project's pendings file, record which entries — verbatim — before you go further.** One `PENDINGS-SOURCE` ledger line per spec, quoting each entry's heading exactly as it appears in the file:

```
scripts/ledger.py append --dir <abs> --type PENDINGS-SOURCE   --text "<spec-slug> consumes: '<entry heading 1>', '<entry heading 2>'"
```

Carry the same list into `handoff.md` at step-06. **This is the only thing that lets `/session-end` close those entries by NAME instead of guessing from a diff**, and the guess is what fails: a user who starts a run *from* the pendings file routinely finds the same items still sitting there after the close-out. Grepping a diff finds an entry that names a file you touched; it does not find the entry that describes the *behaviour* you just fixed and names no path at all.

Recording the source is not a promise to close it. A spec can consume an entry and only half-close it, and the honest close-out then rewrites the entry rather than deleting it — but it cannot do either if nobody wrote down which entry the work came from.

## 2.2 Dependency graph — and expect it to be boring

For each ordered pair, classify in plain prose.

**This classification is repair for a bad cut, not the main event.** A run whose specs were cut along file surface classified ten pairs and wrote one word, *independent*, for all of them, because that cut produces independence by construction. If most pairs come out entangled or ordered, stop classifying and go back to the decomposition — you are describing a problem you could have avoided.

Two things matter more than the taxonomy: **the acyclicity check**, and **lock serialisation, which is orthogonal to dependency** — three mutually independent specs still queue for the same migration mutex.

A dependency is temporal, not spatial. **Every tier keeps its own branch and its own worktree.** A fork that needs another's code cannot implement before that code exists, so sharing a directory buys parallelism the dependency itself forbids, while importing `index.lock` contention, verification that reads a neighbour's half-written files, and working-tree gates that fail on someone else's breakage.

- **Independent** — no shared surface. Fully parallel. **Verify this transitively before believing it.** Two specs that name no file in common are still a single **deploy unit** if one modifies a bundled shared module and the other touches *any consumer of it — including deleting that consumer*. A bundled module is copied into every consumer at deploy time, so the deploy set is computed through the import graph, not from the file list either spec wrote. Misfiled as `Independent`, this pair deadlocks late. Treat it as `Ordered` at minimum, with the deploy ordering settled here rather than discovered later.
- **Ordered** — B needs *something* of A's before it can finish: an interface decision, or code for some of B's tasks. Same answer either way, which is why this is one tier and not two: B branches from the default branch, **orders its plan so every dependency-free task runs first**, and puts the rest behind a single marked merge point. The orchestrator relays the interface decision when there is one, and sends `MERGE <A-branch> BEFORE <task>` when A reports `PUSHED`. B builds while A builds instead of idling.
- **Total** — B imports A's code wholesale, or B's migration assumes A's schema, and almost nothing in B stands alone. **B's branch is created from A's branch**, after A reports `PUSHED` — so integration costs nothing. B still plans and codex-reviews in parallel, from the default branch, while it waits. **With linked sessions this becomes merge-at-grant**, because B's session can only be opened at dispatch: B branches from the default branch, commits only plan and review files, and merges A's branch when its phase-4 `GO` arrives, before any implementation commit, then re-checks its premises (session contract).
- **Entangled** — the two would have to edit the same code at the same time to make sense of each other. That is not a dependency, it is a decomposition error: **fold them back into one spec** with one fork, which implements them serially. Two agents in one working directory is never the answer.

**Decompose by where the diff lands, not by theme — this is what decides whether `N` scales.** Cut along **file and deploy surface** and the manifests come out nearly disjoint by construction, so the intersection is `N` cheap membership checks; cut along topics and it is genuinely `N²` arbitration. **Splitting what lands in the same place buys a merge order, not parallelism.**

**The graph must be acyclic.** Walk it and say so explicitly. Any cycle — directly or through a third spec — is `Entangled` by definition: fold its members into one spec. A cycle left in the graph deadlocks the run *late*, after both forks have planned and built.

**The graph predicts sequence, not entanglement.** It tells you who *needs* whom; it cannot tell you who will end up *containing* whom. Containment is produced later, by the first merge between forks, and it decides whether the run delivers N reviewable branches or one — **so the count you promise here is a forecast, not a commitment.** Say that to the user when you present the order, and say it again at close-out if the number moved.

Both arguments in full: `../references/collision-precedents.md`.

## 2.3 Surface pre-scan — list, do not rule

From the specs alone, list per spec: tables and migrations, edge/serverless functions, shared modules, frontend routes/hooks. **Then stop.** Do not spend the round producing rulings from it.

A spec says what to build, not which files the build will touch — so most rulings made here get redone from scratch by the manifest intersection at step-05, and the collisions that actually bite (a shared hook, a package manifest, a config file) are invisible from the specs entirely. The pre-scan earns its place for exactly **one** question: *does any pair share a bundled module or its consumers?* That one is worth answering now, because it is the one that deadlocks late.

**Ask the transitive question explicitly, before any plan exists:** *does any spec touch a bundled shared module?* If one does, every consumer of that module is contested surface for this run — mark them all now, **including consumers another spec only intends to delete**. Answer it by hand, because no tool will: cross the shared-module imports on the neighbouring branches against the functions your own specs deploy, and record the intersection, empty or not.

**Feed the answer back into the decomposition, not only into the rulings.** The question is not *"do these specs share a file?"* but *"does the import graph join them?"* — and when it does, they are not two deliverable specs with a surface to arbitrate, they are one spec.

Everything else waits for the manifests. Ruling on a hypothesis costs a round and produces decisions that do not survive contact with the plans.

**The four rulings worth making here, when the pre-scan does surface one:**

| Overlap | Ruling |
|---|---|
| Same edge function in two specs | Assign it to exactly one fork. The other fork's change either moves into the owner's plan, or waits for the owner to push and merges that branch before touching it. |
| One spec removes code, another modifies a shared module it consumed | **The removal deploys first, and alone.** It is the only one whose deploy *shrinks* the import graph. Order it the other way and the remover ends up waiting for a branch that now contains it, and can never deploy on its own. |
| Same table in two migrations | Order them. The later is written against the earlier one's schema and is applied only after the earlier is confirmed applied. |
| Same source file | Prefer moving the change into one spec's plan. If genuinely both, order them and make the second fork merge the first's branch. |

If you cannot defend a transitive ruling, read `../references/collision-precedents.md`.

## 2.4 Lock plan

Lock kinds are **open-ended but must be single hyphenated tokens** — `external-live-service`, not `external live service`, which parses as kind `external` holding the identifiers `live` and `service` and collides with every other `external …` lock. The canonical set is `migration`, `deploy`, `verify`, `file`, `external-live-service`, `local-stack`; a run inventing another follows the same one-token rule and `ledger.py` warns when it does not. Add at least:

- **`external-live-service`** — a key-value store, a payments provider, an analytics endpoint, any third-party production surface. Observed: a fork probed a **production** key-value service because the dispatch enumerated only migrations and deploys, so the fork reasonably concluded nothing else needed a lock. The gap was the dispatch's, not the fork's.
- **`local-stack`** — a shared local database container. Starting one that is already running **silently reuses the previous holder's schema**, so a fork can verify green against another branch's database.

A plan may legitimately *require* a lock on an external service. It must request it at plan time, not discover it at execution.

## 2.5 Run the project's own collision gate

If the project ships one (`npm run collide` or equivalent), run it now, through `../scripts/gate.sh`. It sees what a reading of the specs cannot.

**Check that the artefacts you are about to promise are committable at all.** One run promised to collect every codex-review run directory onto the default branch and had to revoke it in front of five forks, because that directory was listed in `.git/info/exclude` and collecting it would have needed a forced add the project forbids. This skill treats plans and review transcripts as committable by default; confirm that against the repo's ignore and exclude rules **before** promising, not after.

## 2.6 Decisions file and SDD marks (N ≥ 2)

A linked session inherits nothing from this conversation. Whatever the brainstorm decided and the specs do not state reaches it only through this file, so write it before the HALT: `<ledger dir>/DECISIONS.md`, through `Write`, with three parts:

1. **Per spec, every decision or preference from the conversation that the spec does not state explicitly.** Final values only; where the conversation reversed itself, write the final value and name the dead one (*"37 days, not 30"*), so nobody resurrects it. Read the specs while writing it: a decision a spec already states does not belong here.
2. **The rulings of §2.2-§2.4:** dependency classes, merge points and order, shared files and who changes what, the lock plan.
3. **The branch name step-03 will use for each spec.** Builders create exactly that name; they never invent one.

Observed in the 2026-10-15 benchmark: a fresh builder given this file matched an inheriting fork on every hidden test; the one without it lost exactly the fact that could not be guessed from the spec and the code. The file also costs the fork path nothing, so write it whichever builder kind the run will use.

**Mark each spec `sdd: on` or `sdd: off`.** The default is off: in the same benchmark SDD cost about four times as much and three times as long with no quality gain. Mark it on only when the spec touches money, fiscal documents, authentication or authorization, RLS, or a destructive migration, or the user asks. The marks exist only for `N ≥ 2` linked sessions; **`N = 1` keeps SDD mandatory** (step-04), and a fork cannot run it at all.

For `N = 1` the file is optional: the builder is this session.

## 2.7 Present and confirm — HALT

Present the spec list, the dependency graph with the acyclicity statement, the lock plan, the project profile, and for `N ≥ 2` the `DECISIONS.md` path, the SDD marks, and the builder kind: *"abrirei N sessões ligadas, uma por spec"* (or the fork fallback, with the reason).

> **HALT.** Options: [A] proceed as presented — [B] change the scope or order, then re-present — [C] fold two specs together and re-derive. Resume only on the user naming one. Do not proceed on silence.

**For linked sessions, the answer [A] is also the app's authorization to open them, and it is only good for the turn it arrives in.** The app opens a session only in a turn carrying the user's own words; a turn started by another session's message is refused. So after [A], run step-03 and step-05 §5.1 to the last `start_session` call **without ending the turn**. Every session the run will need opens now, including the ones that will wait on a dependency.

This run has **five** possible human gates, and this is the last one guaranteed to fire. Say which ones remain rather than promising a duration: *"everything between here and the close-out happens without asking, unless an escalation fires."* Do not promise "one continuous pass" — that is a duration claim, and runs break it.

## Red flags — stop

- About to confirm a dependency graph without having checked it for a cycle.
- About to classify a pair `Independent` on file lists alone, without asking whether the import graph joins them.
- About to open a branch before this step's HALT has been answered.
- About to present the HALT for N ≥ 2 without `DECISIONS.md` written and the SDD marks stated.
- About to promise a number of reviewable branches as a commitment rather than a forecast.

## NEXT

`step-03-isolate.md`

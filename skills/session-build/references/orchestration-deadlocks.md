# Orchestration deadlocks — read before issuing any MERGE between forks

**Load this when:** you are about to order a merge between two forks; or a fork has been silent past its liveness window; or a lock has been outstanding across two status cycles; or a collision gate refuses for a reason naming another branch's work.

**Do not load it on a run that has ordered no inter-fork merge.** In twenty observed runs the precondition below never once occurred — which is not evidence it will not, only evidence that this file belongs behind a trigger rather than in the resident core.

The operational duties that grew out of this incident — FREEZE, `COORDINATE WITH`, the slug→agentId map, selective relay, liveness, the load-average check, the outstanding-lock sweep, never accepting `DONE` from a report, background push, releases, escalation blast radius, and how a stop stops — are **numbered rules in `../steps/step-05-orchestrate.md`**, not here. This file is why they exist.

## The ledger paths that make the sweep real

Before the incident itself, the two ledger facts it depends on. `../scripts/ledger.py` now enforces both, so these are background rather than instructions — but a run that hand-writes a ledger inherits the bugs.

### Say WHICH checkout, or the sweep silently reads nothing

**This path is ambiguous and the ambiguity produces a false green on the run's most important safety rule.** Each fork works in its own worktree, so a relative path puts `fork-<slug>.md` **inside that worktree** — invisible from the main checkout where the orchestrator stands. Verified in a live run: the main checkout held only `ledger.md`, while the fork files sat in the worktrees, alongside a *stale copy* of `ledger.md` inherited from the branch base and easily mistaken for the current one.

The consequence is the bad part. The outstanding-lock sweep tells the orchestrator to read every `fork-<slug>.md` for an ungranted `LOCK`. Run from the main checkout against relative paths, that sweep reads an **empty directory and reports no pending locks** — confidently, and about the one deadlock this design produces on its own.

**Forks write to the main checkout's path, given absolutely in the dispatch prompt.** Not one of two acceptable options — the two were run side by side and only this one works.

Two independent runs happened to resolve the ambiguity differently, which produced a controlled experiment neither intended. The run that passed the **absolute main-checkout path** ended with all five fork files in the main checkout and every worktree empty; its orchestrator swept seven times across the run, and one of those sweeps caught an ungranted `LOCK` it had genuinely forgotten — the exact deadlock the rule exists to prevent. The run that let the path fall out relative ended with the fork files scattered in the worktrees, the main checkout holding only `ledger.md`, and a stale copy of `ledger.md` sitting in each worktree ready to be mistaken for the live one.

The asymmetry is the argument: the relative arrangement is not merely different, it demands that a busy orchestrator remember to sweep `N` worktrees with explicit paths, to recover information the absolute arrangement hands over for free. Use worktree-local files only if a harness leaves you no choice, and then write the explicit sweep paths into the ledger so the next session inherits them.

**The corollary is counter-intuitive and belongs in the dispatch prompt.** With the absolute path, the fork ledger lives on the default branch — where forks are barred from committing. So **`"the fork commits its ledger at most twice"` cannot be asked of a fork at all; the orchestrator commits those files**, and it has to know that before it promises otherwise.

**Check that the artefacts you promise to collect are committable at all.** A run promised to gather every `codex-review` run dir onto the default branch and had to revoke it in front of five forks: `docs/codex-review/` was listed in `.git/info/exclude`, so collecting it would have needed a forced add the project forbids. This skill treats plans and review transcripts as committable by default; confirm that against the repo's ignore and exclude rules **before** promising, not after.

Context does not survive compaction; the ledger does. On resume, trust the ledger, `git log` and `git worktree list` over recollection, and restart at the first phase with no completion line.

### Record dated readings, not only decisions

**A ledger full of rulings still loses the run's state.** Reported by an orchestrator that composed its whole close-out from the ledger without difficulty — rulings, locks, grants, escalations, all there — and then had to reconstruct three things anyway:

- **commit ranges**, dug out of git afterwards;
- **topology over time** — it had recorded the *current* topology, never the series. And topology is precisely what expires: it measured three times and got three different answers, and a merge instruction it had already sent was wrong within the hour;
- **who was blocked on whom, and since when** — reconstructed from memory.

So: **write down the measurement together with the instant it was taken, not just the decision it justified.** `Merge order: A → B → C` is useless without `measured 20:14`. A reading with no timestamp is an instruction with an expiry date that does not say what it is — and the reader cannot tell a fact of the run from a fact of that minute.

### The sweep only works if the fork ledger has the format it greps for

**A defect in this skill, found by an orchestrator whose sweep silently found nothing.** The forks wrote their `fork-<slug>.md` in **prose**, which nothing forbade; the pending-lock sweep greps for checkpoint lines like `^LOCK `; the grep matched zero, and **zero was indistinguishable from clean**.

Either the format is mandatory or the sweep does not exist. Make it mandatory: the checkpoint vocabulary goes into the fork ledger **verbatim, one per line, at the start of the line**, and prose commentary goes underneath. Then make the sweep defensive anyway — search for the word anywhere in the file, not only anchored, and cross-check the count of `LOCK` lines against the grants recorded in `ledger.md`. A sweep whose empty result cannot be distinguished from a healthy one is the false green this whole design most needs not to have.


---

#### The merge-direction deadlock

**The worst failure this skill has recorded, and the rule that caused it is the one directly above.** Ordering a merge between forks can leave one of them with no legal move at all. Read this before issuing any `MERGE` directive.

**The mechanism: a collision gate's resolution predicate is directional.** A typical one asks *"is the peer's branch an ancestor of mine?"* — it clears from the side that **contains**. So the merge that clears the gate for the fork doing the merging simultaneously creates a gate the **merged** fork can never clear: from that moment its entire body of work sits inside the merger's deploy set, and only the containing side satisfies the ancestry test.

Observed end state: a fork **colliding with a copy of itself**. Every object the gate listed was declared only in that fork's own migrations, and the peer's migration referenced none of them. And because the same gate ran on pre-push, it could neither deploy nor push. No legal move.

So, before ordering any merge between forks:

1. **Read the direction of the gate's predicate, and decide the consequence on purpose.** If it clears from the containing side, then *whoever merges is the only one who can deploy the shared surface* — so the ruling must be stated as a pair: **the receiving fork deploys the shared surface, and the merged fork deploys nothing.** Ordering the merge without deciding that second half is what manufactures the impasse.
2. **A merge imports the peer's unapplied migrations too.** Where the migration CLI has no per-file selection, the merged-into fork then cannot apply its own migration without applying the peer's in the same push — which may be destructive. **A merge between forks is only safe once the peer's migrations are already applied.** Otherwise the peer applies first, or the merge waits.
3. **Map which gates each path actually traverses before concluding a fork is stuck.** Deploy, push and migrate are different paths through different gates. In the observed case deploy and push were both closed while *apply* stayed open, because the migration CLI never runs the collision gate — and that open path is what unblocked the run. "This fork has no move" is a claim to verify per path, not per fork.
4. **Diagnose by provenance, never by the gate's list.** Once a peer contains you, everything you declared appears in its set, so the listing looks like a real conflict. Trace which file actually *declares* each listed object. Without that, the natural reading is "there is a genuine conflict" and the natural reaction is to merge — the exact move that deepens the hole.

**Green is a timestamp, not a property.** An ancestry predicate compares **HEADs**, not bodies of work, so its answer is true *at the instant it was measured* and silently false afterwards. Nothing notifies you. In the observed run the merged fork went green, the peer made **one commit**, and it was red again with no one aware — and the commit that broke it was a **ledger commit**. Documentation. Not code, not a migration, not config. *The least suspicious commit of all is the one recording why you stopped committing.*

This is not a gate lying, which is the failure the gate-trust rules cover. It is a **true measurement going stale**, and it needs its own discipline:

- **Measure immediately before use, never earlier.** Record the gate's exit code right before the push or deploy it authorises — that is the only moment it means anything. One collected before a batch of other checks, or "earlier in the phase", authorises nothing.
- **Re-confirm containment at the moment of use.** *"I merged, therefore I am clean"* is false as soon as the peer breathes. Verify the ancestry again; do not trust that the merge happened.
- **Once a merge between forks is ordered, the merged fork FREEZES — and the freeze is absolute.** Not "no code commits": **no commits.** Docs, ledger, `.gitignore`, a typo fix. The predicate compares HEADs, so **the content is irrelevant** — the most harmless commit of the run is exactly as fatal as the riskiest. State it with the cases named, and state no exceptions: whatever exception the skill lists is the one someone will reach for, and the exception people invent unprompted is *"surely the paperwork is fine"*.

  It is not. In the observed run the fork that broke the window was the same fork that had **warned about it one message earlier** — it flagged the instability, then committed the warning to its ledger. Its own conclusion is the maxim worth keeping: **a freeze that permits "just the paperwork" is not a freeze.** The lesson is not that the rule was unknown.

  This is where the ledger cadence rule stops being an economy and becomes a **correctness requirement**: during a containment window, *write to the file and do not commit* has nothing to do with saving hook runs.

- **The other half, without which the freeze becomes paralysis: working-tree churn is allowed; commits are not.** A frozen fork may still need to move a great deal on disk — restoring a peer's migration files into the directory so its own migration can be applied, then deleting them again. That churns the tree heavily and **does not move `HEAD`**, so it is fully compatible with the freeze. Say both halves in the same breath, or a fork that has been told to freeze will stop touching the disk out of caution and block on work it was always free to do. Worth writing into its ledger deliberately, too: seven of someone else's migrations appearing during a declared freeze looks like a violation and is not.
- **Design the closing sequence as a commit-free window.** The shape that works: peer pushes and freezes → container merges → container runs its gates → container pushes, **with no commit at all between the merge and the push**. A commit from either side inside that window reopens it. If the skill has two forks contain each other, this only closes when it is genuinely the last thing each of them does.

**The resolution pattern that worked:** the **containing** fork deployed the **contained** fork's targets. The bodies were byte-identical, the container's gate was clean, and it was substantively the same deploy. The contained fork deployed nothing, merged nothing, and bypassed nothing; it resumed at the next stage through the still-open path.

**And three tempting moves that were refused, each for a reason worth keeping:** editing the deploy wrapper to get past its own gate; having the contained fork merge the container, which turns the gate green by making true the very thing it guards against; and having the container apply the peer's destructive migration, when a destructive migration should be pushed by the session that can actually diagnose it.

- **Assert on behaviour, not on file layout.** A post-merge check written against one plan shape breaks when the plan changes shape, and it breaks *green-looking*: "the directory must not exist" is correct while the plan deletes and wrong the moment the plan switches to stubbing, failing on a perfect merge. Assert what the deployed code must now *do* — the body contains the neutralised marker, the dead module is no longer imported — so the check survives the plan changing its mind.
- **A collision the orchestrator cannot resolve by ordering** — two forks that genuinely need to edit the same function body — is resolved by `COORDINATE WITH`: the two forks agree on one owner and one merge point, report the agreement, and the orchestrator records it in the ledger. If they cannot agree, escalate to the user.
  **This only works if the forks can address each other, and by default they cannot.** Forks list as bare handles rather than names, so a fork told to `COORDINATE WITH <peer>` has no way to resolve that peer — and the correct behaviour, refusing to fire blind at a guessed handle, costs the orchestrator a relay round-trip instead. Observed exactly that. **Send every fork the full `spec slug → agentId` map in its dispatch prompt**, and send an updated line whenever it changes. It costs one paragraph and it is the difference between peer coordination being written down and it being reachable.

**Relaying a ruling costs one revival per fork, so decide deliberately who needs it.** With five forks, ~10 post-dispatch rulings would be 50 revivals if broadcast. The orchestrator that faced this relayed **selectively**, which was right — but note that the judgement is unwritten and its failure mode is invisible: **nobody complains about a ruling they never received.** The line to hold: **relaying is mandatory when the ruling changes something the fork has already decided; optional when it only informs.** When in doubt, relay — a wasted revival is cheap next to a fork building on a superseded decision.

**Another run may be on the same machine, and nothing arbitrates between orchestrators.** When two fan-outs collide over CPU, the database or a push window, the rule that settles it is **serial by necessity beats serial by choice**: a queue that is structurally serial — each fork must merge the previous one for an ancestry gate to clear, and the containment breaks on every commit — cannot be interleaved without restarting, while a queue that is serial because *you* decided to serialise it can simply wait. Yield to the first. Two orchestrators negotiated exactly this and the rule held; without it the argument has no principle in it, just whoever asks louder.

**Liveness.** A fork that has sent nothing across a whole phase gets pinged. Two pings unanswered → read its ledger file and its worktree's `git log` directly, and escalate to the user with what you found. Silence is never treated as progress.

**But measure the machine before calling anything dead.** A CPU-starved fork is *indistinguishable* from a hung one by this rule: branch heads frozen, sessions alive, no output, no error anywhere. Under contention the silence-across-a-phase test gives a guaranteed false positive, and the one number that separates the two cases is the one nobody thinks to look at. `uptime` and a process count cost one command; run them before escalating.

Observed and independently confirmed: **load average 54–75 on a 10-core machine, with 48 test/lint/typecheck processes alive.** Not from one run — a second `session-build` fan-out was running concurrently on the same machine, and eight forks in total had converged on their verification phase at once. Nothing was broken. Everything looked broken.

**Outstanding-lock sweep — do this every time you touch the ledger.** A fork waiting on a `GO` is silent *by design*, so the liveness rule above will never catch it. Read every `fork-<slug>.md` for a `LOCK` line with no matching grant, and grant or deny it. This is the one deadlock this design can produce on its own: the request arrives, your context compacts, the request is forgotten, and the fork waits forever while looking perfectly healthy. The ledger is the only record that survives — trust it over what you remember granting. Forks are instructed to re-send an ungranted `LOCK`; a re-send is a symptom that you dropped one, not noise.

**Never accept `DONE` from the report alone — diff the branch against its base.** A fork's words are not evidence about a fork's branch, and the gap is not dishonesty. One reported two tasks built and pushed; the diff showed two files changed and the **four files that were the feature's entire entry point** simply absent. Its own verdict afterwards: *"not a deferral, an incomplete execution."*

This matters because **deferral and omission demand opposite responses** — one becomes a `CUT` with a recorded reason, the other becomes "finish it" — and confusing them produces a close-out that lies in the hardest direction to catch: a `CUT` section that reads like a decision and was actually forgetting. One command prevents it: diff against the merged base and check the plan's files exist. And it deceives most precisely when the fork is **all green**, because green it was — tests passing, lint at ceiling, typecheck clean. None of that knows what was left out.

**Push mechanics the rest of this skill assumes and should not.** Under load a pre-push hook can run for 40+ minutes, and a client timeout is indistinguishable from a rejection — so **push in the background** and stop treating a hung push as a failed one. Then confirm the ref with `git ls-remote`, never with the command's exit code: as one fork put it, *a correct exit code would still only say the command finished, not that the ref arrived.*

**Releases.** When a fork reports `PUSHED`, immediately: create any worktree that was waiting to branch from it, send `GO` to every fork holding on it, and log the release.

**An escalation stops the forks it affects — and only those.** Report to the user with the fork, the finding, and the state of every other fork; then scope the halt to the blast radius:

- **Stop the whole run** when the finding is global: the shared database left inconsistent, a Step 2 ruling invalidated, a dependency that no longer holds, or anything where the user's answer changes what the other forks should build. Holding everyone is right when continuing would mean building on a premise under review.
- **Stop only the affected fork** when the finding is local to it — its own gate, its own failing task, its own blocked deploy. Freezing a peer over something with no relationship to it burns wall-clock for nothing, and the peers are exactly the parallelism the run exists to buy.

When in doubt, ask what the *other* forks would do differently if the user answered the question. If the answer is "nothing", they keep working.

**The reason this rule stayed wrong for so long is that its cost is invisible.** A fork frozen for nothing files no complaint and leaves no mark; only the escalation that *should* have stopped everyone gets remembered. An orchestrator with two escalations — one touching three of five forks, one touching a single fork — held only the affected ones both times and was right both times, and would have idled two forks for nothing had it obeyed the old wording literally.

**A codex-review that has not approved yet is NOT an escalation at all** — it runs uncapped and reports a stall as information, never as a request.

**How a stop actually stops.** Send `HOLD` to every fork, to take effect **at its next phase boundary** — never mid-phase. A fork currently holding a migration or deploy lock **finishes that operation and releases the lock first**: a half-applied migration or a half-deployed function set is worse than any delay the stop was trying to buy. A fork mid-implementation finishes its current plan phase, commits it, and holds. Then report the exact state of each fork: what it completed, what it holds, what it was about to do.


---

## orchestrator-failures

**Triggered from step-05.** The four rules there are compressed; these are the runs behind them.

**Idle capacity is the deliverable.** Reported from a run that hit a hard deadlock: the orchestrator never had to choose between orchestrating and building, so when a fork jammed it had its entire attention available to diagnose — reading the gate scripts, reading the deploy-set derivation, running the same download twice to settle a disputed claim. Had it been implementing a spec of its own, the jam would have sat untouched until it finished what it was doing.

**The orchestrator is not exempt from the rules it enforces — and it fails at them in a characteristic way.** Three self-reported errors from one run, each the orchestrator committing the exact mistake it was policing: it instructed a fork to narrow a deploy set in a way the script does not support, **without having read the script first**; it relayed *and amplified* a fork's incorrect claim, nearly writing a false statement into project documentation; and it ran its own pending-lock sweep through a pipe, where the status was swallowed and "empty directory" became indistinguishable from "no matches" — the very trap it had spent the day warning others about.

**Re-verification is not suspicion.** In the observed run all three forks were reliable and the problem was never dishonesty. It is that each fork sees only its own slice, so a confident, well-meant report can be locally true and globally wrong. Re-checking is cheap — a query, a grep, one command re-run — and it changed the outcome three separate times: a documentation "fix" that would have deleted a true warning, a deploy scope that was impossible as the orchestrator itself had instructed, and a containment state that had already gone red again.

**A replacement design must clear the same bar as the design it replaces — the single most valuable rule in this family, and it nearly cost a production outage.**

An orchestrator rejected a change from its own spec, **demanding a survey of legitimate callers** before it would accept it. The fork did the survey and won the argument: the change would have dropped 24 access policies across 15 tables. It then proposed a different mechanism — and **the orchestrator endorsed that one on the spot, without asking for the survey it had just insisted on.** The replacement was wrong in the same way: two functions pass third-party ids deliberately, and the new mechanism would have broken task assignment. The adversarial reviewer caught it; the orchestrator did not.

The trap is structural, not careless. **The replacement arrives welded to the refutation of the original**, the refutation is genuinely convincing, and so the new design inherits the credibility of the argument that killed the old one. That is the moment of least scepticism in the whole exchange — and exactly when scepticism is cheapest, because nothing has been written yet.

A later run quoted this rule back nearly verbatim while catching itself, which is the best evidence it works: *the proposal arrives soldered to a correct refutation and inherits its credibility. It is the moment of least scepticism in the conversation.*

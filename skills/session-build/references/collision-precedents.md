# Collision precedents — the pre-scan argument, in full

**Load this when:** the transitive question in step-02 has an answer you cannot defend, or a collision ruling you are about to make would let two specs deploy the same surface.

Step 2 keeps the rule; this file keeps the argument, because two independent runs disagreed about the pre-scan and the disagreement resolves in a way worth reading once.

**One run found the pre-scan produced nothing.** Every ruling it made was redone from scratch by the manifest intersection, and none of its three real collisions — a shared hook, a package manifest, a config file — was visible from the specs at all, because **a spec says what to build, not which files the build will touch.**

**The other found it indispensable** — but for a single question, not for its rulings. That question is below, and it is the reason step-02 still runs a pre-scan at all.


   So the surviving value is **one transitive question, asked here because nothing later can ask it**: *does any spec touch a bundled shared module?* If one does, mark **every consumer** of that module as contested surface now, including consumers another spec intends only to **delete**. The manifest intersection cannot catch this — it compares **files**, and this conflict lives in the **deploy set**, one level of transitivity away. Missing it produced the worst failure this skill has recorded.

   Answer it by hand, because no tool will: cross the shared-module imports on the **neighbouring branches** against the functions your own specs deploy, and record the intersection — empty or not. The orchestrator that did exactly this reported it as the only thing its pre-scan produced, without having recognised at the time that it was the step that mattered.

   **And feed the answer back into the decomposition, not just into the collision rulings.** The question is not *"do these specs share a file?"* but *"**does the import graph join them?**"* — and when it does, they are not two deliverable specs with a surface to arbitrate. **They are one.** An orchestrator that classified two specs as `Independent` on "no shared surface" watched them fuse into a single deploy unit anyway, and every hour of containment choreography that followed — three merge laps and a deadlock — descended from that one line. Its own verdict in hindsight: it would have proposed **two** specs instead of three, merging the pair the graph had already merged. Splitting what deploys together buys no parallelism; it buys a merge order.

   Everything else waits for the manifests. Ruling on a hypothesis costs a round and produces decisions that do not survive contact with the plans.
   **Ask the transitive question explicitly, before any plan exists:** *does any spec touch a bundled shared module?* If one does, every consumer of that module is contested surface for this run — mark them all now, including consumers another spec only intends to **delete**. This is the collision that survives both the pre-scan and the Step 5 manifest intersection, because both compare **files** while the conflict lives in the **deploy set**, one level of transitivity away. Skipping this question is what produced the worst failure this skill has recorded.

---

## Why the cut decides whether N scales

Cut along topics and the specs' manifests overlap, so the manifest intersection becomes genuinely `N²` work and every pair needs arbitration. Cut along **file and deploy surface** and the manifests come out nearly disjoint by construction, so the intersection is `N` membership checks that take seconds each.

Measured: a five-spec run produced 10 pairs and dismissed all of them in seconds, precisely because five candidate items that converged on two files had been folded into **one** spec instead of five. The corollary from a different run points the same way: when the import graph joins two specs, they are one spec, not two.

## Sequence is not entanglement

A dependency graph tells you who *needs* whom; it cannot tell you who will end up *containing* whom. Containment is produced later, by the first merge between forks.

Observed: a graph printed `A -> B -> C`, and the sequence survived while its **meaning** did not — A still merged first, but because B now contained it, not because of any dependency the graph had recorded, and the second review was born empty. That is why the branch count promised at step-02 is a forecast rather than a commitment, and why step-06 re-measures it.

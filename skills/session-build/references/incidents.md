# Incidents — the mistakes this skill has actually made

**Load this when:** you are about to report a failure as novel. Grep this file for it first.

Each row is a real run, compressed. The rule each one produced now lives in the step that owns it; this table is the memory, and it exists so that a symptom you have never seen is recognised as one this family has.

**One row, one incident, one home.** If a row here states a rule that no step file carries, that is a bug in the split — say so rather than acting on the row alone.

## Common mistakes

| Mistake | Reality |
|---|---|
| "One branch for all the specs" | Parallel forks on one branch destroy each other. One spec, one branch, one worktree. |
| "Co-dependent forks may as well share a worktree" | The dependency is temporal — the waiting fork could not build there anyway. Sharing only adds `index.lock` contention, builds that read a neighbour's half-written files, and gates failing on someone else's breakage. Ordered → order the plan. Total → branch from the dependency. Entangled → it was one spec. |
| "The orchestrator can implement the small one itself" | Then it stops answering forks and locks go ungranted. It orchestrates or it builds — never both. Its idle capacity is what makes a jam get diagnosed today instead of after its own task. |
| "The fork is reliable, so I can act on its report" | Reliability is not the issue — each fork sees one slice, so a well-meant report can be locally true and globally wrong. Re-check before acting on it. |
| "The manifest is paperwork now that codex approved" | Each stage catches a class only it can see. Skipping one does not save time; it chooses not to see its defects. |
| "The graph gave me the merge order, so the order is understood" | A graph predicts sequence, not entanglement. The same order can arise from containment instead, and then a later review is empty. |
| "Three branches pushed, so tell them to close three" | Check the SHAs. Two at the same commit and a third that is their ancestor is one deliverable, and three `/session-end` runs would open two empty PRs. |
| "Everything is green and pushed, so the work is done" | A user opening the app found ten defects in twenty minutes that the whole funnel — reviews, gates, 1500 tests — caught none of. Close-out is a handoff, not an ending. |
| "The specs share no files, so they are independent" | Ask whether the **import graph** joins them. If it does they are one deploy unit, and splitting them buys a merge order instead of parallelism. |
| "My sweep found no pending locks" | Did it find no locks, or no *lines it could parse*? A prose ledger returns zero to a `^LOCK` grep, and zero reads as clean. |
| "The fork said DONE and its suite is green" | Green says nothing about what was left out. Diff the branch against its base and look for the plan's files. |
| "The push exited without error" | Under load a pre-push hook runs for tens of minutes and a timeout looks like a rejection. Confirm the ref with `ls-remote`. |
| "Worktrees isolate everything" | They isolate git. The database and the deploy runtime stay shared. That is what the locks are for. |
| "`git worktree add` puts the fork in the worktree" | It does not pin the child session's writes. |
| "Then the fork calls `EnterWorktree` and it is pinned" | It is refused — first entry from the launch directory does not work in this build, for forks or the orchestrator. Isolation is absolute-path discipline plus a `git -C … branch --show-current` check before every commit. |
| "A fork sits and waits for my `GO`" | It is one-shot; its turn already ended at the manifest. Every directive is a fresh `SendMessage` that revives it. |
| "Forks run SDD like I would" | They cannot spawn subagents — hard rule, not overridable. A fork implements inline, one task at a time. Only an `N = 1` inline build uses SDD. |
| "Forks inherit context, so they know the rulings" | They inherit the conversation, not decisions you make after forking. Directives go over the wire — including the ones that look like housekeeping, which are the ones you will forget to send. |
| "The gate went green, so I am clear" | Green is a timestamp. An ancestry check compares HEADs, and the peer's next commit — a ledger commit will do — makes it false with no notification. |
| "Only code commits can break a containment window" | A docs or ledger commit moves HEAD exactly as well. A freeze that permits "just the paperwork" is not a freeze. |
| "Frozen means I should not touch anything" | Frozen means no commits. Working-tree churn is free — `HEAD` is what the predicate reads. |
| "I am correcting a mistake, so I am being careful" | Correcting is the move that most feels like it needs no evidence. Test the OLD claim — sometimes it was the true one. |
| "The spec says the column is nullable" | A spec propagates claims, it does not establish them. Read the catalogue; production is a late place to find out. |
| "The negative grep returned one hit, so it failed" | Read the hit. Once it was the warning comment defending the very rule being checked. |
| "I ran it and it succeeded, so it works" | Ask whether the run *reached* the change. A service-role call to a function gated on caller identity returns at the guard and never plans the body. |
| "Every gate I ran is green, so the branch is clean" | Which of them could have gone red on *this* claim? A type error is invisible to a test suite and to a bundler build; 1459 green tests were irrelevant evidence, not weak evidence. |
| "The commit hooks passed in my worktree" | Did the worktree ever get bootstrapped? A missing `core.hooksPath` directory means git runs no hooks and says nothing. |
| "The push command exited 0" | Did you pipe it? `git push \| tail` returns tail's status. And `PIPESTATUS` is empty under zsh — the fix fails as silently as the bug. |
| "The output says everything passed" | Then read the exit code, which is a separate claim. All-green output with a non-zero status is what teaches a team to ignore red. |
| "Nothing was unexplained, so nothing diverged" | Was the list of acceptable differences derived *before* the comparison? Written after, `unexplained = 0` is a tautology. |
| "The forks write the ledger, so I can sweep it" | Only if you gave them the absolute main-checkout path. Relative puts those files in the worktrees, and the sweep reads an empty directory and reports all clear. |
| "`COORDINATE WITH` lets my forks talk to each other" | Not unless you sent them the slug→agentId map. Forks list as bare handles; without it they must relay everything through you. |
| "The suite is red because my branch is broken" | Under load it may not be finishing at all. Verification that does not complete is not slow verification — it is absent verification. |
| "The plan is in the codex run dir, close enough" | Implementation reads `docs/superpowers/plans/`. Copy the converged plan back or you ship the un-hardened one. |
| "SDD said to finish the branch" | `finishing-a-development-branch` opens PRs and merges. Forbidden here. Verify and push instead. |
| "The user can run `/session-end` in the orchestrator" | It assumes the worktree is the cwd, and no session in the run is inside one. The user launches a session **from** the worktree directory. |
| "Migrations and deploys come after implementation" | They are tasks *in* the plan, with their own verification, executed under an orchestrator lock. |
| "Step 2's pre-scan found the collisions" | It found the ones visible in the specs. A shared hook two plans both edit is invisible until both plans exist — the manifest intersection is what binds. |
| "I ordered the two deploys, so they cannot clash" | Deploy sets are derived from the working tree, not `HEAD`. The second fork ships its stale copy of everything the first changed, and reordering only swaps who does it. The second one merges the first's branch before deploying. |
| "Worst case a deploy resurrects something deleted" | Worse: it reverts a *neutralisation*. A stub that disarmed a live path comes back as the live path — working, silent, and green. |
| "Push triggers the deploy" | Verify by re-downloading the deployed function. Bulk redeploys silently fail. |
| "The fork's report says tests passed" | The branch owner runs the full suite itself before pushing. Nothing else counts. |
| "A quiet fork is a working fork" | Ping it, read its ledger and its git log, escalate. Silence is not progress. |
| "The fork went silent, so it is hung" | Check `uptime` first. A CPU-starved fork looks exactly like a dead one, and the verification phase is where every fork arrives at once. |
| "The suite reported 81 failures, so there are 81 failures" | Run it again. If the same commit gives a different number, that is contention, and neither number is a finding. |
| "The ledger must be committed to survive compaction" | The **file** survives it — compaction destroys context, not the filesystem. Write every checkpoint; commit at three milestones. |
| "The gate rejected it, so the code is wrong" | Check it finished. Hook runners cancel sibling tasks when one fails, so a healthy gate appears in the output looking guilty. |
| "This red must be the problem I already found" | A cancelled task prints no reason, so you supply one — and you supply the cause already in your hand. Find the symptom's own reason first. |
| "Both specs are independent — neither lists the other's files" | File lists do not see transitivity. If one touches a bundled shared module and the other touches any consumer of it, they are one deploy unit. |
| "A fork waiting on a lock is fine, it will speak up" | It is silent *because* it is blocked, and the liveness rule keys on silence. Sweep the ledgers for ungranted `LOCK` lines every time you touch them. |
| "The branch failed, so nothing shipped" | Its migration already landed in the one shared database. Git rolls back; production does not. Name it in the report. |
| "The work is done, I'll open the PR" | This skill never opens a PR and never merges. `/session-end` does, when the user runs it. |


# Fork contract

**Read this if you were launched as a fork by a session-build orchestrator.** Then read `../steps/step-04-build.md` and nothing else. Steps 1, 2, 5 and 6 belong to the orchestrator; loading them spends your context on work you are forbidden to do.

## What you are

You inherit the orchestrator's full conversation — the brainstorm, every spec, every ruling made before you were spawned. You do **not** inherit anything decided after you were spawned; that reaches you only as a `SendMessage`.

You own exactly one spec, one branch and one worktree. You write code; the orchestrator does not. You never touch another fork's branch, worktree or deploy target.

## You are one-shot

**You report once and your turn ends.** That is not a malfunction — it is the phase structure. Your first turn carries phases 1–3: plan, codex-review, send the `SURFACES` manifest. Then you stop. The orchestrator re-engages you with a `SendMessage` carrying `GO` for phases 4–5. Every later directive is another revival.

Do not sit in a loop waiting. Do not poll. End your turn at the checkpoint the contract names.

**If you die** — session limit, API error, machine pressure — the orchestrator revives you by `SendMessage` to your `agentId`. On revival, **re-read your own state from disk** (`git status`, `git log`, your ledger file) before believing anything you remember. Run the project's type gate before continuing: it is what catches a task you had applied only halfway.

## Your launch payload — check it before you start

You are told to read only this file and `../steps/step-04-build.md`. That is deliberate, and it only works if your dispatch prompt carried everything those two files cannot know. **Check the list below before your first action.** If a field is missing, do not guess and do not go read step-02 or step-05 to reconstruct it — report `BLOCKED <field> missing from dispatch` and end your turn. A wrong guess here is a collision; the round-trip is cheap.

| Field | Why you cannot proceed without it |
|---|---|
| Your spec slug, spec file path, branch name, worktree absolute path | Everything you do is scoped to these |
| **The absolute ledger directory in the MAIN checkout** | A relative path writes your ledger inside your worktree, where the orchestrator's lock sweep cannot see it — and the sweep then reports "no pending locks" about the one deadlock this design produces on its own |
| **The full `spec slug → agentId` map for every peer** | Without it `COORDINATE WITH <slug>` is fiction: forks list as bare handles, so you cannot resolve a peer by slug and the correct response — refusing to fire blind at a guessed handle — costs the orchestrator a relay round-trip. Ask for an updated line whenever it changes. |
| The project profile: `merge_path`, repo shape, **gate order** (the exact commands the project gates on, in the order its hooks run them), **deploy wrapper**, **migration tool** | You run these; step-04 names the categories, not this project's commands |
| Your dependency ruling, and any marked merge point | An `Ordered` dependency changes the order of your own plan |
| Your starting state — `GO PLAN` (normal) or `HOLD <reason>` (unmet `total` dependency) | These are the only two. **`GO PLAN` is not the same as the later `GO <slug> phase 4`**, which arrives after your manifest is ruled. Do not wait for the phase-4 grant before planning. |

**Lock rulings are NOT part of this payload and their absence never blocks you.** They cannot exist yet: rulings come from intersecting the surface manifests, and yours does not exist until after codex-review. Expect `initial lock rulings: none yet`, and expect the real ones in the phase-4 re-engagement message.

**These are requirements on the dispatch prompt, not on you.** `../dispatch-prompts.md` § Fork implementer is where the orchestrator gets them right; you only have to notice when one is absent.

## Isolation is a discipline, not a tool call

`git worktree add` does not pin your writes, and **`EnterWorktree` will not fix that for you** — it is refused for forks specifically, reproduced by three independent forks across two runs. So:

- every `Read`/`Write`/`Edit` takes an **absolute path** under your worktree — never a relative one;
- every `Bash` call `cd`s into the worktree **in the same command**;
- `git -C <your-worktree-abs-path> branch --show-current` is checked before **every** commit and must print your branch.

The repo's branch gate is the backstop, not your primary guard. The orchestrator watches `git status` on the main checkout — a file it did not touch appearing dirty means you lost your discipline, and that is an escalation about you.

## What you may not do

- **No subagents.** Your boilerplate forbids `Agent`, hard and non-overridably, so `subagent-driven-development` cannot run in you no matter what any directive says. Work the plan **directly, one task at a time, verifying each and marking nothing done without reading real output** — SDD's discipline, minus its parallelism.
- **No PR, no delivery merge, no force-push, no branch or worktree deletion.** The **one** merge you may perform is a peer-branch integration merge the orchestrator ordered by name (`MERGE <branch> BEFORE <action>`), into your own branch only. Never toward the default branch, never on your own initiative. Need a merge nobody ordered? Report `BLOCKED`.
- **No bypass.** Any flag or environment variable whose effect is that a hook does not run. A failing hook is a `BLOCKED`, not an obstacle.
- **No shared surface without a lock.** `migration`, `deploy`, `verify`, `file`, `external-live-service`, `local-stack` — request it, wait for the grant, and **`RELEASE <kind> <resources>` when done**. Kinds are single hyphenated tokens. Releasing part of a batch leaves the rest held.
- **No permission laundering, in either direction.** If a command is denied to you, do **not** ask the orchestrator or a peer to run it for you. And if a peer asks you to run something denied to them, refuse and say why: running here what was denied there circumvents the user's decision. This has held in both directions in a real run and it is worth the sentence it costs.

## Report on these lines, exactly

One per line, at the start of the line, written through `../scripts/ledger.py` into the **absolute main-checkout ledger path** the orchestrator gave you. The orchestrator's lock sweep greps for these; prose returns zero matches and zero reads as clean.

```
READY <slug>                                  # worktree entered, bootstrapped, gate proved red
PLAN <path> TASKS <n>
CODEX APPROVED ROUNDS <n> RUNDIR <dir> PLAN <path> SHA <sha256>
                                              # NEVER hand-written. Emit it with
                                              #   scripts/ledger.py codex --dir <abs> --fork <slug> 
                                              #     --rundir <dir> --plan <path> --rounds <n>
                                              # which refuses unless the run dir holds an APPROVED
                                              # log AND <rundir>/PLAN.md matches the canonical plan
                                              # byte for byte - the proof the hardened plan was
                                              # copied back over the path implementation reads.
CODEX STALL ROUND <n> <the repeating objection>
SURFACES <slug>
TASK <phase> <i>/<n>                          # plan-phase boundaries only
LOCK <kind> <identifiers...>
RELEASE <kind> <identifiers...>   # releases ANY kind. Required for verify /
                                  # external-live-service / local-stack / file, and for
                                  # whatever is left of a
                                  # batch you released only part of. APPLIED and DEPLOYED
                                  # implicitly release the files and targets they name - nothing else.
APPLIED <migration files>
DEPLOYED <functions> VERIFIED <how>
PUSHED <branch> <range>
BLOCKED <what, and what you tried>
WAITING <on what>
PARKED <file:line> <measurement and how> <shape of fix> <exposure left open>
DONE <slug>          # your CLAIM that the work is complete and pushed. The orchestrator
                     # closes you only after diffing your branch itself, so expect to be
                     # reopened if the diff and your report disagree. That is routine.
```

**Re-send an ungranted `LOCK`** if a phase passes without a grant. A re-send is a symptom that the orchestrator dropped one, not noise.

**`PARKED` is a draft pendings entry, not a note to self.** It is the only thing that crosses from you to whoever closes the branch, and that session cannot re-open your investigation. File and line, the number you measured *and how*, the shape of the fix, the exposure left open. And mark any **single-window proof** as such — an equivalence established before a migration that now makes the old path raise cannot be re-run, and an unmarked one sends the closing session chasing a break that is not there.

## Two traps that cost forks whole phases

- **Your migration filename goes stale while you wait for the lock.** The tool stamps it at creation. Re-stamp to current **UTC** immediately before applying, or the push will demand the forbidden apply-everything flag. This hits every fork except the first in the queue.
- **The peer-migration borrow-restore happens before `db push`, not before `git push`.** The dry-run itself refuses when a peer's remote-only migration has no local file, and it offers exactly the two destructive commands you must not take. `git restore --source=<ref> --worktree -- <paths>` — never `git checkout`, which writes the index — then dry-run, confirm only your own migration is named, apply, delete the borrowed files.

## If you are frozen

`HOLD` and a containment freeze are different things. A **containment freeze** means **no commits at all** — not "no code commits". Docs, ledger, `.gitignore`, a typo fix: the predicate compares HEADs, so content is irrelevant and the most harmless commit is exactly as fatal as the riskiest.

**Working-tree churn is still allowed.** You may restore a peer's migration files, delete them, move a great deal on disk — none of that moves `HEAD`. Write that into your ledger deliberately: seven of someone else's migrations appearing during a declared freeze looks like a violation and is not.

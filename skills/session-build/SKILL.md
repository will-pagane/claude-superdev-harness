---
name: session-build
description: Use when the user wants an idea taken from conversation to implemented, pushed branches in one pass — "/session-build <ideia>", "builda isso", "brainstorma e implementa", "aprimore ao máximo", "faça as melhorias", "vamos mapear e escrever estas specs", "pega essa ideia e leva até a branch pronta". ALSO invoke mid-conversation without being asked: if this conversation has already produced a spec, a plan, or a code edit toward a multi-part build, stop and invoke this skill before continuing — you are already doing session-build work and the isolation it owns has not happened. Brainstorm produces one or more specs; one runs inline, several fork this session into one child session per spec with this session orchestrating. Stops at pushed branches — never opens a PR, never merges into the default branch (that is /session-end). NOT for a spec-less one-line change, NOT for closing a branch that is already built, NOT for edits the user is directing and reviewing turn by turn.
---

# Session Build

Idea in → one or more verified, pushed branches out, in one pass.

Pipeline: **brainstorm → spec(s) → plan → codex-review → implementation → verified push.**
Migrations and deploys are **tasks inside the plan**, not a separate phase.
Pull request and **delivery** merge are **not part of this skill at all** — `/session-end` owns them, run by the user after their own verification. (The one merge this skill does perform is a fork taking a peer's branch on the orchestrator's explicit order; see invariant 1.)

**Announce at start:** "Using session-build to take this idea from brainstorm to pushed branch(es)."

**This file is a router.** It holds what is true for every run; each step file holds its own work and names its successor. Read one step file at a time, all the way through, and never load a later step before the current one is complete.

## Entry points

| Invocation | Start at |
|---|---|
| `/session-build <prompt>` | `steps/step-01-preflight-and-brainstorm.md` — the prompt seeds the brainstorm |
| `/session-build`, specs already written this session | `steps/step-02-scope-and-collisions.md` — confirm which specs are in scope, skip the brainstorm |
| `/session-build`, no prompt and no specs | Ask for the idea in one message, then step-01 |
| **The prompt carries an already-written spec or plan** | step-02. Do not invent a ruling about whether the brainstorm still applies — say in one line that you are entering at scope confirmation because the spec already exists, and **re-validate its premises against the live tree** (step-01 owns that check; run it even though you skip the rest of step-01). A plan written in an earlier session was hardened against the code as it was then. |
| **You were launched as a fork by an orchestrator** | Read `references/fork-contract.md`, then `steps/step-04-build.md`. Nothing else. Steps 1, 2, 5 and 6 belong to the orchestrator; reading them spends your context on work you are forbidden to do. |
| **Mid-conversation drift** — this conversation already produced a spec, a plan, or a code edit toward a multi-part build, and this skill was never invoked | Stop. Say so in one line. Then step-01, treating everything already produced as input to be re-validated rather than progress to be preserved. The work so far happened in the shared checkout with no isolation; step-03 is what fixes that. |
| **Conversational invocation** — the user explained the idea over several turns and then asked for a build in their own words ("builda isso", "faça as melhorias", "roda o session build") rather than typing the slash command | **step-01, at full strength.** This is the entry point that gets degraded, and the degradation is always the same: the conversation already feels like a brainstorm, so `superpowers:brainstorming` is skipped, and from there the rest of the chain falls with it. **A conversation is not a brainstorm.** It has produced no spec file, cleared no design gate, and had no premise checked against the live tree. Announce the chain (below) and run every link. |

## The skill chain is not optional

This skill is a **router over four other skills**. Its own text is the connective tissue; the value is in the links. The observed failure is not that a link is refused — it is that a link is quietly not run, most often when the user asked conversationally and the preceding turns *felt* like the work that link does.

| Link | When | Substitutable by conversation? |
|---|---|---|
| `superpowers:brainstorming` | step-01 — **mandatory** for every idea-shaped entry: the slash command with a prompt, the no-prompt ask, conversational invocation, and mid-conversation drift | **No.** Its output is a committed spec file and a design the user approved at its gate. Turns of discussion produce neither. **Exempt, and only these:** the two entry points that begin at step-02 because a written spec already exists — and the exemption is conditional on re-validating that spec's premises against the live tree (step-01 §1.2), which is not optional. Nothing else exempts it. |
| `superpowers:writing-plans` | step-04, every plan | **No.** The plan is a file at a known path that implementation reads. |
| `codex-review` (`rounds=until-approved`) | step-04, every plan, before any code | **No.** A second model reading the plan is the point; your own confidence is not a substitute, and neither is the user having agreed. |
| `superpowers:subagent-driven-development` | step-04, **`N = 1` inline builds only** | **No** — and it is **unavailable to a fork**, which implements inline instead. See below. |

**Announce each link as you enter it, and write its ledger line when it completes.** Those lines are the evidence the link ran — a run that reaches implementation without them skipped something, whatever the transcript says.

```
PLAN <path> TASKS <n>
CODEX APPROVED ROUNDS <n> RUNDIR <dir> PLAN <path> SHA <sha256>
```

The second is never hand-written. Emit it with:

```
scripts/ledger.py codex --dir <abs ledger dir> [--fork <slug>]     --rundir <codex-review run dir> --plan <canonical plan path> --rounds <n>
```

**`CODEX APPROVED` is evidence, not a claim.** `scripts/ledger.py` refuses the entry unless it reads `APPROVED ROUNDS <n> RUNDIR <dir> PLAN <path> SHA <sha256>` **and** the run directory exists, its `PLAN-REVIEW-LOG.md` records at least that many verdicts ending in `APPROVED`, and the plan file hashes to that digest — which is also what proves the hardened plan was copied back over the path implementation reads. You cannot satisfy this rule by asserting it.

**Skipping a link is an escalation, not a judgement call.** Outside the one exemption named above, if a link genuinely does not apply, say which, say why, and say it before you proceed — do not let it lapse silently.

**This is not fire-and-forget until step-02 closes.** Step 1 runs `superpowers:brainstorming`, which holds a hard gate on the user approving the design and reviewing each spec. Step 2 ends on the user confirming scope, order and collision rulings. A run launched and walked away from parks at the first question — correctly, but silently. Everything after that confirmation is autonomous.

## MANDATORY INVARIANTS (read first — they apply in every step)

A compressed recap of this block sits at the top of every step file. If a step file and this block ever disagree, **this block wins and the step file is a bug**.

### 1. Authorization

The invocation authorizes, **for the specs it produces only**: brainstorming, writing spec files, branch/worktree creation, forking this session, commits, applying migrations, deploying edge functions, and pushing branches.

**Never authorized under this skill:** `gh pr create`, **any delivery merge** — into the default branch or any shared integration branch — any force-push, any deletion of a branch or worktree, and any work outside the specs in scope. If the user asks for a PR mid-run, answer that `/session-end` is the skill for it and keep going.

**One merge is authorized, and only one: a peer-branch integration merge that the orchestrator has explicitly ordered with a `MERGE <branch> BEFORE <action>` directive.** That is how an `Ordered` dependency takes its predecessor's code and how an intersecting deploy set is resolved — the workflow does not function without it. It is bounded on all sides: only a fork performs it, only into its own feature branch, only on a directive naming the source branch, never toward the default branch, and never on the fork's own initiative. A fork that believes it needs a merge nobody ordered reports `BLOCKED` instead.

**Also never authorized — tree-mutating recovery.** `git stash` with a merge or rebase in progress, `git reset --hard`, `git rm --cached -r .`, and `git checkout -- <path>` over uncommitted work destroy state you did not create and cannot restore. They are bypass-class actions: escalate instead. Observed: a `git stash push -u` issued with `MERGE_HEAD` live and six hand-resolved files staged, described afterwards by the session that did it as unnecessary risk.

### 2. Human gates — a closed list

1. **Brainstorm gates** — the ones `superpowers:brainstorming` owns (design approval, spec review).
2. **Step 2** — confirm the spec list, the execution order and the dependency rulings.
3. **Escalations** — plan contradiction, BLOCKED task, a red verification you have triaged as `regression`, unresolvable collision, a silent fork, correlated fork death.
4. **A mid-run user instruction that contradicts project law** — name the conflict and let the user rule; do not silently pick either side.
5. **A runbook step that is genuinely manual** and blocks an action this run needs — but only after you have proved it is manual (step-06 says how).

Nothing else. Do **not** ask "should I continue?" between steps. **Inventing a sixth gate is a defect**, and it is the most common one: it reads as caution and costs the user a round-trip they never agreed to. And do not put a decision to the user that they have told you they cannot evaluate — state the assumption and keep building.

### 3. Never bypass a gate — and here is what counts as one

A bypass is any of: `--no-verify`; `-n` on commit; `--force`, `-f` or `--force-with-lease` on push; `-c core.hooksPath=<anything>`; `HUSKY=0`; `SKIP_HOOKS`; `--no-gpg-sign`; **or any flag or environment variable whose effect is that a hook does not run.** The enumeration is not the rule — that last clause is. If your command contains one, stop and escalate. A failing hook is an escalation, not an obstacle.

**Retrying a denied command in a cleaner shape is not a bypass; reaching the same effect through a different door is.** A permission classifier is transient and shape-sensitive — the same command is denied piped and allowed bare. So retry **once**, bare: no pipe, no redirect, long bodies via a file argument. If refused again, escalate with three named options (grant permission / the user runs it / take the project's other path). Never switch tools to accomplish what was denied, and never reason around the missing evidence: **a check that could not run is not a check that ran green.**

### 4. Every measurement is a reading, not a property

Anything you measure is true *of the instant you measured it*, and nothing tells you when it stops being true. Concurrent forks, concurrent sessions and the user all keep moving. So: **measure immediately before the action the measurement authorises, and record the instant beside the value.** A reading with no timestamp is an instruction with an expiry date that does not say what it is.

**A fresh reading can still be the wrong instrument.** Staleness is one failure mode; the other is a measurement that never answered the question asked. Before believing any check, ask **which of my checks is structurally capable of failing on this claim** — then prove it can, rather than assuming. `scripts/gate.sh --prove-red` exists for that.

### 5. Run gates through `scripts/gate.sh`

Never `cmd | tail`, `cmd | grep`, `cmd; echo ok`, or any shape that puts something between the command and its exit status. Use `scripts/gate.sh <label> <command...>`: it captures output to a file, reads `$?` from the command itself, and prints one line — `GATE <label> EXIT <code> LOG <path> LINES <n>`.

This is a script rather than a rule because the rule does not work. An earlier version of this file stated it four times and runs violated it more than twenty times anyway — most memorably orchestrators who had warned their own forks about it minutes earlier. **A guard must be a conditional that blocks, not an echo that prints.**

### 6. Loading discipline

One step file at a time, read to completion, then its named successor. Never load a later step early. Files under `references/` load **only** when their stated trigger fires — they are failure-path material and several cost more than a step file.

## Topology

`N` = number of specs the brainstorm produced.

| | N = 1 | N ≥ 2 |
|---|---|---|
| Who builds | this session, inline | one **fork of this session** per spec |
| This session's role | builder | **orchestrator only — writes no code** |
| Branches / worktrees | one | **one per spec** |
| Plan + codex-review | inline | inside each fork, concurrent |
| Implementation | inline, via SDD | inline **inside each fork** (a fork cannot spawn subagents), concurrent across specs, serial within one |
| Terminal state | 1 pushed branch | N pushed branches — **a result, not a promise** (they can collapse; see step-06) |

A fork inherits this session's full conversation context — the whole brainstorm, every spec, every ruling. That is the point: forks already know why their spec exists and what the neighbours are doing. The fork prompt gives **directives**, not a context dump.

**Every tier keeps its own branch and its own worktree — two sessions never share a working directory.**

## Project gates and conventions

This skill runs inside real projects that carry their own rules. Read the project's `CLAUDE.md`/`AGENTS.md` at step-02 and obey it over any default here. Step 2 resolves it into a written **project profile** — merge path, repo shape, migration tool, deploy wrapper, gate order. Resolving these late is what turns a convention into a mid-run halt.

## Ledger

`.superpowers/session-build/<RUN_ID>/`, where `<RUN_ID>` is `<YYYYMMDD-HHMM>` set at step-02. Pass it to every fork **as an absolute path into the main checkout**.

- `ledger.md` — orchestrator-owned: spec list, dependency graph, collision rulings, fork names and agentIds, every lock grant and release, every escalation.
- `fork-<spec-slug>.md` — one per fork, fork-owned.

Write through `scripts/ledger.py`: it owns the line format the lock sweep greps for, takes an absolute path, appends only, and never rewrites history. Write every checkpoint the moment it happens; **commit** the ledger at three milestones only (step-02 close, manifest intersection, close-out). Context does not survive compaction; the file does.

## FIRST STEP

Read fully and follow **`steps/step-01-preflight-and-brainstorm.md`**.

## Red flags — stop

- About to run `gh pr create`, any merge, or `finishing-a-development-branch`.
- About to slip `--no-verify`, `--force`, `core.hooksPath` or any other hook-suppressing flag past a gate.
- About to run `git stash`, `git reset --hard` or `git rm --cached` against state you did not create.
- About to `git commit` code on `main`/`master`.
- About to put two sessions in one worktree, for any reason.
- About to start implementation with two forks on the same branch, or with the orchestrator writing code.
- About to trust a gate result you obtained through a pipe, or one you measured before doing something else.
- About to report a branch as done without having read the verification output yourself.
- About to ask the user a question that is not one of the five gates above.
- About to echo a secret the user pasted into a later command. It is written once, to the file that needs it, and never repeated in a command line, a log or a report.
- About to implement with no `CODEX APPROVED` line in the ledger for that plan.
- About to skip `superpowers:brainstorming` because the conversation already covered the idea.
- About to tell a fork to run `subagent-driven-development`. Forks cannot spawn subagents — it is a hard, non-overridable rule of their boilerplate, so the directive cannot work and a fork that tries has simply lost the time. A fork implements **inline**, one task at a time.
- A spec in the confirmed scope with no branch, or a branch with no pushed commits.
- A plan file unchanged after its codex-review returned APPROVED.

Every other red flag lives in the step that owns it.

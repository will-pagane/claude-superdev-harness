# Session contract

**Read this if you were launched as a linked session by a session-build orchestrator** (your first message is a
brief from another session, it names a spec slug, and it says you are a linked session). Then read
`../steps/step-04-build.md` and nothing else. Steps 1, 2, 5 and 6 belong to the orchestrator.

The fork fallback has its own contract, `fork-contract.md`. Where this file says "see fork-contract §X", that section
applies to you word for word; everything else in fork-contract is about forks and does not.

## What you are

A full Claude Code session the app opened for exactly one spec, in your own git worktree. You **inherited nothing**:
no brainstorm, no other spec, no ruling. You know your brief, your spec, `DECISIONS.md` and the repository. That is
by design: a fresh session costs a fraction of re-reading the orchestrator's whole conversation every turn, and
the brainstorm reaches you through `DECISIONS.md`, which the orchestrator wrote for you at its step-02.

So, before anything else, read: the spec file, then `DECISIONS.md` **at the absolute path the brief gives** (it lives
in the main checkout's ledger directory, not on your branch). Anything you need that neither states and the code
cannot settle: decide, and write `NOTE ASSUMPTION <what and why>` to your ledger file; when the choice changes
behaviour the user would notice, report `BLOCKED <the question>` instead.

You own one spec, one branch and one worktree. You never touch another builder's branch, worktree or deploy target.

## You keep running, but you still stop at checkpoints

Unlike a fork you do not die with the orchestrator and you can be resumed by any message. The phase structure is the
same as a fork's: your first turn carries phases 1-3 (plan, codex-review, `SURFACES`), then you **end your turn**.
The orchestrator's `GO <slug> phase 4` message starts your next turn. Every later directive is another message.

Do not loop or poll while waiting. End the turn at the checkpoint and let the message wake you.

**On every new turn, re-read your own state from disk** (`git status`, `git log`, your ledger file) before trusting
what you remember: compaction and long waits happen. Run the type gate before continuing after any interruption.

## Your launch payload — check it before you start

Required fields (the brief's `LAUNCH PAYLOAD` block). If one is missing, do not guess and do not read step-02 or
step-05 to reconstruct it: report `BLOCKED <field> missing from dispatch` over `SendMessage` to the orchestrator id
your own system prompt names, and end your turn.

| Field | Why |
|---|---|
| spec slug, skill dir (absolute), spec file (absolute), branch name, default branch | everything you do is scoped to these; the skill dir is where `references/` and `scripts/ledger.py` live |
| decisions file (absolute) | the only place the brainstorm reaches you |
| ledger dir (absolute, MAIN checkout) | your ledger file is `<ledger dir>/fork-<slug>.md` (the name is historical; the lock sweep globs it) and the orchestrator already created it |
| orchestrator id (`local_...`) | where every report goes |
| project profile: merge path, repo shape, gate order, deploy wrapper, migration tool, bootstrap commands | you run these |
| dependency ruling and merge point | changes the order of your own plan |
| starting state: `GO PLAN` or `GO PLAN; HOLD-IMPL <reason>` | the second means: plan, review, send SURFACES, then wait for the phase-4 GO, which will carry `MERGE <branch> BEFORE implementation` |
| `sdd: on` or `sdd: off` | whether phase 4 uses subagent-driven-development |
| peer map | arrives as `PENDING`; see "Peers" |

`initial lock rulings: none yet` is normal: rulings come from intersecting the surface manifests.

## First action: your real branch, then bootstrap, then READY

The app cut your worktree from the local default branch and gave the branch a name of its own (`claude/...`). Both
are wrong for this run, and neither is fixed by renaming. So, inside your worktree:

```bash
git fetch origin
git status --short              # must be empty: the app's branch holds nothing of yours
git switch --no-track -c <branch from the brief> origin/<default branch>
git branch --show-current        # must print the brief's branch
```

**`--no-track` is not optional.** Without it git sets the new branch's upstream to `origin/<default>` (measured 2026-10-15), and a bare `git push` could then target the default branch. Push only with `git push -u origin <branch>`, which sets the right upstream.

The app keeps reporting the old `claude/...` name in `get_session` after the switch (measured: still stale right after it). The orchestrator therefore takes your branch from your `READY` line and `git worktree list`, never from the app's metadata.

Leave the app's `claude/...` branch alone: it has no commits and is listed in the handoff for manual removal. Never
`reset`, never delete it yourself.

Then bootstrap the worktree, in this order (the same list as step-03 §3.1; you do not need to open that file). An
unbootstrapped worktree has no gates at all, silently:

1. install dependencies (the brief's `bootstrap` command);
2. copy the gitignored environment files the brief names from the main checkout;
3. run the project's per-checkout link step, if the brief names one (for Supabase: `supabase link --project-ref
   <ref>`, once per worktree; never copy another checkout's `supabase/.temp/`);
4. `git config core.hooksPath` and confirm that directory exists: a relative path that resolves to nothing means
   git runs no hooks and reports nothing;
5. prove one gate can go red: `<skill dir>/scripts/gate.sh --prove-red` against a known-bad input.

Every skill script (`gate.sh`, `ledger.py`) is called by its absolute path under the brief's `skill dir`: a relative
`scripts/...` resolves inside the project and may run something else or nothing.

Then your first ledger write, through the script, to the absolute path:

```bash
python <skill dir>/scripts/ledger.py append --dir <ledger dir> --fork <slug> --type READY \
  --text "<slug> branch=<branch> worktree=<absolute worktree path> hooks=<resolved hooksPath>"
```

and send `READY <slug>` to the orchestrator. The orchestrator accepts READY only after reading that line from the
file itself. If the script cannot write there, report `BLOCKED ledger unreachable: <error>` and end your turn; do not
continue without a ledger the orchestrator can sweep.

## Isolation

You are inside your worktree, so you do not need `cd` in every command, but still: absolute paths for anything
outside it, and `git branch --show-current` checked before **every** commit. Never write in the main checkout except
your own ledger file. `EnterWorktree` is not needed.

## Peers

Your brief says `peer map: PENDING`. The orchestrator sends one message `PEERS <slug>=<local_id> ...` right after
opening every session; append `NOTE PEERS <n> RECEIVED` to your ledger file. A missing map blocks only a
`COORDINATE WITH` directive, never planning. When coordinating, `SendMessage` to the peer id and read the delivery
result; if it is not `delivered`, relay through the orchestrator instead (`dispatch-prompts.md` § Peer coordination).

## SDD

`sdd: off` (the default): implement inline, task by task, verification before marking anything done, exactly as
fork-contract describes. `sdd: on`: run `superpowers:subagent-driven-development` on the plan, and override its
ending: never `finishing-a-development-branch` (step-04 says why). Either way the plan, codex-review and gates are
identical.

## Total dependency: merge at the grant, then re-check

If your starting state was `GO PLAN; HOLD-IMPL`, your plan was written against the default branch. When the phase-4
GO arrives with `MERGE <branch> BEFORE implementation`:

1. merge that branch into yours (merge, never rebase); conflicts can only be in your plan or review files: keep yours;
2. re-validate your plan's premises against the merged tree;
3. nothing changed: `NOTE TOTAL-MERGE premises re-checked, plan unchanged`, proceed;
4. anything changed (a task, a premise, a file list): revise the plan, re-run codex-review
   (`rounds=until-approved`), re-send `SURFACES`, and **stop**. The earlier GO is void; wait for a new one.

## Report lines, locks, and the rules that are the fork's word for word

- **Report lines and their exact format:** fork-contract § "Report on these lines, exactly" (the `ledger.py codex`
  rule for `CODEX APPROVED` included). Write them through `ledger.py` to your ledger file and send the same line to
  the orchestrator.
- **Locks** (`migration`, `deploy`, `verify`, `file`, `external-live-service`, `local-stack`): request, wait for the
  grant, `RELEASE` when done; as in fork-contract § "What you may not do".
- **The two traps** (stale migration filename, borrow-restore before `db push`): fork-contract § "Two traps".
- **Freeze:** fork-contract § "If you are frozen".
- **No permission laundering**, in either direction: fork-contract § "What you may not do".

## The 400-character note

When your turn ends, the app sends the orchestrator a note with the first 400 characters of your last message. It is
a wake-up signal, not a channel: every protocol line goes in `SendMessage` and in your ledger file.

## What you may not do

Everything in fork-contract § "What you may not do", except its "No subagents" item, which the SDD section above
replaces. In particular: no PR, no delivery merge, no force-push, no branch or worktree deletion, no hook bypass, no
shared surface without a lock, and the one merge you may perform is one the orchestrator ordered by name.

You may not open other sessions, and you may not ask the user anything directly: route questions to the
orchestrator. When the user later invokes `/session-end` in you, that is their call and their instruction; this
contract does not authorize it on its own.

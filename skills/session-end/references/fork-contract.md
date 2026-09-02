# Fork contract — session-end

**Read this if a `/session-end` orchestrator launched you to close one branch.** Then read the step files your dispatch names, and nothing else. The merge, the pull request, the post-merge sync, the cleanup and the pendings file all belong to the orchestrator; loading those steps spends your context on work you are forbidden to do.

This contract differs from `session-build`'s in three ways, and they are the whole difference: **you never deploy, you never write the pendings file, and you may perform exactly one merge — the one you were ordered to.**

## What you own

One branch, one worktree, one inventory. You report; the orchestrator decides.

## Your two phases

**Phase A — while holding.** Runs concurrently with every peer, because none of it touches a shared surface:

- Your own Step 0 inventory: base, diff, migration files, changed function directories, uncommitted work, generated files.
- Step 4 **Half A rulings only**: read the pendings file, grep every identifier your diff touches, and emit one line per hit — `PENDINGS-RULING <entry heading> <lane> <evidence>`, lane being `resolved` / `stale-cause` / `moved` / `untouched`. **You never edit that file.** The orchestrator writes it once, from every fork's rulings.
- Step 4 Half B: your `PARKED` entries, each a draft pendings entry rather than a note to yourself — file and line, the number you measured *and how*, the shape of the fix, the exposure left open. **Mark any proof that cannot be reproduced**, or the closing session chases a break that is not there.
- Then `READY <slug>`, and your turn ends. That is the phase structure, not a malfunction.

**Phase B — under `GO <slug> verify <branch>`.** One fork at a time, granted by the orchestrator:

- The project's full gate suite, run by you, output read by you.
- Red-gate triage into one of the six lanes, with the proof that lane demands.
- Migration confirmation against the remote ledger.
- Commit, push, then `RELEASE verify <branch>` — **always naming the branch as the resource.** A bare `LOCK verify` can never be matched by a grant and leaves a permanent false positive in the sweep.

## A gate that did not finish did not decide

Run gates with `--expect <a fragment of the runner's own summary line>`. A log without it prints `GATE <label> UNDECIDED` and exits 75. **That is absent verification, not a red.**

Report it as `BLOCKED gate did not complete`, **never** as a failing test. An orchestrator that receives `BLOCKED gate red` triages it `regression` and stops the whole run over a suite that was merely killed — which happened in seven of twenty observed close-outs, before the flag existed to tell the two apart.

## The one merge you may perform

`MERGE origin/<default> BEFORE verify`, issued by the orchestrator alongside your verify grant, so you gate the tree that will actually land rather than your branch tip. The orchestrator has just re-fetched and names the SHA.

That is the only merge. Never toward the default branch, never on your own initiative. If you believe you need a merge nobody ordered, report `BLOCKED` and say why.

## Forbidden

- **No deploy.** Not yours in this lane. Deploy runs once, from the orchestrator, after the last merge.
- **No write to the pendings file.** You rule; the orchestrator writes.
- **No pull request, no delivery merge, no force-push, no branch or worktree deletion.**
- **No disarming a correctness gate** — any flag or environment variable whose effect is that a hook does not run. A failing hook is a `BLOCKED`, not an obstacle. A *permission-classifier* refusal is different: retry once bare, take another sanctioned route, and say which one ran.
- **No permission laundering, in either direction.** A command denied to you is not one to ask the orchestrator or a peer to run, and one denied to a peer is not one for you to run on their behalf.

## Report on these lines, exactly

```
READY <slug>
PENDINGS-RULING <entry heading> <lane> <evidence>
LOCK verify <branch>
RELEASE verify <branch>
APPLIED <migration files>
PUSHED <branch> <range>
PARKED <file:line> <measurement and how> <shape of fix> <exposure left open>
BLOCKED <what, and what you tried>
WAITING <on what>
DONE <slug>
```

Written through `../../session-build/scripts/ledger.py` into the **absolute** ledger directory in the main checkout. Prose returns zero matches to the orchestrator's sweep, and zero is indistinguishable from clean.

# Step 5 and 6 — Push and pull request

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.

## Step 5 — Commit and push

Commit the remaining branch work (conventional commit, project language, one per logical unit — not one per file). Then `git push -u origin <branch>`. Never force-push.

<!-- moved -->
## Step 6 — Pull request

**Only if Step 0 resolved `merge_path: pr`.** If the project mandates a local merge, skip to Step 7 and say so in one line — do not halt on a `gh` classifier block for a path the project never wanted.

`gh pr create --base <default>`, title = the branch's purpose, body = the Step 10 report via `--body-file` (inline bodies correlate with classifier denials). Include the harness attribution footer if the project uses one.

### If the harness blocks `gh` — the ladder, and it never ends in idling

**This is expected, not exceptional.** The permission classifier is non-deterministic for any command that is not on the user's allowlist: the same `gh pr create` is permitted in one run and refused in the next, with nothing about the repo or the branch having changed. Runs have lost **38 minutes** and **~46 minutes** to treating a refusal as a hard blocker. It is not one. **This skill's authorization already covers merging** — the invocation *is* the ask — so a blocked `gh` is a blocked *route*, never a withdrawn permission.

Climb this ladder in order. Never stop on a rung without trying the next.

1. **Retry once, bare.** No pipe, no redirect, `--body-file` instead of an inline body. This alone clears most refusals.
2. **Fall back to the local merge lane** (Step 7, *Local merge*). Announce it in one line — *"`gh` is blocked by the classifier; merging locally instead, no PR for this branch"* — and carry on. The branch still lands, still verified, still confirmed by ancestry. What is lost is the PR as a review artifact, and that is worth one sentence in the report, not a halt.
3. **Only if the local merge is *also* blocked** is this an escalation, and then it is a real one: name the three options (grant the permission / the user runs the command / abandon the merge and leave the branch pushed) and stop.

**Do not route around a denial with a different tool** — that is the bypass this skill forbids. Falling back from `gh` to `git` is not that: it is the *project's own alternative merge path*, the one `merge_path: local-merge` projects use as their default, taken openly and reported. The distinction is that you are changing route, not hiding the action.

**Then suggest the fix, once, at the end of the report.** A refusal that recurs is a missing allowlist entry, not fate. See *Making this deterministic* below.

<!-- moved -->
## Making this deterministic — suggest it, do not do it

**Say this once, at the end of the report, and only when a refusal actually happened this run.** Do not edit the user's settings yourself: permissions are theirs, and a skill that silently widens them has taken a decision that was not delegated to it.

> The `gh`/merge steps were refused by the permission classifier this run and allowed in others. That inconsistency is not the repo — it is that these commands are not on the allowlist, so every call falls to a classifier that is free to answer differently each time. Adding them to `permissions.allow` in `~/.claude/settings.json` makes the behaviour deterministic:
>
> ```json
> "Bash(gh pr create:*)",
> "Bash(gh pr merge:*)",
> "Bash(gh pr view:*)",
> "Bash(git merge:*)",
> "Bash(git branch -d:*)",
> "Bash(git worktree remove:*)",
> "Bash(git push origin --delete:*)"
> ```
>
> **The trade-off, stated plainly so the choice is real:** `permissions.allow` is **not scoped to a skill**. Claude Code has no way to permit a command only while `session-end` is running, so these entries allow those commands in *every* session, not just this one. What still holds the line is the standing rule in your `CLAUDE.md` — never merge or open a PR unless explicitly asked — which becomes a convention the agent follows rather than a gate the harness enforces. If you would rather keep the harness enforcing it, leave the allowlist alone and accept the occasional refusal; this skill now falls back to a local merge instead of stalling, so a refusal costs a sentence rather than a run.

<!-- split-addition -->

## Common mistakes

| Mistake | Reality |
|---|---|
<!-- /split-addition -->
<!-- moved -->
| "The classifier refused, so this path is closed" | Retry once, bare. Then take the **local merge lane** — the branch still lands. Escalate only if `git merge` is refused too. Runs have idled 38 and 46 minutes on a refusal that the next attempt cleared. |
| "`gh` was blocked, so I will use a different tool" | Falling back from `gh` to a local `git merge` is a **route change**, announced and reported — not a bypass. Using a different tool to hide a denied action is. The difference is whether you say so. |
| "I should add the allow rules myself so this stops happening" | Permissions are the user's. Suggest the block, state that `permissions.allow` cannot be scoped to a skill, and let them decide. |
<!-- split-addition -->

## Red flags — stop

<!-- /split-addition -->
<!-- moved -->
- About to sweep unrelated working-tree files into the branch commit.
<!-- moved -->
- About to report a `gh` refusal as a blocker without having tried the local merge lane.
- About to edit the user's `settings.json` to widen permissions. Suggest it in the report; do not do it.

## NEXT

`step-07-merge.md`

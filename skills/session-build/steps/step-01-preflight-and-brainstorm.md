# Step 1 — Preflight, then brainstorm to spec(s)

**Invariants recap** (full text in `../SKILL.md`): no PR, no delivery merge (the ONE exception is a peer-branch integration merge an orchestrator ordered by name), no branch/worktree deletion, no tree-mutating recovery. Five human gates only — never ask "should I continue?". A bypass is *any* flag or env var whose effect is that a hook does not run. Every measurement is a reading: measure immediately before the action it authorises. Gates run through `../scripts/gate.sh`. One step file at a time.

## 1.1 Preflight — before you read a single source file

The brainstorm is about to make claims about code. Make sure it is the code that exists.

```
git fetch origin
git rev-list --left-right --count HEAD...origin/<default-branch>
```

If the right-hand number is not 0, **sync before reading anything, or state in one line why you are not.** A brainstorm run against a stale checkout does not fail loudly — it produces a spec that is internally coherent and aimed at the wrong tree.

Observed: a brainstorm ran against a checkout **3,602 commits behind** the default branch. Three of its four scope targets turned out to be already done in the real code — an index that existed, a retention policy that existed, and a "forgotten" artifact that was a registered, documented job. The user had to intervene and the whole spec was rebuilt. Everything read before that point was discarded.

Then classify the repo, because several later steps do not apply to every shape. Write the answers into the ledger at step-02 as the **project profile**:

| Field | How to resolve it |
|---|---|
| `merge_path` | The project's `CLAUDE.md`. `pr` or `local-merge`. Resolve it **now**, not when you reach it. |
| `repo_shape` | `app` / `docs-only` / `infra-no-suite` / `library`. Decides what verification means. |
| `migration_tool` | The CLI and whether migrations are applied by CI on merge instead of by this run. |
| `deploy_wrapper` | The project's script, or `none`. Never a bare deploy command. |
| `gate_order` | The commands the project actually gates on, in the order its hooks run them. |

## 1.2 Every premise is a claim

**A fact the brainstorm asserts is not a fact the spec may inherit.** Before a premise becomes a spec line, read it out of the live tree: the column really is nullable, the function really is called from there, the job really is not registered. A spec cannot inherit premises the brainstorm itself has already falsified — and it will, silently, if nobody re-reads.

## 1.3 Brainstorm

Run `superpowers:brainstorming` with the user's prompt, following it exactly, including its gates.

Three overrides on that skill:

- **Its terminal state is invoking `writing-plans`. Ignore that.** Return here instead — step-04 owns planning, and for `N ≥ 2` planning happens inside the forks.
- **Decomposition produces the spec set.** When the idea is too large for one spec, brainstorming decomposes it into sub-projects. Brainstorm **every** sub-project to its own spec file before leaving this step — do not build the first and defer the rest. That decomposition is exactly what makes `N ≥ 2`.
- **Filter what you put to the user.** `superpowers:brainstorming` has an ask-until-approved posture; the user's own `CLAUDE.md` says to ask only when different readings lead to materially different work. The second wins. In particular, **do not ask the user to arbitrate a trade-off they have told you they cannot evaluate** — an infrastructure cost comparison put to someone who answered that they lacked the knowledge to decide. State the assumption, name what would change your mind, and keep building.

**Cut the specs by where the diff lands, not by theme.** This is decided here, and it is what decides whether `N` scales at all — see step-02.

## 1.4 Land the specs

Specs go to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` (or the project's spec location) and are committed per the project's docs policy. If the project routes docs straight to the default branch, commit them there — not on a feature branch.

**Push the spec commit before step-03** if the project's worktrees branch from the remote default branch — otherwise a fresh worktree will not contain the spec its fork is supposed to read.

## Red flags — stop

- About to read source files without having run the freshness check above.
- About to write a spec line asserting a fact you have not read out of the live tree.
- About to leave this step with some sub-projects brainstormed and others deferred.
- About to ask the user a question outside the brainstorm's own gates.

## NEXT

`step-02-scope-and-collisions.md`

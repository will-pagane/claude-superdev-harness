# Repo shapes — what verification means when the default assumptions do not hold

**Load this at Step 0 when the repo is not a plain application with a test suite, migrations and deployables.**

This skill was written against one stack. Its steps assume a project that has all four of: a lint/typecheck/test suite, database migrations, deployable functions, and a pull-request merge path. Real repos are missing some of those, and the failure mode is not that a step breaks loudly — it is that the step gets **improvised**, or run as dead weight, or reported as done when it did nothing.

Classify once, write the answer into the ledger, and route past what does not apply. **Say in the report which steps were routed past and why** — a skipped step reported as skipped is information; a skipped step reported as complete is a lie.

## The shapes

| Shape | What it looks like | What changes |
|---|---|---|
| **`app`** | Suite, migrations, deployables, PR merge | Nothing. Every step applies as written. |
| **`docs-only`** | The whole diff is markdown, or the repo is a documentation vault | Step 1 runs the **formatter the project's CI runs**, not the type checker — and says so. Steps 2, 3 and 8 do not apply. Say "Steps 2, 3 and 8 do not apply to this repo" in the report rather than leaving them silent. |
| **`infra-no-suite`** | Infrastructure or configuration repo with no test suite at all | Step 1 has no suite to run. **Do not improvise one.** Name the checks that do exist — a linter, a config validator, a dry-run — run those through `../scripts/gate.sh`, and state in the report that no test suite exists. One run improvised this across seven tool calls and reported a verification it had invented. |
| **`ci-applies-migrations`** | Migrations are applied by CI on merge, not by this session | Step 2 is a **permanent no-op** and must be reported as such. Confirming migrations "applied" here would be false: they are applied later, by something else. Check instead that the migration files are present and committed. |
| **`no-deployables`** | Library or package with no runtime to deploy | Steps 3 and 8.1 do not apply. Step 8.4 (full suite on the merged default branch) still does — it is the measurement nobody else takes. |
| **`local-merge`** | The project's `CLAUDE.md` forbids autonomous pull requests | Step 6 is skipped entirely. Resolve this at Step 0, never at Step 6: two runs hit the identical classifier block 36 hours apart and reached opposite outcomes, and the one that halted for ~46 minutes had been blocked on a path its project never wanted. |

## The rule underneath all of them

**A step that cannot apply is routed past and reported, not silently completed and not improvised.** The three observed failures are all the same shape from different angles: a docs vault where three steps did not apply and the run had to work that out live; an infrastructure repo where a verification was invented because the step demanded one; and a project where migrations were CI-applied so the migration step could only ever have reported someone else's work as its own.

A repo can also be more than one shape at once — a docs-only diff in an `app` repo takes the `docs-only` lane for this run only.

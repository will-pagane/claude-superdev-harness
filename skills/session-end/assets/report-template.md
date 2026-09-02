# Close-out report template — four shapes

Pick the variant matching **how this branch actually landed**, not how you expected it to. Print inline, in the user's language, composed from the ledger.

**DELETE every section with nothing in it.** Never write "N/A", "nenhum", or leave an empty heading.

The default shape below opens with a PR number. A report that opens that way when there was no PR reads as *the merge did not happen* — one did, and the user answered *"mas porque voce nao mergeou?"*, costing a whole turn proving ancestry. Two other runs improvised the missing line. Hence four variants.

---

## Variant A — merged via pull request

**Mergeado** — PR number and URL, commit range, what shipped.

## Variant B — merged locally, no pull request

**Mergeado localmente** — merge commit SHA, commit range, what shipped, and the confirmation used: `git branch -r --contains <sha>` naming the default branch.

**Name which of the two reasons applies — this field is required, not optional:**

- *the project mandates it* — its `CLAUDE.md` forbids autonomous pull requests, so the PR path was never taken; or
- *the harness blocked `gh`* — the permission classifier refused it, the bare retry also failed, and the run took the local merge lane rather than stalling. Say so plainly; it is not a failure of the branch.

Without the reason, a missing PR reads as an omission or as a merge that did not happen.

## Variant C — nothing to merge, nothing to delete

**Nada a mergear** — say what state the branch was actually in and how you established it: already contained in the default branch (`git log <branch> --not origin/<default>` empty), or never diverged. Name the SHA the default branch already carries.

Then say **explicitly**: no PR to open, no branch to delete, and *the work is already on the default branch* — that last clause is the one whose absence caused the misunderstanding.

## Variant D — multi-branch close-out

One **Mergeado** block per branch, in merge order, each with its own commit range and confirmation.

Then a single line stating the order and **why each branch held its position** — a merge forced by containment looks identical to one forced by a dependency, and only the first means a later review was empty. If branches collapsed, say which one carried everything and that the others were closed as contained.

---

Every variant then continues with the sections below.

## Aplicado em produção

Migrations applied (with ledger confirmation) and functions deployed (with how each was verified **after** the merge, not before). Who executed and who verified are two fields, not one.

## Pendências registradas

Each item written to the pendings file, with its file path.

## Pendências reconciliadas

Step 4's Half A, reported as **four counts, every one of them stated even when zero** — a reconciliation with no residual bucket cannot tell you it missed something:

- **fechadas** — entries deleted because this session resolved them, listed by heading.
- **reescritas (`stale-cause`)** — entries whose stated cause or unblock stopped being true while the defect survived. **Say what the old text claimed and why it was wrong**, because this is the lane that silently converts a live bug into a closed one.
- **atualizadas** — entries whose numbers, paths or branch-state claims were corrected in place.
- **intocadas** — the count your diff does not reach.

Closing is easy to omit, because the report is built from what you *wrote* and a deleted entry leaves nothing to point at — yet on a cleanup-heavy branch it is often the larger half of the work. One close-out reported 13 opened and said nothing about **17 closed**, until the user asked outright. A later one merged four branches, deployed, drained a production queue, and left three entries describing a world that had ended two hours earlier — one of which would have made the next reader close a bug that was still live.

## Verificação

What ran, what it returned, and **what was routed past and why** — a repo shape with no suite, a docs-only diff that ran the formatter instead of the type checker, a migration step that is a no-op because CI applies them. A skipped step reported as skipped is information; reported as complete it is a lie.

Any gate laned as `pre-existing-on-base` or `environmental` goes here with its proof.

## Você precisa revisar

What only a human can check: visual and UX, live end-to-end, external panel configuration.

## Limpeza

Branch and worktree removed, or exactly why one survived. Name any gitignored artifact that was relocated or de-referenced before the worktree went.

## Deixado de fora

Untracked or unrelated files left in the working tree, and anything cut. Files outside the branch's purpose are named here, never swept into the commit.

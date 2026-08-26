# Close-out report template — four shapes

Pick the variant matching **how this branch actually landed**, not how you expected it to. Print inline, in the user's language, composed from the ledger.

**DELETE every section with nothing in it.** Never write "N/A", "nenhum", or leave an empty heading.

The default shape below opens with a PR number. A report that opens that way when there was no PR reads as *the merge did not happen* — one did, and the user answered *"mas porque voce nao mergeou?"*, costing a whole turn proving ancestry. Two other runs improvised the missing line. Hence four variants.

---

## Variant A — merged via pull request

**Mergeado** — PR number and URL, commit range, what shipped.

## Variant B — merged locally, no pull request

**Mergeado localmente** — the project's `CLAUDE.md` mandates local merge, so no PR was opened. Merge commit SHA, commit range, what shipped, and the confirmation used: `git branch -r --contains <sha>` naming the default branch.

State the *reason* there is no PR. Without it, the absence reads as an omission.

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

## Pendências fechadas

Each item **removed** from the file because this session resolved it.

Easy to omit, because the report is built from what you wrote and closing an item leaves nothing to point at — but on a cleanup-heavy branch it is often the larger half of the work. One close-out reported 13 opened and said nothing about **17 closed**, until the user asked outright.

## Verificação

What ran, what it returned, and **what was routed past and why** — a repo shape with no suite, a docs-only diff that ran the formatter instead of the type checker, a migration step that is a no-op because CI applies them. A skipped step reported as skipped is information; reported as complete it is a lie.

Any gate laned as `pre-existing-on-base` or `environmental` goes here with its proof.

## Você precisa revisar

What only a human can check: visual and UX, live end-to-end, external panel configuration.

## Limpeza

Branch and worktree removed, or exactly why one survived. Name any gitignored artifact that was relocated or de-referenced before the worktree went.

## Deixado de fora

Untracked or unrelated files left in the working tree, and anything cut. Files outside the branch's purpose are named here, never swept into the commit.

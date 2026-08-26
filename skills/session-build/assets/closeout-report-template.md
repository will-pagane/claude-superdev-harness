# Close-out report template

Fill this and print it inline, in the user's language. Compose from the ledger, never from memory.

**DELETE every section with nothing in it.** Do not write "N/A", "nenhum", "nada a reportar", or leave an empty heading — an empty section reads as an unanswered question, and several of these sections being empty is a *claim* that must be checked before it is made.

Section names below are Portuguese because the report is user-facing; the skill itself stays English.

---

## Specs

One line per spec: file path, and the one-sentence design it captured.

## Branches

One line per branch: name, commit range, what shipped, verification result.

State how many branches carry **distinct** work — tested by ancestry, not assumed from the spec count — with the timestamp of that measurement. If they collapsed, say which single branch to close and why.

## Aplicado em produção

Migrations applied (with ledger confirmation) and functions deployed (with how each was verified), per branch.

**Who executed and who verified are two fields, not one.** Where one fork deploys a surface another owns, both "I deployed it" and "not verified by me" are false. The honest line names them separately — *"deployed by fork B; I verified its result on the critical target, from the deployed bundle: marker present, auth gate intact, zero matches for the forbidden call"*.

## Aplicado em produção sem merge

Any migration applied before its branch merged — **this skill's normal design, not an exception.** If the user never merges, production carries the schema and the repository does not, and nothing else will tell them.

## Aplicado sem código

Any migration applied by a branch that was abandoned or left incomplete, named individually. The database kept it; git did not. **This section being empty is a claim** — make it only after checking.

## Ordem de merge

The dependency order, explicitly, when one branch was based on another.

**State the reason each branch holds its position, not just the sequence.** A merge forced by containment looks identical to one forced by a dependency, and only the first means a later review will be empty. If the number of independently reviewable branches dropped during the run, say so here and say when.

## Você precisa revisar

What only a human can check: visual and UX, live end-to-end, external panel configuration, anything observable only in production.

Frame this as the point of the handoff, not as a caveat. Automated review and a human opening the screen catch **disjoint** classes of defect.

## Adiado / parked

Every deferred finding from every fork's ledger, with its ruling — file and line, the number measured and how, the shape of the fix, the exposure left open. Mark any single-window proof as such.

## Adiado com documento

Work fully specified and waiting on a precondition — a post-merge runbook, for instance. Neither `CUT` (that would say abandoned) nor `PARKED` (that would say it is an idea). **Name the precondition**, because it is often the merge itself.

## Não feito

Anything cut from a spec, and why.

## Próximo passo

The branches are pushed and verified, awaiting review. Then `/session-end`.

Say **which** session runs it and how: the orchestrator can enter each worktree in sequence and close each branch, which is the cheapest path since it already holds the whole picture; a fresh session launched from the worktree directory is equally valid. Warn that `/session-end`'s step 0 stops on the default branch — inside this run that means *enter each worktree*, not *abort* — and that a session inside a worktree has compound bash refused.

Name the handoff file: `.superpowers/session-build/<RUN_ID>/handoff.md`.

## Pendências desta sessão

Anything the run itself left in a state the next session must know about: a lock never released, a worktree holding gitignored artifacts the pendings cite, a fork that died and was never revived.

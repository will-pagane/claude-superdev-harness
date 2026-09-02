#!/usr/bin/env bash
# assert-findings.sh - one assertion per content finding from the evidence
# document. "The findings landed" is otherwise a claim.
#
# Fixed strings (grep -qF), never regexes: this content is markdown and
# escaping it into an ERE is how an assertion quietly stops discriminating.
# And never grep -c, which exits 1 on a zero count and inverts exactly the
# assertions whose answer should be zero.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"

want() {  # want <id> <file> <distinctive literal clause>
  if grep -qF -- "$3" "$HERE/$2" 2>/dev/null; then ok "$1"; else bad "$1  ($2)"; fi
}



# --- B: Step 1 triage lanes -------------------------------------------------
want B1-incomplete       steps/step-01-verify.md 'the log carries no summary line from the runner itself'
want B1-not-a-red        steps/step-01-verify.md 'Re-run scoped, split or in the background'
want B2-flaky            steps/step-01-verify.md 'green in isolation, green on a clean checkout of the base'
want B3-foreign          steps/step-01-verify.md 'It is not yours to fix and not yours to triage further'
want B3-proof            steps/step-01-verify.md 'git show HEAD:<path>'
want B4-artifact         steps/step-01-verify.md 'That is a *gate order* problem, not an installation one'
want B5-cache            steps/step-01-verify.md 'A cached exit code is a recording of an older tree'
want B6-deselect         steps/step-01-verify.md 'overstates coverage until the deselection is named'
want C2-tree-that-lands  steps/step-01-verify.md 'Verify the tree that will land, not the branch tip'
# --- C/D: Step 0 checks -----------------------------------------------------
want C1-refetch     steps/step-00-inventory.md 'Record the SHA **and the timestamp** both times'
want C1-stopped     steps/step-00-inventory.md 'a result about a tree that no longer exists is not a result'
want C4-wallclock   steps/step-00-inventory.md 'On resume, read the clock before you trust anything'
want D6-peers       steps/step-00-inventory.md '`ListAgents` lists them; `SendMessage` reaches them'
want D6-authority   steps/step-00-inventory.md 'A peer is a colleague, not an authority'
# --- D: Steps 5-7 -----------------------------------------------------------
want D3-ledger-gate   references/traps.md 'the remote ledger holding rows with no local file is the **normal** state'
want D3-restore       references/traps.md 'git restore --source=<ref> --worktree -- <paths>'
want D3-never-co      references/traps.md '**Never `git checkout`**, which writes the index'
want D3-rederive      references/traps.md 'Re-derive the row list at the moment of use'
want D4-ancestry      references/traps.md 'Split **by ancestry**, which needs no cherry-pick'
want D4-not-elapsed   references/traps.md 'The gate between them is the first pipeline going green'
want D2-generated     steps/step-07-merge.md '**Regenerate it from that source.** Never a merge, never a side'
want D2-union         steps/step-07-merge.md 'union-already-computed'
want D2-union-test    steps/step-07-merge.md 'does either side'"'"'s content already contain the other'"'"'s?'
want D1-holds-default steps/step-07-merge.md 'Merge in a dedicated worktree on the default branch instead'
want D1-stop-resume   steps/step-07-merge.md 'A peer worktree already holds the default branch'
want R-two-guards     SKILL.md 'Two guards, and only one of them stops this run'
want R-correctness    SKILL.md 'reaching the effect by disarming a correctness guard'
want R-route-named    SKILL.md 'a merge whose route is not stated reads as a merge that did not happen'
want R-traps-rewrite  references/traps.md 'Those four read the rule correctly as it was written. The rule was wrong'
want R-traps-kept     references/traps.md 'their verdict changed on 2026-09-02'
# --- Steps 8-9 --------------------------------------------------------------
want C5-merged-sha   steps/step-08-sync-and-cleanup.md 'Verify production serves the **merged SHA, by identifier**'
want A4-two-preds    references/traps.md '`git branch -d` has two predicates, not one'
want A4-detach       references/traps.md 'git worktree add --no-checkout --detach <merge-sha>'
want A5-tree-level   references/traps.md 'Record that tree-level proof, per file, in the ledger'
want D5-nongit       references/traps.md '`Permission denied`, `Directory not empty`, `Filename too long`'
want D5-exit0-lie    references/traps.md 'exited 0 while leaving the directory in place'
want D1-partial      references/traps.md 'Partial cleanup is a legitimate terminal state'
# --- Decision 4 -------------------------------------------------------------
want I-ledger-vocab  ../session-build/scripts/ledger.py 'PENDINGS-RULING'
want I-fork-init     ../session-build/scripts/ledger.py 'a fork could not create its own ledger'
want I-agentid       ../session-build/steps/step-06-closeout.md 'agentId'
# --- Fork lane --------------------------------------------------------------
want FL-lock-resource steps/lane-fork-orchestrator.md 'a grant with no resource matches nothing'
want FL-never-edits   steps/lane-fork-orchestrator.md 'It emits rulings and never edits the pendings file'
want FL-once          steps/lane-fork-orchestrator.md 'committed on the last branch in merge order'
want FL-no-worktree   steps/lane-fork-orchestrator.md 'The orchestrator never enters a worktree'
want FL-self-lock     steps/lane-fork-orchestrator.md 'not exempt from the rule it enforces'
want FL-degrade       steps/lane-fork-orchestrator.md 'never assumes a fork remembers anything'
want FL-unexercised   steps/lane-fork-orchestrator.md 'This lane is unexercised'
want FL-limitation    steps/lane-fork-orchestrator.md 'is weaker for the last branch in merge order'
want FC-expect        references/fork-contract.md 'A gate that did not finish did not decide'
want FC-merge-order   references/fork-contract.md 'MERGE origin/<default> BEFORE verify'

finish

# session-end router + fork lane + content rewrite — Implementation Plan

> **For agentic workers:** This plan is executed **inline, one task at a time**, by the fork that owns it. `superpowers:subagent-driven-development` is UNAVAILABLE here — a fork's boilerplate forbids the `Agent` tool, hard and non-overridably. Keep SDD's discipline without its parallelism: one task, its verification run and *read*, then the next. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn `skills/session-end/` from a 36,761-byte monolith into a router plus just-in-time step files, give it a fork lane for multi-branch close-out, and fold in the findings from all 20 real `session-end` ledgers.

**Architecture:** Three commit phases that never interleave — (1) baseline: the un-propagated `~/.claude` text lands in the repo unchanged; (2) mechanical split: text moves, nothing is written; (3) content: one commit per evidence section. The split diff and the content diff must never share a commit, because a 36 KB file reshaped into ten is already hard to review and content changes hidden inside that reshape are invisible.

**Tech Stack:** Markdown, POSIX `sh` (`gate.sh`), PowerShell 5.1 (`gate.ps1`), Python 3 (`ledger.py`). No package manager, no test framework, no application code.

**Spec:** `docs/superpowers/specs/2026-09-02-session-end-router-and-fork-lane-design.md`
**Evidence:** `docs/superpowers/specs/2026-09-02-session-end-run-evidence.md`

---

## Global Constraints

Copied verbatim from the spec and the dispatch. Every task's requirements implicitly include this section.

- **Steps 0–10 keep their numbers in the prose.** Files group steps; the prose keeps saying "Step 4", "Step 7". Fourteen cross-references to `Step N` live outside `SKILL.md`. Renumbering breaks all fourteen silently.
- **`SKILL.md` ≤ 12,288 bytes. No step file above 8,192 bytes.**
  The spec estimated 7,168; the split measured otherwise, so the number moved and the reason
  is recorded rather than the check quietly relaxed. `step-04-pendings.md` lands at **7,952**:
  6,307 of that is Step 4's body, which the spec requires to move *verbatim*; ~600 is the
  invariant recap every step file must carry; ~1,000 is its own four *Common mistakes* rows
  and two *Red flags* entries, which belong to that step and nowhere else. 7,168 left roughly
  260 bytes of headroom for 1,000 bytes of content, so it was infeasible against a constraint
  the spec imposes elsewhere in the same document. Every other step file is under 6,100 and
  the router is 8,144, so the cap binds exactly one file.
- **This repo runs NO local git hooks.** `core.hooksPath` is unset and `.git/hooks` holds only samples. A clean commit proves nothing; every gate is one you run explicitly and read yourself.
- **Gate path is `$SKILL/scripts/gate.sh`** where `SKILL=$HOME/.claude/skills/session-build` — the *skill's* script, absolute. This repo has no `scripts/` directory of its own.
- **Isolation:** every `Read`/`Write`/`Edit` takes an absolute path under `$WT`; every `Bash` call `cd`s into `$WT` in the same command; `git -C "$WT" branch --show-current` must print `refactor/session-end-router-fork-lane-20260902` before **every** commit.
- **Never write into `C:/Users/willi/.claude/skills/**`.** It is the live copy of the running skills. Read it; never write it.
- **Forbidden:** `gh pr create` · any merge · `finishing-a-development-branch` · force-push · `--no-verify` · `--squash` · committing on the default branch · deleting any branch or worktree · touching the peer fork's files (`install.sh`, `scripts/check-drift.sh`, `.github/workflows/lint.yml`, `README.md`) · writing `docs/superpowers/specs/**`.
- **Line endings:** the repo checkout normalises. Always compare with `\r` stripped (`diff <(tr -d '\r' < A) <(tr -d '\r' < B)`) or you will see 23 false diffs where there are 5.
- **Language:** the skills are written in English; `docs/cadeia-session.md` is written in Brazilian Portuguese. Each file keeps its own language.
- **No em-dash rule does not apply here** — these are engineering documents, not NOVARC brand text. Match the surrounding prose of the file being edited.

### Shell variables every task assumes

```bash
WT="C:/dev/Projects/claude-setup/.claude/worktrees/session-end-router-fork-lane-20260902"
SKILL="$HOME/.claude/skills/session-build"
HOME_SE="$HOME/.claude/skills/session-end"
LEDGER="C:/dev/Projects/claude-setup/.superpowers/session-build/20260902-0447"
SLUG="session-end-router-fork-lane"

# Git Bash does not guarantee TMPDIR. Define it ONCE, here, and validate it -
# round 2 caught that scripts defined it internally while standalone steps used
# it bare, so `rm -rf "$TMPBASE/t2"` could have expanded to `rm -rf /t2`.
TMPBASE="${TMPDIR:-/tmp}"
case "$TMPBASE" in /|"") echo "refusing TMPBASE=$TMPBASE" >&2; exit 1 ;; esac
mkdir -p "$TMPBASE" || exit 1

export WT SKILL HOME_SE LEDGER SLUG TMPBASE

# Round 9: an `onbranch` helper defined here could not work - the plan states
# two lines above that every Bash call is a fresh process, so a function
# defined in this block is gone by the next command. The guard is therefore
# INLINED at every commit site, in the same invocation as the commit:
#
#   cd "$WT" && test "$(git branch --show-current)" = "<branch>" && git add ... && git commit ...
#
# One invocation, so the branch cannot change between the check and the commit.
```

**Each Bash tool call is its own process and inherits nothing from the last.** Round 3 caught the first draft asserting these were "exported" while only assigning them. Paste the block above at the top of any step that references them, or write it to a file and `source` it — an unset `$TMPBASE` in `rm -rf "$TMPBASE/t2"` is the failure this guards.

### Every check in this plan must be able to fail

**Round 1 of this plan's own codex-review found that most of its verification could not go red** — the exact defect the skill being rewritten exists to prevent. Corrected globally; these bind every task below.

- **Never `cmd; echo "exit=$?"`.** The compound exits 0 whatever `cmd` did, so a step that looks like a gate is a print statement.
- **Never a bare `for` loop over gates.** A loop returns its *last* iteration's status, so a failure followed by a pass reads green.
- **Never a check that only prints.** A byte budget that echoes sizes, an identity check that echoes `DRIFT`, a cross-reference sweep that echoes `ORPHAN` — none of them fail.

`skills/session-end/verify/lib.sh`, sourced by every check script:

```bash
#!/usr/bin/env bash
# lib.sh — shared assertion helpers. Sourced, never executed.
#
# Exists because round 1 of this plan's own review found that most of its
# verification was structurally incapable of failing. A check that cannot go
# red is a print statement wearing a gate's clothes.

TMPBASE="${TMPDIR:-/tmp}"      # Git Bash does not guarantee TMPDIR
FAILED=0

ok()  { printf 'PASS %s
' "$*"; }
bad() { printf 'FAIL %s
' "$*"; FAILED=1; }

# finish — the ONLY way these scripts end. Non-zero if anything failed.
finish() {
  if [ "$FAILED" -eq 0 ]; then printf '
ALL CHECKS PASSED
'; else printf '
CHECKS FAILED
'; fi
  exit "$FAILED"
}
```

Every invocation below is `bash <script>` and every expected result is stated as an **exit code**, never as printed text.

### How "TDD" works in a repo with no test framework

There is no runner to make red. The equivalent that genuinely holds here:

1. Write the assertion into `verify/assert-findings.sh` **first**.
2. Run it and **watch that named assertion fail** in the output.
3. Write the content.
4. Run it and watch it pass.

**Step 2 is not a formality, and round 1 proved it.** Several first-draft assertions — `D2-generated` matching the word "generated", `C1-refetch` matching "fetch", `I-fork-init` matching "fork" — would have matched prose **already in the file**, so they could never fail and would have certified content nobody wrote. **An assertion that passes before the content exists is a broken assertion, not an early success.**

So the rule is stronger than "watch it fail": **assert a distinctive full clause or a structural table row, never a bare word.** `'Regenerate it from that source'` discriminates; `'generated'` does not. If an assertion passes at step 2, tighten it until it fails, then continue.

`grep -q` exits 1 on no match, which is the failure signal. Beware the inverse the skill documents: `grep -c` exits 1 on a zero count, inverting exactly the assertions whose answer should be zero. Use `grep -q`, never `grep -c`.

---

## File Structure

**Created — `skills/session-end/`**

| File | Responsibility |
|---|---|
| `steps/step-00-inventory.md` | Step 0. Lane routing, the three-lane table, compound-bash rule, re-fetch cadence, wall-clock-on-resume, peers |
| `steps/step-01-verify.md` | Step 1. Six triage lanes, cached-green, deselection reporting, verify-the-tree-that-lands |
| `steps/step-02-production-state.md` | Steps 2 and 3. Migrations, edge functions |
| `steps/step-04-pendings.md` | Step 4 **verbatim**, plus a recap header and one fork-lane paragraph. Nothing else. |
| `steps/step-05-push-and-pr.md` | Steps 5 and 6. Pre-push ledger gate, the route ladder, split-by-ancestry, *Making this deterministic* |
| `steps/step-07-merge.md` | Step 7. Four conflict lanes, who-holds-the-default-branch pre-check |
| `steps/step-08-sync-and-cleanup.md` | Steps 8 and 9. Merged-SHA proof, three cleanup facts, partial cleanup as a terminal state |
| `steps/step-10-report.md` | Step 10 |
| `steps/lane-fork-orchestrator.md` | The fork lane — orchestrator side |
| `references/fork-contract.md` | The fork lane — fork side |
| `dispatch-prompts.md` | The fork lane — dispatch payload |
| `verify/assert-findings.sh` | Every content assertion, one runnable script |
| `verify/reconstruct.sh` | The split's reconstruction check |

**Modified**

| File | Change |
|---|---|
| `skills/session-end/SKILL.md` | Becomes the router |
| `skills/session-end/references/traps.md` | `#classifier-denials` rewritten, not deleted |
| `skills/session-end/assets/report-template.md` | Baseline only; no content change |
| `skills/session-end/scripts/gate.sh` · `gate.ps1` | `--expect` |
| `skills/session-build/scripts/gate.sh` · `gate.ps1` | `--expect` — **byte-identical to session-end's copies** |
| `skills/session-build/scripts/ledger.py` | `READY`/`PENDINGS-RULING`/`CLOSED`, and the fork-ledger-creation defect |
| `skills/session-build/steps/step-06-closeout.md` | `handoff.md` gains `spec slug → agentId` |
| `skills/session-build/references/fork-contract.md` | `--expect`, and `MERGE origin/<default> BEFORE verify` |
| `docs/cadeia-session.md` | Three lanes; and the `EnterWorktree` premise it still states wrongly |

**Four copies of gate, not two.** `skills/session-end/scripts/gate.sh` and `skills/session-build/scripts/gate.sh` are **byte-identical today** (verified with `cmp`), as are both `gate.ps1`. `gate.ps1` already carries `NOTE: duplicated verbatim in skills/session-end/scripts/gate.ps1. Change both or neither.` — `gate.sh` does not, and gains it. Task 3 patches all four and asserts identity.

---

## Task 1: Baseline — land the un-propagated `~/.claude` text unchanged

**Why this is first and alone:** four files in this surface exist in `C:/Users/willi/.claude/skills/` **only**, committed nowhere, with no history and no backup. Two are Will's Step 4 pendings rewrite from 2026-09-02. If they land as part of the restructure, the split's diff swallows them and nobody reviews them.

**The spec names two files. This task copies five, and the extra three are not scope creep** — they are the same rule applied consistently. `ledger.py` and `step-06-closeout.md` are also un-propagated, are also in this fork's surface, and are *modified by Task 3 and Task 8*. Committing a modification on top of an uncommitted baseline destroys exactly what the baseline commit exists to protect.

> **`steps/step-02-scope-and-collisions.md` was added to this task after codex-review approved the plan, by orchestrator directive.** It carries the 2026-09-02 `PENDINGS-SOURCE` recording rule, it was in no fork's surface, and it was therefore the one file in the drift set that nothing in this run would have landed. The orchestrator granted it and re-measured the whole drift set to confirm nothing else is orphaned.
>
> **It is an UPDATE, not a create** — a framing I got wrong when I raised it. `git cat-file -e HEAD:skills/session-build/steps/step-02-scope-and-collisions.md` succeeds; the file is tracked and only the edit is uncommitted. Verified before writing this.
>
> No new review round: this is not a new design but the identical baseline-copy operation the review already approved for `SKILL.md` and `report-template.md`, applied to a third file with the same provenance, the same failure mode and the same verification shape. **Self-review of the added step:** it copies one tracked file from a read-only source, is covered by both existing identity checks (byte and normalised), adds no new interface, is committed in the same phase-1 commit whose whole purpose is text that lives on one disk, and touches nothing any later task modifies — `step-02` is not edited by Tasks 2 through 10, so no diff can swallow it later.

**Files:**
- Modify: `skills/session-end/SKILL.md`
- Modify: `skills/session-end/assets/report-template.md`
- Modify: `skills/session-build/scripts/ledger.py`
- Modify: `skills/session-build/steps/step-06-closeout.md`
- Modify: `skills/session-build/steps/step-02-scope-and-collisions.md` (granted post-approval)

**Interfaces:**
- Produces: the exact byte content every later task edits. Task 2 splits `SKILL.md` from this baseline, not from the repo's older copy.

- [ ] **Step 1: Confirm exactly which files differ, normalised**

Round 2: printing the differences is not a check — it neither rejects an extra file nor notices a missing one. Compare the actual set against the expected set and let `diff` be the gate.

```bash
cd "$WT" && (cd skills && find session-end session-build -type f | sort) | while IFS= read -r f; do diff -q <(tr -d '\r' < "skills/$f") <(tr -d '\r' < "$HOME/.claude/skills/$f") >/dev/null 2>&1 || printf '%s\n' "$f"; done > "$TMPBASE/actual-drift.txt"
```

```bash
cd "$WT" && printf '%s\n' session-build/scripts/ledger.py session-build/steps/step-02-scope-and-collisions.md session-build/steps/step-06-closeout.md session-end/SKILL.md session-end/assets/report-template.md > "$TMPBASE/expected-drift.txt" && diff "$TMPBASE/expected-drift.txt" "$TMPBASE/actual-drift.txt"
```

Expected: exit 0, no output. **A non-zero exit means the baseline is not what this plan measured** — either someone edited `~/.claude` during this run, or a file this plan expected to differ no longer does. Report `BLOCKED` with the diff; do not proceed on a guess.

- [ ] **Step 2: Read the diff of each of the five files you are about to copy**

Do not copy blind. Read what changes, so the commit message can describe it and so a surprise surfaces now rather than at review.

```bash
cd "$WT" && diff <(tr -d '\r' < skills/session-end/SKILL.md) <(tr -d '\r' < "$HOME/.claude/skills/session-end/SKILL.md")
```

Repeat for `assets/report-template.md`, `scripts/ledger.py`, `steps/step-06-closeout.md`, `steps/step-02-scope-and-collisions.md`.

Expected shape: `SKILL.md` gains Step 4's "RECONCILE first, then collect" rewrite (Half A, the four-lane table, `stale-cause`), two *Common mistakes* rows and one red flag. `report-template.md` turns *Pendências fechadas* into *Pendências reconciliadas* with four counts. `ledger.py` adds `PENDINGS-SOURCE` to `BOOKKEEPING`. `step-06-closeout.md` adds the `PENDINGS-SOURCE` field to `handoff.md`. `step-02-scope-and-collisions.md` gains the ten-line block instructing a run to record `PENDINGS-SOURCE` per spec before proceeding.

- [ ] **Step 3: Copy all five, verbatim**

```bash
cd "$WT" && cp "$HOME/.claude/skills/session-end/SKILL.md" skills/session-end/SKILL.md
cd "$WT" && cp "$HOME/.claude/skills/session-end/assets/report-template.md" skills/session-end/assets/report-template.md
cd "$WT" && cp "$HOME/.claude/skills/session-build/scripts/ledger.py" skills/session-build/scripts/ledger.py
cd "$WT" && cp "$HOME/.claude/skills/session-build/steps/step-06-closeout.md" skills/session-build/steps/step-06-closeout.md
```

```bash
cd "$WT" && cp "$HOME/.claude/skills/session-build/steps/step-02-scope-and-collisions.md" skills/session-build/steps/step-02-scope-and-collisions.md
```

- [ ] **Step 4: Prove the copy is identical, and say precisely what that means**

Round 1 caught an overclaim here: the first draft said "byte-exact" while comparing with every carriage return deleted, which permits real byte differences. Two claims, stated separately because they are different claims.

**(a) Byte identity of the copy itself** — `cp` should have produced exactly the source bytes:

```bash
cd "$WT" && rc=0; for f in session-end/SKILL.md session-end/assets/report-template.md session-build/scripts/ledger.py session-build/steps/step-06-closeout.md session-build/steps/step-02-scope-and-collisions.md; do cmp -s "skills/$f" "$HOME/.claude/skills/$f" || { echo "BYTE-DIFF $f"; rc=1; }; done; exit $rc
```

Expected: exit 0. If this fails but (b) passes, the difference is line endings only — record that explicitly rather than calling it identical.

**(b) Textual identity ignoring line endings** — the claim that survives the repo's `.gitattributes` normalisation:

```bash
cd "$WT" && rc=0; for f in session-end/SKILL.md session-end/assets/report-template.md session-build/scripts/ledger.py session-build/steps/step-06-closeout.md session-build/steps/step-02-scope-and-collisions.md; do diff -q <(tr -d '\r' < "skills/$f") <(tr -d '\r' < "$HOME/.claude/skills/$f") >/dev/null || { echo "TEXT-DIFF $f"; rc=1; }; done; exit $rc
```

Expected: exit 0. Both loops accumulate `rc` rather than returning the last iteration's status.

- [ ] **Step 5: Run the repo's own gates on the copied Python**

```bash
cd "$WT" && "$SKILL/scripts/gate.sh" baseline-ledger-py python -c "import ast,sys; ast.parse(open('skills/session-build/scripts/ledger.py',encoding='utf-8').read())"
```

Expected: `GATE baseline-ledger-py EXIT 0 LOG <path> LINES 0`

- [ ] **Step 6: Verify the branch, then commit**

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902"
```

Expected: exit 0. A non-zero exit means you are not on this fork's branch — **STOP**, and do not commit. Round 7: printing the branch name cannot enforce the rule that this run never commits on the default branch.

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-end/SKILL.md skills/session-end/assets/report-template.md skills/session-build/scripts/ledger.py skills/session-build/steps/step-06-closeout.md skills/session-build/steps/step-02-scope-and-collisions.md && git commit -F- <<'EOF'
docs(skills): land the session-end text that lived only on one disk

Five files were edited in ~/.claude and committed nowhere: session-end's
Step 4 rewrite (reconcile before collect, the four lanes, stale-cause),
the report template's four reconciliation counts, and the PENDINGS-SOURCE
plumbing in session-build's ledger.py, step-06 and step-02.

They land here unchanged and alone, before the restructure touches them.
A 36KB file reshaped into ten is already hard to review; this text hidden
inside that reshape would not be reviewed at all.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 7: Write the ledger line**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "1/10 baseline landed. Four files copied verbatim from ~/.claude and committed alone: session-end/SKILL.md, session-end/assets/report-template.md, session-build/scripts/ledger.py, session-build/steps/step-06-closeout.md. Two claims proved separately: byte identity with cmp, and textual identity with a normalised diff - the first draft called the second byte-exact, which it is not. The spec named two files; the other two are in this surface AND are modified by tasks 3 and 8, so committing a change on top of an uncommitted baseline would destroy exactly what the baseline exists to protect. session-build/steps/step-02-scope-and-collisions.md is a FIFTH un-propagated file and is NOT in this fork's surface - reported to the orchestrator, not taken."
```

---

## Task 2: Mechanical split — router plus step files, moving text only

**The rule for this whole task: no sentence gains or loses a word.** Text moves. The only additions permitted are (a) each step file's invariant-recap header, (b) each step file's `## NEXT` pointer, (c) the router's entry-point table and loading-discipline block. Everything else is a cut-and-paste, and the reconstruction check in Step 6 is what proves it.

**Files:**
- Modify: `skills/session-end/SKILL.md` → router
- Create: `skills/session-end/steps/step-00-inventory.md`, `step-01-verify.md`, `step-02-production-state.md`, `step-04-pendings.md`, `step-05-push-and-pr.md`, `step-07-merge.md`, `step-08-sync-and-cleanup.md`, `step-10-report.md`
- Create: `skills/session-end/verify/reconstruct.sh`

**Interfaces:**
- Produces: the file layout every content task edits. Task 4 edits `steps/step-01-verify.md`; Task 6 edits `steps/step-05-push-and-pr.md` and `steps/step-07-merge.md`; and so on.

**Section-to-file map, with measured byte counts from the baseline `SKILL.md` (36,761 bytes total, 313 lines):**

| Source section | Bytes | Destination |
|---|---|---|
| preamble (before first `##`) | 1,154 | router |
| `## Authorization` | 1,814 | router |
| `## Never bypass a gate — and here is what counts as one` | 1,487 | router |
| ``## Run gates through `scripts/gate.sh` `` | 489 | router |
| `## Project rules win` | 763 | router |
| `## Ledger` | 470 | router |
| `## Common mistakes` | 3,113 | **split** — cross-cutting rows stay in router, step-specific rows move |
| `## Red flags — stop` | 1,377 | **split** — same rule |
| `## Step 0 — Pre-flight inventory` | 3,806 | `steps/step-00-inventory.md` |
| `## Step 1 — Verify before anything irreversible` | 2,465 | `steps/step-01-verify.md` |
| `## Step 2 — Migrations` | 1,075 | `steps/step-02-production-state.md` |
| `## Step 3 — Edge functions` | 697 | `steps/step-02-production-state.md` |
| `## Step 4 — Pendings: RECONCILE first, then collect` | 6,307 | `steps/step-04-pendings.md` |
| `## Step 5 — Commit and push` | 203 | `steps/step-05-push-and-pr.md` |
| `## Step 6 — Pull request` | 2,383 | `steps/step-05-push-and-pr.md` |
| `## Making this deterministic — suggest it, do not do it` | 1,598 | `steps/step-05-push-and-pr.md` |
| `## Step 7 — Merge` | 3,557 | `steps/step-07-merge.md` |
| `## Step 8 — Post-merge sync` | 1,010 | `steps/step-08-sync-and-cleanup.md` |
| `## Step 9 — Cleanup` | 2,114 | `steps/step-08-sync-and-cleanup.md` |
| `## Step 10 — Report` | 879 | `steps/step-10-report.md` |

Router after the split ≈ 1,154 + 1,814 + 1,487 + 489 + 763 + 470 ≈ 6,177 bytes of moved text, plus the trimmed cross-cutting halves of *Common mistakes* and *Red flags* (≈ 1,900), plus the new entry-point and loading-discipline blocks (≈ 2,500). **Budget ≈ 10,600 of the 12,288 cap.**

**`step-04-pendings.md` is the file that broke the 7,168 cap** — measured at 7,952, which is why the cap is 8,192 and why that number carries its measurement in `budgets.sh` —  — 6,307 bytes of verbatim text plus a recap header. It therefore receives **no** content additions in Task 4 onward beyond the single fork-lane paragraph the spec already allows. If it exceeds the cap, the fork-lane paragraph moves to `lane-fork-orchestrator.md` and `step-04-pendings.md` gets a one-line pointer instead.

- [ ] **Step 1: Write the reconstruction check first**

Round 1 of this plan's review killed the first design. It compared **sorted line multisets with blank lines dropped**, which cannot distinguish a faithful split from shuffled table rows, and its only demonstrated failure mode was a missing file. Replaced by a check that is byte-exact per file and proves itself against real mutations.

`skills/session-end/verify/reconstruct.sh`:

```bash
#!/usr/bin/env bash
# reconstruct.sh - prove the split MOVED text and wrote none.
#
# Two claims, both enforced for the ROUTER as well as the step files. Round 3
# caught that the router's retained text was only multiset-checked, so its
# sections could be reordered freely while reconstruction passed - the exact
# round-1 defect, surviving in the one file nobody was checking.
#
#   FIDELITY  every retained BLOCK, in every file, appears verbatim and
#             contiguously in the original. This is what preserves blank lines
#             and ordering INSIDE a block.
#   COVERAGE  every NON-BLANK line of the original appears the same number of
#             times across all files. Blank lines between blocks are glue the
#             split may rearrange; blank lines inside blocks are fidelity's job.
#
# Markers, uniform across router and step files:
#   <!-- split-addition --> ... <!-- /split-addition -->   NEW text. Excluded
#     from both checks. Used for the router's entry-point table, each step
#     file's repeated table headers, and anything else the split writes.
#   <!-- moved -->                                          Block boundary. The
#     text after it comes from a DIFFERENT part of the original, so it is a new
#     contiguous block rather than a continuation of the last one.
#
# Usage: reconstruct.sh <pre-split SKILL.md> [<session-end dir>]
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"

ORIG="${1:?usage: reconstruct.sh <pre-split SKILL.md> [dir]}"
ROOT="${2:-$HERE}"

W="$TMPBASE/recon.$$"; mkdir -p "$W"; trap 'rm -rf "$W"' EXIT
tr -d '\r' < "$ORIG" > "$W/orig"
: > "$W/all"

# Round 3: a glob silently omits a missing file, so only aggregate coverage
# would have caught it - and a compensating duplicate elsewhere could hide it.
# Enumerate exactly.
EXPECTED="step-00-inventory.md step-01-verify.md step-02-production-state.md \
step-04-pendings.md step-05-push-and-pr.md step-07-merge.md \
step-08-sync-and-cleanup.md step-10-report.md"

for name in $EXPECTED; do
  if [ -f "$ROOT/steps/$name" ]; then ok "present $name"; else bad "MISSING $name"; fi
done
for f in "$ROOT"/steps/step-*.md; do
  [ -f "$f" ] || continue
  case " $EXPECTED " in
    *" $(basename "$f") "*) ;;
    *) bad "unexpected step file: $(basename "$f")" ;;
  esac
done

# blocks.py does extraction, marker validation and block splitting. It is
# Python rather than layered awk because the split-addition regions need
# balance and nesting validation, which awk expresses badly.
#
# Note precisely what is validated: split-addition is a PAIRED region, so
# nesting, unmatched closes and unclosed-at-EOF are all rejected. `moved` is a
# single BOUNDARY with no closing form, so there is nothing to pair and no
# pairing check to make. Round 4 caught the plan claiming otherwise.
check() {  # check <file> <router|step>
  label=$(basename "$1")
  rm -rf "$W/b"; mkdir -p "$W/b"
  if ! python "$HERE/verify/blocks.py" "$1" "$2" "$W/b" 2>"$W/err"; then
    bad "$label - $(head -1 "$W/err")"
    return
  fi
  n=0
  for blk in "$W"/b/blk*; do
    [ -f "$blk" ] || continue
    n=$((n+1))
    if python "$HERE/verify/contains.py" "$W/orig" "$blk"; then
      ok "fidelity $label block $n"
    else
      bad "fidelity $label block $n - not a verbatim contiguous block of the original"
    fi
  done
  if [ "$n" -eq 0 ]; then bad "fidelity $label - no retained blocks extracted"; fi
  cat "$W/b/cover" >> "$W/all"
}

check "$ROOT/SKILL.md" router
for name in $EXPECTED; do
  [ -f "$ROOT/steps/$name" ] && check "$ROOT/steps/$name" step
done

# COVERAGE: exact multiset of NON-BLANK lines.
#
# Blank lines are excluded deliberately, and the reason matters. A blank line
# INSIDE a retained block is already verified byte-exactly by fidelity, since
# the block must be a verbatim contiguous substring of the original. A blank
# line BETWEEN blocks is structural glue the split legitimately rearranges - a
# section that now ends a file no longer needs the blank that separated it from
# its old neighbour. Counting those made the check fail on a CORRECT split,
# which is how it was found: by running it, not by reading it.
if diff <(grep -v '^[[:space:]]*$' "$W/orig" | sort) \
        <(grep -v '^[[:space:]]*$' "$W/all"  | sort) > "$W/diff" 2>&1; then
  ok "coverage: every original NON-BLANK line accounted for exactly once"
else
  bad "coverage: $(wc -l < "$W/diff") differing lines"
  head -40 "$W/diff"
fi

finish
```

`skills/session-end/verify/blocks.py` — extraction, marker validation, block splitting:

```python
"""Extract the retained blocks and the coverage stream from a split file.

Usage: blocks.py <file> <router|step> <outdir>
Exit 0 on success, 3 on a marker error (message on stderr).
"""
import io, os, sys

path, kind, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
lines = io.open(path, encoding="utf-8").read().replace("\r", "").split("\n")

ADD_O, ADD_C = "<!-- split-addition -->", "<!-- /split-addition -->"
MOVED = "<!-- moved -->"

# A step file is: H1, invariant recap, BODY, "## NEXT" + pointer. Drop the
# frame; the recap and the H1 are written by the split, not moved by it.
if kind == "step":
    try:
        i = next(n for n, L in enumerate(lines) if L.startswith("**Invariants recap**"))
    except StopIteration:
        sys.stderr.write("no invariant recap line\n"); sys.exit(3)
    lines = lines[i + 1:]
    for n, L in enumerate(lines):
        if L.strip() == "## NEXT":
            lines = lines[:n]
            break
    else:
        sys.stderr.write("no '## NEXT' pointer\n"); sys.exit(3)

# Validate markers, then strip additions and split at MOVED.
blocks, cur, inside_add = [[]], None, False
for n, L in enumerate(lines, 1):
    t = L.strip()
    if t == ADD_O:
        if inside_add:
            sys.stderr.write("nested %s at line %d\n" % (ADD_O, n)); sys.exit(3)
        inside_add = True
        continue
    if t == ADD_C:
        if not inside_add:
            sys.stderr.write("unmatched %s at line %d\n" % (ADD_C, n)); sys.exit(3)
        inside_add = False
        continue
    if inside_add:
        continue
    if t == MOVED:
        blocks.append([])
        continue
    blocks[-1].append(L)
if inside_add:
    sys.stderr.write("unclosed %s at EOF\n" % ADD_O); sys.exit(3)

os.makedirs(outdir, exist_ok=True)
cover = []
kept = 0
for b in blocks:
    body = "\n".join(b).strip("\n")
    if not body.strip():
        continue
    kept += 1
    io.open(os.path.join(outdir, "blk%03d" % kept), "w", encoding="utf-8", newline="\n").write(body + "\n")
    # Coverage takes the block VERBATIM, blanks and all; reconstruct.sh filters
    # blank lines when comparing, so a future stricter comparison needs no
    # change here.
    cover.extend(b)
io.open(os.path.join(outdir, "cover"), "w", encoding="utf-8", newline="\n").write("\n".join(cover) + "\n")
if kept == 0:
    sys.stderr.write("no retained blocks\n"); sys.exit(3)
```

`skills/session-end/verify/contains.py` - contiguous substring containment, exit 0 or 1:

```python
"""Exit 0 if the block is a verbatim contiguous substring of the original.

Usage: contains.py <original> <block>
"""
import io, sys

o = io.open(sys.argv[1], encoding="utf-8").read()
b = io.open(sys.argv[2], encoding="utf-8").read().strip("\n")
sys.exit(0 if b and b in o else 1)
```

Note there is no `grep -v` over the markers any more — round 3 flagged the GNU-specific `\?` in `'^<!-- /\?moved -->$'`, and `blocks.py` never emits a marker line into the coverage stream in the first place.

Syntax-check all three:

```bash
cd "$WT" && "$SKILL/scripts/gate.sh" reconstruct-syntax bash -n skills/session-end/verify/reconstruct.sh
```

```bash
cd "$WT" && "$SKILL/scripts/gate.sh" contains-syntax python -c "import ast; ast.parse(open('skills/session-end/verify/contains.py',encoding='utf-8').read())"
```

```bash
cd "$WT" && "$SKILL/scripts/gate.sh" blocks-syntax python -c "import ast; ast.parse(open('skills/session-end/verify/blocks.py',encoding='utf-8').read())"
```

Expected: `EXIT 0` from all three.

- [ ] **Step 1b: Prove `blocks.py` rejects a malformed marker set**

Round 3 asked for balance and nesting validation; an unexercised validator is not a validator.

```bash
cd "$WT" && printf '# X\n\n**Invariants recap** x\n<!-- split-addition -->\nnew\n## NEXT\na\n' > "$TMPBASE/bad1.md" && python skills/session-end/verify/blocks.py "$TMPBASE/bad1.md" step "$TMPBASE/bo"; test $? -eq 3
```

Expected: exit 0 from the `test` — `blocks.py` exits 3 on the unclosed addition.

```bash
cd "$WT" && printf '# X\n\n**Invariants recap** x\nbody\n' > "$TMPBASE/bad2.md" && python skills/session-end/verify/blocks.py "$TMPBASE/bad2.md" step "$TMPBASE/bo"; test $? -eq 3
```

Expected: exit 0 — no `## NEXT` pointer.

- [ ] **Step 2: Snapshot the pre-split original outside the tree**

`TMPDIR` is not guaranteed in Git Bash, so every task uses `TMPBASE` from `lib.sh`.

```bash
cd "$WT" && TMPBASE="${TMPDIR:-/tmp}" && cp skills/session-end/SKILL.md "$TMPBASE/session-end-presplit.md" && test "$(wc -c < "$TMPBASE/session-end-presplit.md")" -eq 36761
```

Expected: exit 0. The `test` is the gate; a wrong size exits non-zero on its own.

- [ ] **Step 4: Create the eight step files by moving text**

Each file opens with the invariant recap in the shape `session-build`'s step files use, and closes with `## NEXT`. Header for every step file, with `<N>` replaced:

```markdown
# Step <N> — <title>

**Invariants recap** (full text in `../SKILL.md`): the invocation authorises everything on this branch, including the merge — a permission-classifier refusal closes a route, never the run. Disarming a correctness gate is forbidden: any flag or env var whose effect is that a hook does not run. Two human gates only — Step 0 ambiguity and a correctness escalation. Every measurement is a reading; measure immediately before the action it authorises. Gates run through `<skill-dir>/scripts/gate.sh`. One step file at a time.
```

Extract each section from the snapshot with `awk`, one file at a time. For example, Step 0:

```bash
cd "$WT" && awk '/^## Step 0 — Pre-flight inventory$/{f=1} /^## Step 1 —/{f=0} f' "$TMPBASE/session-end-presplit.md" > "$TMPBASE/step00-body.md" && test "$(wc -c < "$TMPBASE/step00-body.md")" -eq 3806
```

Expected: `3806`. Then write `skills/session-end/steps/step-00-inventory.md` as the header, the body, and:

```markdown
## NEXT

`step-01-verify.md`
```

Repeat for each row of the section-to-file map. `step-02-production-state.md` and `step-05-push-and-pr.md` and `step-08-sync-and-cleanup.md` each concatenate two or three sections in source order.

**The `## NEXT` chain:** `step-00` → `step-01` → `step-02-production-state` → `step-04-pendings` → `step-05-push-and-pr` → `step-07-merge` → `step-08-sync-and-cleanup` → `step-10-report` → terminal.

- [ ] **Step 5: Rewrite `SKILL.md` as the router**

Keep, in this order: the preamble, `## Authorization`, `## Never bypass a gate`, `## Run gates through ...`, `## Project rules win`, `## Ledger`, the cross-cutting rows of `## Common mistakes`, the cross-cutting rows of `## Red flags — stop`.

Add, each wrapped in `<!-- split-addition -->` / `<!-- /split-addition -->` so `reconstruct.sh` strips it:

1. The **entry-point table** — the three lanes from spec Decision 2, verbatim:

```markdown
## Entry points

| Situation | Lane |
|---|---|
| A feature branch, or the default branch with a `handoff.md` naming one branch | **inline** — Steps 0–10, `steps/step-00-inventory.md` |
| Default branch **and** `handoff.md` with `N ≥ 2` branches | **fork lane** — `steps/lane-fork-orchestrator.md` |
| Default branch with worktrees and **no** `handoff.md` | **sequential** — `steps/step-00-inventory.md`, once per branch, entering each worktree |

The fork lane **requires** `handoff.md`. Without it there is no branch list, no merge order and no project profile, and improvising those is exactly what the handoff exists to prevent.
```

2. The **loading-discipline block**:

```markdown
## Loading discipline

One step file at a time, read to completion, then its named successor. Never load a later step early. Files under `references/` load **only** when their stated trigger fires — they are failure-path material.
```

3. **FIRST STEP**:

```markdown
## FIRST STEP

Route at the table above, then read fully and follow **`steps/step-00-inventory.md`**.
```

**Which `Common mistakes` rows stay in the router** — the three that belong to no single step: *"Tests passed earlier in the session"*, *"Report from memory"*, *"The command exited 0"*. Every other row moves to the step it belongs to. Same rule for `Red flags`: the ones naming a specific step move to it.

**Two markers make the split checkable, and `reconstruct.sh` depends on both. They work identically in the router and in every step file.**

1. **Anything the split WRITES** goes inside `<!-- split-addition -->` / `<!-- /split-addition -->` — the router's entry-point table and loading-discipline block, and **every repeated table header** above a moved fragment. Excluded from both checks. This is a paired region and `blocks.py` rejects nesting, an unmatched close, or one left open at EOF.
2. **`<!-- moved -->` is a single boundary marker. There is no closing form.** It says "the next line comes from a different part of the original", which starts a new block. A `<!-- /moved -->` would itself become retained content and fail both checks.

**Where a boundary is required — mechanical, not a judgement call.** Insert `<!-- moved -->` at **every point where two consecutive retained lines were not consecutive in the original.** That adjacency rule is the specification; the list below is three *kinds* of gap this run creates, and a single trimmed table can need several boundaries on its own:

- A step file receiving rows from `Common mistakes` or `Red flags`: the rows come from 20 KB away, so a boundary precedes them, and the **repeated table header is a `split-addition`** because the split writes it rather than moves it.
- **The router's own trimmed tables.** Removing step-specific rows from `Common mistakes` and `Red flags` leaves the retained rows non-contiguous in the original, so a boundary goes at each omission. Round 4 found this: the router is checked exactly like a step file and gets no exemption, and without the boundaries its fidelity fails.
- Any section placed out of its original order.

A file's body is otherwise assumed to be **one contiguous run** of the original — true for `## Step 4` moved whole, false the moment anything is omitted from the middle.

- [ ] **Step 6: Require the reconstruction check to PASS**

```bash
cd "$WT" && bash skills/session-end/verify/reconstruct.sh "$TMPBASE/session-end-presplit.md"
```

Expected: exit 0, `ALL CHECKS PASSED`. **A `fidelity` failure means text was edited inside a moved block; a `coverage` failure means a line was lost or duplicated. Fix the split. Never adjust the checker to make it pass.**

- [ ] **Step 6b: Prove the checker can fail, three ways**

Round 2: this runs **after** the clean pass, not before — an executor following checkbox order could not perform the first draft's version, which sat at Step 3 while instructing the reader to run it after Step 5.

**The three mutations and the claim each proves were executed against a synthetic split before this plan was finalised**, using the two `python` helpers below extracted verbatim from this document. That run corrected the first draft's claims, which had the isolation backwards. What follows is measured behaviour.

Round 8: each mutation is applied and reverted **inside one script with a `trap`**, because the first draft left restoration as a separate manual command after a step that deliberately exits non-zero — an executor interrupted between the two leaves a moved or edited file behind and contaminates every later check.

`skills/session-end/verify/prove-red.sh`:

```bash
#!/usr/bin/env bash
# prove-red.sh - mutate the split three ways and require reconstruct.sh to
# catch each one, restoring on every exit path including an interrupt.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"
ORIG="${1:?usage: prove-red.sh <pre-split SKILL.md>}"

R="$HERE/verify/reconstruct.sh"
S10="$HERE/steps/step-10-report.md"
S00="$HERE/steps/step-00-inventory.md"
SAVE="$TMPBASE/prove-red.$$"; mkdir -p "$SAVE"

restore() {
  [ -f "$SAVE/s10" ] && cp "$SAVE/s10" "$S10"
  [ -f "$SAVE/s00" ] && cp "$SAVE/s00" "$S00"
  rm -rf "$SAVE"
}
# Round 9: `trap restore EXIT INT TERM` restores on a signal but does NOT
# stop the script, so bash resumes and applies the next mutation to a
# just-restored tree. EXIT cleans up; the signal handlers must also exit.
trap restore EXIT
trap 'restore; echo "interrupted" >&2; exit 130' INT
trap 'restore; echo "terminated" >&2; exit 143' TERM
cp "$S10" "$SAVE/s10"; cp "$S00" "$SAVE/s00"

# (a) a step file removed - must be caught by the filename enumeration, not
#     merely by aggregate coverage, which a compensating duplicate could mask.
rm -f "$S10"
if bash "$R" "$ORIG" >"$SAVE/a.log" 2>&1; then bad "(a) missing file NOT caught"; else
  grep -qF "MISSING step-10-report.md" "$SAVE/a.log" \
    && ok "(a) missing file caught by enumeration" \
    || bad "(a) failed, but not via the enumeration"
fi
cp "$SAVE/s10" "$S10"

# (b) a line deleted from the MIDDLE of a block - fidelity AND coverage.
#     Deleting a TRAILING line leaves the block contiguous and proves nothing.
python - "$S00" <<'PY'
import io,sys
p=sys.argv[1]; L=io.open(p,encoding="utf-8").read().split("\n")
i=[n for n,x in enumerate(L) if x.strip()][3]
L.pop(i); io.open(p,"w",encoding="utf-8",newline="\n").write("\n".join(L))
PY
if bash "$R" "$ORIG" >"$SAVE/b.log" 2>&1; then bad "(b) deleted line NOT caught"; else
  grep -q "FAIL fidelity" "$SAVE/b.log" && grep -q "FAIL coverage" "$SAVE/b.log" \
    && ok "(b) deleted middle line caught by fidelity AND coverage" \
    || bad "(b) failed, but not on both claims"
fi
cp "$SAVE/s00" "$S00"

# (c) an existing line duplicated as its own moved block - COVERAGE ONLY.
#     Both blocks stay contiguous, so this is what isolates the two claims.
python - "$S10" <<'PY'
import io,sys
p=sys.argv[1]; t=io.open(p,encoding="utf-8").read()
b=[x for x in t.split("## NEXT")[0].strip().split("\n") if x.strip()][-1]
io.open(p,"w",encoding="utf-8",newline="\n").write(
    t.replace("\n## NEXT", "\n<!-- moved -->\n"+b+"\n\n## NEXT", 1))
PY
if bash "$R" "$ORIG" >"$SAVE/c.log" 2>&1; then bad "(c) duplicate NOT caught"; else
  grep -q "FAIL coverage" "$SAVE/c.log" && ! grep -q "FAIL fidelity" "$SAVE/c.log" \
    && ok "(c) duplicated block caught by coverage ONLY" \
    || bad "(c) failed, but fidelity also fired - the claims are not isolated"
fi
cp "$SAVE/s10" "$S10"

finish
```

```bash
cd "$WT" && bash skills/session-end/verify/prove-red.sh "$TMPBASE/session-end-presplit.md"
```

Expected: exit 0, three `PASS`. The script restores on every exit path, so a failure here leaves the tree exactly as it found it.

Then confirm the tree really is clean and the checker still green:

```bash
cd "$WT" && test -z "$(git status --porcelain skills/session-end/)" && bash skills/session-end/verify/reconstruct.sh "$TMPBASE/session-end-presplit.md"
```

Expected: exit 0. Round 7: `git status --porcelain` exits 0 **even when it prints changes**, so `git status ... && reconstruct.sh` would have run the checker over a tree still carrying a mutation. `test -z "$(...)"` is the gate.

- [ ] **Step 7: Enforce the byte budgets**

Printing sizes is not a check. `skills/session-end/verify/budgets.sh`:

```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"
n=$(wc -c < "$HERE/SKILL.md")
if [ "$n" -le 12288 ]; then ok "SKILL.md $n <= 12288"; else bad "SKILL.md $n > 12288"; fi
for f in "$HERE"/steps/*.md; do
  n=$(wc -c < "$f")
  # 8192, not the spec's estimated 7168. Measured during the split: Step 4's
  # body is 6307 bytes the spec protects VERBATIM, the invariant recap every
  # step file carries is ~600, and its own Common-mistakes and Red-flags rows
  # are ~1000 more. 7168 leaves ~260 bytes of headroom for 1000 bytes of
  # content that belongs there, so the cap was infeasible against a constraint
  # the spec imposes elsewhere. Raised with the measurement, not to pass.
  if [ "$n" -le 8192 ]; then ok "$(basename "$f") $n <= 8192"; else bad "$(basename "$f") $n > 8192"; fi
done
finish
```

```bash
cd "$WT" && bash skills/session-end/verify/budgets.sh
```

Expected: exit 0.

- [ ] **Step 8: Enforce the cross-reference sweep**

The first version printed `ORPHAN` for every number and left a human to compare two outputs, so it had no failing condition. `skills/session-end/verify/xrefs.sh` derives the referenced set and fails on a gap:

```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
. "$HERE/verify/lib.sh"
# Round 2: hard-coding four files contradicts the plan's own claim that
# fourteen references live outside SKILL.md, and lets a reference elsewhere go
# orphaned unnoticed. Derive repo-wide.
#
# Round 5: --exclude-dir matches a BASENAME, so --exclude-dir=steps also
# excluded skills/session-build/steps - one of the known external reference
# sources, silently dropped from a sweep whose whole job is to find them.
# Exclude by PATH instead, and only the one directory that legitimately
# contains the headings rather than references to them.
refs=$(grep -rlE 'Step [0-9]+' "$REPO/skills" "$REPO/docs" 2>/dev/null \
  --exclude-dir=plans --exclude-dir=specs --exclude-dir=codex-review \
  | grep -v "^$HERE/steps/" \
  | tr '\n' '\0' | xargs -0 -r grep -hoE 'Step [0-9]+' 2>/dev/null \
  | grep -oE '[0-9]+' | sort -un)
if [ -z "$refs" ]; then bad "no Step N references found at all - the sweep is looking in the wrong place"; finish; fi
printf 'sweeping %s referenced step numbers\n' "$(printf '%s\n' "$refs" | wc -w)"
for n in $refs; do
  if grep -rq "^## Step $n " "$HERE/steps/"; then ok "Step $n resolves"; else bad "Step $n referenced but no owning heading"; fi
done
finish
```

```bash
cd "$WT" && bash skills/session-end/verify/xrefs.sh
```

Expected: exit 0. The empty-`refs` guard matters: with wrong paths the sweep finds nothing and would otherwise pass vacuously.

- [ ] **Step 9: Commit**

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902"
```

Expected: exit 0.

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-end/SKILL.md skills/session-end/steps/ skills/session-end/verify/ && git commit -F- <<'EOF'
refactor(session-end): split the monolith into a router and just-in-time steps

36,761 bytes were loaded on every invocation, including for a docs-only
branch that will never touch a migration, a function or a pull request.
session-build took this shape on 2026-08-26; session-end was left behind.

Text moves in this commit and nothing is written. verify/reconstruct.sh
concatenates the pieces back together and diffs against the original as a
line multiset, so a reordering is not mistaken for a loss and a loss cannot
hide behind a reordering. It is run empty before the split exists, so the
check is known to discriminate.

Steps 0-10 keep their numbers in the prose. Fourteen cross-references live
outside this file and renumbering would break all of them silently.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 10: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "2/10 mechanical split committed. Router <bytes>, eight step files, largest <bytes>. reconstruct.sh green on the split, then PROVED able to fail three ways, each exiting 1 via finish(): (a) a step file removed - caught by the explicit filename enumeration, not merely by coverage, which a compensating duplicate could have masked; (b) a line deleted from the MIDDLE of a block - fidelity AND coverage, because deleting a trailing line leaves the block contiguous and proves nothing; (c) an existing line duplicated as its own <!-- moved --> block - COVERAGE ONLY, every fidelity check still passing, which is the mutation that isolates the two claims. blocks.py separately proved to exit 3 on an unclosed split-addition and on a missing ## NEXT. budgets.sh and xrefs.sh both exit non-zero on violation and were run green."
```

---

## Task 3: `gate.sh --expect` — the one finding that needs code

**Evidence B1, 7 of 20 runs.** A suite killed mid-run returns `EXIT 1`, which is indistinguishable from a red. One run put it exactly: *"the FULL suite was KILLED mid-run TWICE — once after 2189 log lines, once after 963, neither with a summary line — and `gate.sh` reports EXIT 1 for that, which reads exactly like a red and is not one."* Another: *"A gate that did not finish did not decide."*

**Files:**
- Modify: `skills/session-build/scripts/gate.sh:47-58,120-135`
- Modify: `skills/session-build/scripts/gate.ps1:20-26,60-70`
- Modify: `skills/session-end/scripts/gate.sh` — identical
- Modify: `skills/session-end/scripts/gate.ps1` — identical

**Interfaces:**
- Produces: `gate.sh [--prove-red] [--shell] [--expect <literal>] <label> <command...>`. On no match: stdout `GATE <label> UNDECIDED LOG <path> LINES <n>`, exit **75**. On match or no `--expect`: unchanged `GATE <label> EXIT <code> ...`, exit = the command's own code. **`<literal>` is a fixed string, identical semantics in both shells.**
- Consumed by: Task 4 (`steps/step-01-verify.md`'s `incomplete` lane), Task 8 (`references/fork-contract.md`).

**Design decisions, and why:**

- **`--expect` takes a FIXED STRING, not a regex.** Round 1: `grep -E` speaks POSIX ERE and `Select-String -Pattern` speaks .NET regex, and they are not the same language — one `--expect` documented as "a regex" would mean two different things on the two platforms, silently. Runner summary lines are literal text, so the regex bought nothing and cost portability. `grep -qF` and `Select-String -SimpleMatch`. The flag is documented as `--expect <literal>` everywhere.
- **The match is checked regardless of exit code.** A command that exits 0 while printing no summary is *more* alarming, not less — it is a runner that did nothing. So `--expect` gates completion, not success.
- **A genuine red still reports `EXIT`.** Real failures print a summary (`2 failed, 300 passed`); killed runs print none. That is precisely the discrimination wanted, and it is why matching the *summary line* works where matching "no errors" would not.
- **Exit 75** (`EX_TEMPFAIL` — "temporary failure, the user is invited to retry"), which is semantically exact. 75 is **not reserved** — a command under test can exit 75 too — so the two cases are told apart by the **record type on stdout**, never by the exit code alone. This is the same caveat `gate.sh` already documents for `WRAPPER_ERROR`/70, and the header comment must say so in the same words.
- **`--prove-red` composes.** If the gate did not complete, prove-red cannot conclude either; it prints `PROVE_RED INCONCLUSIVE - gate did not complete`.

- [ ] **Step 1: Write the failing test**

`skills/session-end/verify/expect-flag.sh`:

```bash
#!/usr/bin/env bash
# expect-flag.sh — prove --expect changes the output, in BOTH directions.
# A flag never seen to change the output is not a flag.
set -u
G="${1:?usage: expect-flag.sh <path-to-gate.sh>}"
fail=0

# 1. Log matches the expected line -> normal EXIT record, command's own code.
out=$("$G" --expect 'ran 3 tests' t-match printf 'ran 3 tests\n'); rc=$?
case "$out" in
  "GATE t-match EXIT 0 LOG "*) echo "PASS match -> EXIT" ;;
  *) echo "FAIL match: got [$out] rc=$rc"; fail=1 ;;
esac

# 2. Log does NOT match -> UNDECIDED record, exit 75. This is the killed-suite case.
out=$("$G" --expect 'ran 3 tests' t-nomatch printf 'killed after 2189 lines\n'); rc=$?
case "$out" in
  "GATE t-nomatch UNDECIDED LOG "*) [ "$rc" -eq 75 ] && echo "PASS nomatch -> UNDECIDED 75" \
      || { echo "FAIL nomatch rc: want 75 got $rc"; fail=1; } ;;
  *) echo "FAIL nomatch: got [$out] rc=$rc"; fail=1 ;;
esac

# 3. A REAL red whose runner printed its summary still reports EXIT, not UNDECIDED.
#    Round 1: the first draft allowed this case to SKIP, so the suite could pass
#    without ever testing one of --expect's core claims. --shell, and no skip.
out=$("$G" --shell --expect 'passed tests' t-red 'echo "2 failed, 1 passed tests"; exit 1')
case "$out" in
  "GATE t-red EXIT 1 LOG "*) echo "PASS real red -> EXIT 1" ;;
  *) echo "FAIL red: got [$out]"; fail=1 ;;
esac

# 4. No --expect at all -> byte-identical behaviour to before.
out=$("$G" t-plain printf 'anything\n')
case "$out" in
  "GATE t-plain EXIT 0 LOG "*) echo "PASS no-flag unchanged" ;;
  *) echo "FAIL no-flag: got [$out]"; fail=1 ;;
esac

exit $fail
```

- [ ] **Step 2: Run it and verify it fails**

```bash
cd "$WT" && chmod +x skills/session-end/verify/expect-flag.sh && bash skills/session-end/verify/expect-flag.sh skills/session-build/scripts/gate.sh
```

Expected: `FAIL nomatch` (the flag does not exist yet, so `--expect` is treated as the label), `exit=1`.

- [ ] **Step 3: Implement in `skills/session-build/scripts/gate.sh`**

Add to the option loop (currently lines 51-58):

```bash
EXPECT=""

while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --prove-red) PROVE_RED=true; shift ;;
    --shell)     ALLOW_SHELL=true; shift ;;
    --expect)    shift
                 [ "$#" -gt 0 ] || { echo "gate.sh: --expect needs a pattern" >&2; exit 64; }
                 EXPECT="$1"; shift ;;
    *)           break ;;
  esac
done
```

Replace the single result line (currently `echo "GATE $label EXIT $code LOG $log LINES $lines"`) with:

```bash
# --expect answers a question the exit code cannot: did the gate FINISH?
# A suite killed mid-run returns 1 and is indistinguishable from a red — seven
# of twenty observed close-outs hit that, and at least two triaged a killed run
# as a failing one. So the caller names the runner's own summary line, and a log
# without it is reported as UNDECIDED: not red, not green, no verification.
# Checked regardless of exit code — a command that exits 0 having printed no
# summary is a runner that did nothing, which is worse, not better.
# NOTE 75 is EX_TEMPFAIL and is NOT reserved: a command under test can exit 75
# too. Tell the cases apart by the RECORD TYPE on stdout (`GATE … UNDECIDED …`
# versus `GATE … EXIT …`), never by the exit code alone — the same caveat this
# script already carries for WRAPPER_ERROR and 70.
if [ -n "$EXPECT" ] && ! grep -qF -- "$EXPECT" "$log" 2>/dev/null; then
  echo "GATE $label UNDECIDED LOG $log LINES $lines"
  if [ "$PROVE_RED" = true ]; then
    echo "GATE $label PROVE_RED INCONCLUSIVE - gate did not complete" >&2
  fi
  exit 75
fi

echo "GATE $label EXIT $code LOG $log LINES $lines"
```

Update the usage line and the header contract block:

```bash
  echo "usage: gate.sh [--prove-red] [--shell] [--expect <literal>] <label> <command> [args...]" >&2
```

Add to the header comment, beside the existing `WHAT THIS GUARANTEES` bullets:

```
#   * With --expect <literal>, a log not containing that literal reports UNDECIDED and
#     exits 75. UNDECIDED is neither red nor green: it is absent verification.
#     Never merge off it and never report it as a failure — re-run the gate
#     scoped, split or backgrounded.
#
# NOTE: duplicated verbatim in skills/session-end/scripts/gate.sh.
# Change both or neither.
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
cd "$WT" && bash skills/session-end/verify/expect-flag.sh skills/session-build/scripts/gate.sh
```

Expected: exit 0, exactly four `PASS` lines. Round 2: the revised test has no skip path, so a `SKIP` here is a failure, not an alternative.

- [ ] **Step 5: Implement in `gate.ps1`, then copy both to `session-end/scripts/`**

Add the parameter, before `$Label` so positional binding is unaffected:

```powershell
[CmdletBinding()]
param(
    [switch]$ProveRed,
    [string]$Expect,
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Label,
    [Parameter(Mandatory = $true, Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Command
)
```

Replace the `Write-Output` result line with:

```powershell
# See gate.sh for why this exists: a killed suite exits 1 and is
# indistinguishable from a red. 75 is EX_TEMPFAIL and is NOT reserved — tell
# the cases apart by the record type on stdout, never by the exit code.
if (-not [string]::IsNullOrEmpty($Expect)) {
    $matched = $false
    if (Test-Path -LiteralPath $log) {
        $matched = [bool](Select-String -LiteralPath $log -SimpleMatch -Pattern $Expect -Quiet)
    }
    if (-not $matched) {
        Write-Output "GATE $Label UNDECIDED LOG $log LINES $lines"
        if ($ProveRed) { Write-Error "GATE $Label PROVE_RED INCONCLUSIVE - gate did not complete" }
        exit 75
    }
}

Write-Output "GATE $Label EXIT $code LOG $log LINES $lines"
```

Then make the four copies identical:

```bash
cd "$WT" && cp skills/session-build/scripts/gate.sh skills/session-end/scripts/gate.sh
cd "$WT" && cp skills/session-build/scripts/gate.ps1 skills/session-end/scripts/gate.ps1
```

- [ ] **Step 6: Syntax gate, and pairwise identity that can actually fail**

```bash
cd "$WT" && "$SKILL/scripts/gate.sh" gatesh-syntax bash -n skills/session-build/scripts/gate.sh
```

Expected: `EXIT 0`.

Round 1: the first draft's identity loop printed `DRIFT` and could still exit 0 on a passing final iteration.

```bash
cd "$WT" && rc=0; for f in gate.sh gate.ps1; do cmp -s "skills/session-end/scripts/$f" "skills/session-build/scripts/$f" || { echo "DRIFT $f"; rc=1; }; done; exit $rc
```

Expected: exit 0.

- [ ] **Step 6b: Behavioural test for `gate.ps1`, not just a parse check**

Round 1 is right that a parse check leaves matching, exit-75, real-red and no-flag behaviour unverified on the platform the script exists for. `skills/session-end/verify/expect-flag.ps1` mirrors the four cases:

```powershell
param([Parameter(Mandatory=$true)][string]$Gate)
$fail = 0
function Check($name, $got, $wantPrefix, $wantCode, $code) {
    if ($got -like "$wantPrefix*" -and $code -eq $wantCode) { Write-Host "PASS $name" }
    else { Write-Host "FAIL ${name}: got [$got] code=$code"; $script:fail = 1 }
}
$o = & $Gate -Expect 'ran 3 tests' t-match cmd /c "echo ran 3 tests"; Check 'match' $o 'GATE t-match EXIT 0' 0 $LASTEXITCODE
$o = & $Gate -Expect 'ran 3 tests' t-nomatch cmd /c "echo killed"; Check 'nomatch' $o 'GATE t-nomatch UNDECIDED' 75 $LASTEXITCODE
$o = & $Gate -Expect 'failed' t-red cmd /c "echo 2 failed & exit 1"; Check 'real-red' $o 'GATE t-red EXIT 1' 1 $LASTEXITCODE
$o = & $Gate t-plain cmd /c "echo anything"; Check 'no-flag' $o 'GATE t-plain EXIT 0' 0 $LASTEXITCODE
exit $fail
```

```bash
cd "$WT" && pwsh -NoProfile -File skills/session-end/verify/expect-flag.ps1 -Gate skills/session-build/scripts/gate.ps1
```

```bash
cd "$WT" && pwsh -NoProfile -File skills/session-end/verify/expect-flag.ps1 -Gate skills/session-end/scripts/gate.ps1
```

Expected: exit 0 and four `PASS` from **each**. Round 2: testing only one copy leaves the other's matching, exit-75 and real-red behaviour unverified, and they are separate files that can drift.

**If `pwsh` is not on this machine, try `powershell.exe` (5.1, the stated target). If neither runs, record in the ledger and the final report that the PowerShell twin is UNVERIFIED — a named gap beats an unverified claim, and this is exactly the "a check that could not run is not a check that ran green" rule applied to my own work.**

- [ ] **Step 7: Run the test against the session-end copy too**

```bash
cd "$WT" && bash skills/session-end/verify/expect-flag.sh skills/session-end/scripts/gate.sh
```

Expected: `exit=0`.

- [ ] **Step 8: Commit**

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-build/scripts/gate.sh skills/session-build/scripts/gate.ps1 skills/session-end/scripts/gate.sh skills/session-end/scripts/gate.ps1 skills/session-end/verify/lib.sh skills/session-end/verify/expect-flag.sh skills/session-end/verify/expect-flag.ps1 && git commit -F- <<'EOF'
feat(gate): --expect, so a killed suite stops being spelled EXIT 1

Seven of twenty observed close-outs hit a gate that was killed mid-run.
gate.sh reported EXIT 1, which is what a real red looks like, and at least
two runs triaged the corpse as a failing test. The runs that got it right
invented the phrase themselves: a gate that did not finish did not decide.

--expect names the runner's own summary line. A log without it reports
UNDECIDED and exits 75 -- not red, not green, absent verification. The
pattern is checked whatever the exit code, because a command that exits 0
having printed no summary is a runner that did nothing.

Proved in both directions before being believed: match reports EXIT,
no-match reports UNDECIDED 75, a real red whose runner printed a summary
still reports EXIT 1, and an invocation without the flag is unchanged.

All four copies patched -- both skills carry gate.sh and gate.ps1 and they
were byte-identical, so patching two would have started the drift the
duplication note exists to prevent.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 9: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "3/10 gate.sh --expect landed in all four copies (both skills carry gate.sh and gate.ps1, byte-identical before and after, verified with cmp). Proved both directions with verify/expect-flag.sh: match -> GATE <l> EXIT 0; no match -> GATE <l> UNDECIDED, exit 75; a real red whose runner printed a summary still reports EXIT 1; no --expect is unchanged. Exit 75 is EX_TEMPFAIL and NOT reserved - the record type on stdout discriminates, same caveat gate.sh already carries for WRAPPER_ERROR/70."
```

---

## Task 4: Step 1 — three new triage lanes, and two one-line rules

**Files:**
- Modify: `skills/session-end/steps/step-01-verify.md`
- Modify: `skills/session-end/verify/assert-findings.sh` (create on first use)

**Interfaces:**
- Consumes: `gate.sh --expect` from Task 3 — the `incomplete` lane is defined by `UNDECIDED`, which does not exist without it.

- [ ] **Step 1: Write the assertions first**

Create `skills/session-end/verify/assert-findings.sh`. **The helper matches FIXED STRINGS, not regexes** — the content is markdown full of backticks, asterisks and pipes, and escaping those into an ERE is how an assertion silently stops discriminating. Same lesson as `--expect`.

```bash
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

finish
```

**Every clause above is a phrase this task is about to write and that exists nowhere in the repo today.** That is the property that makes step 2 meaningful — verify it by running step 2 and seeing all nine fail by name.

- [ ] **Step 2: Run it and verify it fails**

```bash
cd "$WT" && chmod +x skills/session-end/verify/assert-findings.sh && bash skills/session-end/verify/assert-findings.sh
```

Expected: nine `FAIL` lines, `exit=1`. **If any of them PASSes, the assertion is matching something already present and is too loose — tighten it before writing the content.**

- [ ] **Step 3: Rewrite Step 1's triage table to six lanes**

In `steps/step-01-verify.md`, replace the three-lane table with:

```markdown
**A red gate is not automatically a stop. Triage it into exactly one lane and name the proof.** A lane is defined by the **proof it demands**, not by its name — a run that cannot produce the proof falls back to `regression`, which stops the merge, so the failure mode is conservative by construction.

| Lane | Proof required | Response |
|---|---|---|
| `incomplete` | `gate.sh` reported **`UNDECIDED`** — the log carries no summary line from the runner itself | **Not a red.** Re-run scoped, split or in the background. Never merge off it, never report it as a failure. Two runs completed a suite this way after it had been killed twice. |
| `regression` | The same gate is green on the base and the failure signature is new | **Escalate.** Never migrate, deploy or merge off it. |
| `pre-existing-on-base` | **Reproduce the same normalised failure on a clean checkout of the base ref.** Byte-comparing the failing file against base is *not* proof on its own — an unchanged test can fail from a changed caller, config, schema or generated input; it is admissible only alongside a stated argument that nothing in your diff reaches that file. | Record with the reproduction, report at Step 10, continue |
| `flaky-under-load` | **All three**: green in isolation, green on a clean checkout of the base, and green on an identical re-run. Fewer than three is not this lane. | Record all three readings, continue |
| `foreign-dirty-tree` | `git show HEAD:<path>` proves the committed file is clean and the red comes from a **peer's uncommitted state** in a shared checkout | **Touch nothing.** Report it. It is not yours to fix and not yours to triage further. |
| `environmental` | Name the missing or stale artifact — dependencies not installed, a stale dependency tree. **Sub-case `missing-artifact`:** a gate run before the one that generates its input, e.g. typecheck ahead of build failing on a file the build writes. That is a *gate order* problem, not an installation one, and the project profile's `gate_order` is the fix. | Repair **without touching branch content**, then re-run. **Continue only if the identical gate now returns green**; if the failure survives the repair it was never environmental — re-triage it. |

**`incomplete` is the lane runs did not have, and the one they most needed.** Seven of twenty observed close-outs met a gate that was killed — by a tool timeout, by the harness, by memory pressure — and `EXIT 1` is what a real red looks like. Two triaged the corpse as a failing test. Name the runner's summary line in `gate_order` and let `--expect` decide:

```
<skill-dir>/scripts/gate.sh --expect 'Test Files' test npm test
```

The literal is a fragment of the runner's **own summary line** — `Test Files` for vitest, `passed,` for pytest's tail, `Tests:` for jest. Pick a fragment that a *complete* run always prints and a killed run never reaches, and record it per gate in `gate_order`. A fragment that also appears in ordinary progress output is worthless: it will match a corpse.

**A cached green is not a green.** Where the project uses a build cache — turbo, nx, bazel — run the Step 1 gates with the cache disabled and record the cache-miss evidence. A cached exit code is a recording of an older tree. One run re-ran every gate with `--force` and recorded `Cached: 0` beside each.

**Report what the suite did not run.** `344 passed, 13 deselected` overstates coverage until the deselection is named. Put the count and the reason in the report.
```

- [ ] **Step 4: Add the verify-the-tree-that-lands rule to the same file**

```markdown
## Verify the tree that will land, not the branch tip

Merge `origin/<default>` into the branch **first**, then gate. That is the tree that lands, and it front-loads the conflict work into the step that has time for it.

One run did exactly this — *"run on the branch AFTER merging origin/main@6078de1, i.e. on the tree that would land"* — and another made the merged default branch the *decisive* run rather than an extra one. That second run went red and exposed a main checkout carrying a stale dependency tree for days, *"so any suite run there was measuring the wrong tree."*

**Under the fork lane a fork may not do this on its own** — a fork performs no merge it was not ordered to perform. The orchestrator issues `MERGE origin/<default> BEFORE verify` in the same message as `GO <slug> verify <branch>`, having just re-fetched, so it names the SHA.
```

- [ ] **Step 5: Run the assertions and verify they pass**

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

Expected: nine `PASS`, `exit=0`.

- [ ] **Step 6: Re-check the byte budget**

```bash
cd "$WT" && bash skills/session-end/verify/budgets.sh
```

Expected: exit 0. Round 5: a bare `wc -c` here only printed sizes, so an oversized file could be committed past a budget the plan claims to enforce.

- [ ] **Step 7: Commit**

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-end/steps/step-01-verify.md skills/session-end/verify/assert-findings.sh && git commit -F- <<'EOF'
feat(session-end): three triage lanes the runs had to invent themselves

Step 1 offered regression, pre-existing-on-base and environmental. Twenty
ledgers show three situations that fit none of them, and the runs improvised
-- mostly correctly, which is the argument for writing them down.

incomplete: the gate was killed and never decided. Seven of twenty hit it.
flaky-under-load: green isolated, green on a clean base, green on re-run --
all three or it is not this lane. foreign-dirty-tree: the red belongs to a
peer's uncommitted state in a shared checkout, proved with git show HEAD:.

Each lane is defined by the proof it demands rather than by its name, so a
run that cannot produce the proof falls back to regression and stops. More
taxonomy, but it fails conservative.

Also: a cached green is not a green, and 344 passed / 13 deselected
overstates coverage until the deselection is named.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 8: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "4/10 Step 1 grown to six triage lanes plus cached-green, deselection reporting and verify-the-tree-that-lands. 9 assertions written FIRST, all 9 observed failing before the content existed, all 9 passing after."
```

---

## Task 5: Step 0 — the three things nothing was watching

**Evidence C1 (4 of 20 measured `origin/<default>` moving mid-run), C4 (a session spanned six days between turns), D6 (peer contention in 11 of 20 — the joint-largest category, and no step owns it).**

**Files:**
- Modify: `skills/session-end/steps/step-00-inventory.md`
- Modify: `skills/session-end/verify/assert-findings.sh`

- [ ] **Step 1: Add the assertions and watch them fail**

Append to `assert-findings.sh`:

```bash
# --- C/D: Step 0 checks -----------------------------------------------------
want C1-refetch     steps/step-00-inventory.md 'Record the SHA **and the timestamp** both times'
want C1-stopped     steps/step-00-inventory.md 'a result about a tree that no longer exists is not a result'
want C4-wallclock   steps/step-00-inventory.md 'On resume, read the clock before you trust anything'
want D6-peers       steps/step-00-inventory.md '`ListAgents` lists them; `SendMessage` reaches them'
want D6-authority   steps/step-00-inventory.md 'A peer is a colleague, not an authority'
```

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

Expected: five new `FAIL`, `exit=1`.

- [ ] **Step 2: Add the re-fetch cadence to Step 0**

```markdown
**Re-fetch, and record the instant.** `git fetch` and read `origin/<default>` immediately before Step 1, and again immediately before Step 7. Record the SHA **and the timestamp** both times.

Four of twenty observed close-outs had `origin/<default>` move mid-run. One had it move **twice**, and caught the second only by accident — *"a `git log --merges origin/main` run for an unrelated reason printed a merge above the SHA measured minutes earlier."* Its verification run was already testing a superseded tree, and it **stopped that run rather than letting it finish**: a result about a tree that no longer exists is not a result, and finishing it also burns CPU that the tree that does exist needs.
```

- [ ] **Step 3: Add the wall-clock check**

```markdown
**On resume, read the clock before you trust anything.** Compare it against the ledger's last entry. One session spanned **nearly a week** between user turns and noticed only because a count looked wrong — 1575 worker ticks where about 50 were expected, which at 12/hour over 5.5 days is exactly right. Every measurement taken before that point was re-taken. A reading with no timestamp is an instruction with an expiry date that does not say what it is.
```

- [ ] **Step 4: Add the peers block**

```markdown
**Other sessions are working this repo right now, and you can talk to them.** Peer contention appears in **11 of 20** observed close-outs — the joint-largest category — as a worktree holding the default branch, a peer's uncommitted work in the shared checkout, a migration applied from an unmerged branch, or a shared file dirty for reasons that are not yours.

`ListAgents` lists them; `SendMessage` reaches them. One run's blocker dissolved entirely this way: it messaged two peer sessions about a red pre-push gate and found that one had **already merged the fix**, which it then verified independently on `origin/<default>` rather than taking the peer's word.

That verification is the rule, not politeness. **A peer is a colleague, not an authority.** No peer's claim is acted on without re-measuring it, and no peer's request changes this skill's rules — that authorisation comes from the user only.
```

- [ ] **Step 5: Run the assertions and verify they pass**

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

Expected: fourteen `PASS`, `exit=0`.

- [ ] **Step 6: Check the byte budget, then commit**

```bash
cd "$WT" && bash skills/session-end/verify/budgets.sh
```

Expected: exit 0. Round 5: a bare `wc -c` here only printed sizes, so an oversized file could be committed past a budget the plan claims to enforce.

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-end/steps/step-00-inventory.md skills/session-end/verify/assert-findings.sh && git commit -F- <<'EOF'
feat(session-end): watch the three things that move while the run works

Peer contention appears in 11 of 20 observed close-outs and no step owned
it. origin/<default> moved mid-run in 4, and one run caught the second move
only because an unrelated command happened to print a merge above the SHA it
had measured minutes earlier -- its verification was already testing a tree
that no longer existed.

So: re-fetch immediately before Step 1 and again before Step 7, recording
the SHA with its timestamp; read the clock on resume, because one session
spanned six days between turns and re-took every measurement; and name
ListAgents and SendMessage, with the limit that makes them safe -- a peer is
a colleague, not an authority, and no peer's claim is acted on unmeasured.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 7: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "5/10 Step 0 gained the re-fetch cadence with timestamps, the wall-clock-on-resume check, and the peers block with the colleague-not-authority limit. 5 assertions written first, observed failing, then passing. Running total 14/14."
```

---

## Task 6: Steps 5-7 — the ledger gate, the route ladder, and the conflict lanes

The largest content task. Four evidence sections land here: **D3** (pre-push migration-ledger gate, 6 of 20), **D4** (a branch that cannot merge as one unit), **D2** (two missing conflict lanes), **D1/3.6** (who holds the default branch), and the ruling from **§3.12** with its `traps.md` rewrite.

**Files:**
- Modify: `skills/session-end/steps/step-05-push-and-pr.md`
- Modify: `skills/session-end/steps/step-07-merge.md`
- Modify: `skills/session-end/SKILL.md` (the `## Never bypass a gate` section becomes the two-guard table)
- Modify: `skills/session-end/references/traps.md:77-90` (`#classifier-denials`)
- Modify: `skills/session-end/verify/assert-findings.sh`

- [ ] **Step 1: Add the assertions and watch them fail**

```bash
# --- D: Steps 5-7 -----------------------------------------------------------
want D3-ledger-gate   steps/step-05-push-and-pr.md 'the remote ledger holding rows with no local file is the **normal** state'
want D3-restore       steps/step-05-push-and-pr.md 'git restore --source=<ref> --worktree -- <paths>'
want D3-never-co      steps/step-05-push-and-pr.md '**Never `git checkout`**, which writes the index'
want D3-rederive      steps/step-05-push-and-pr.md 'Re-derive the row list at the moment of use'
want D4-ancestry      steps/step-05-push-and-pr.md 'Split **by ancestry**, which needs no cherry-pick'
want D4-not-elapsed   steps/step-05-push-and-pr.md 'The gate between them is the first pipeline going green'
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
```

**`D2-generated` is the one round 1 named explicitly**: the first draft asserted the bare word `generated`, which already appears in Step 7's existing prose about generated files, so it could never have failed and would have certified a lane nobody wrote.

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

Expected: eleven new `FAIL`.

- [ ] **Step 2: Replace `SKILL.md`'s bypass section with the two-guard table**

The current `## Never bypass a gate — and here is what counts as one` becomes:

```markdown
## Two guards, and only one of them stops this run

The word "bypass" has been covering two unrelated things, and separating them is what lets this skill finish without asking.

| | **Permission guard** | **Correctness guard** |
|---|---|---|
| What it is | The harness permission classifier | The project's own hooks and gates |
| What it protects | Your authorisation to act | Whether the code is sound |
| Already settled? | **Yes** — the invocation *is* the ask, and the Authorization block above says so | **No** — nothing settles a red hook in advance |
| A refusal means | *This route is closed* | *This change is not ready* |
| Response | **Take another route, name it in the report, keep going** | **Escalate** |

**The permission classifier is non-deterministic and it is not a decision point.** The same command is permitted in one run and refused in the next with nothing about the repo having changed. Runs have lost **38 minutes** and **~46 minutes** treating a refusal as a verdict. It is not one — the user authorised this work by invoking the skill.

So: retry once bare, then take **any sanctioned route** to the effect already authorised — the project's own `git merge` where `merge_path: local-merge`, `gh api` where the forge supports it, whichever exists. **Say in the report which route ran and why**, every time: a merge whose route is not stated reads as a merge that did not happen. Escalate only when every route is exhausted, and then it is a wall rather than a choice — report it with the branch pushed, the PR open if there is one, and the single command the user has to run.

**What is never permitted is reaching the effect by disarming a correctness guard.** `--no-verify`; `-n` on commit; `--force`, `-f` or `--force-with-lease` on push; `-c core.hooksPath=<anything>`; `HUSKY=0`; `SKIP_HOOKS`; `--no-gpg-sign`; **or any flag or environment variable whose effect is that a hook does not run.** The enumeration is not the rule — that last clause is. A failing hook is an escalation, not an obstacle.

**And never reason around missing evidence.** A check that could not run is not a check that ran green. That holds on both sides of the table.
```

- [ ] **Step 3: Rewrite `traps.md#classifier-denials` — rewrite, do not delete**

Replace the section body with the same incidents and a corrected verdict:

```markdown
## classifier-denials

**Triggered from the two-guard rule.** The incidents below are unchanged; **their verdict changed on 2026-09-02** and the entry says so rather than quietly dropping the ones that no longer fit.

- A run met a refused `gh pr create`, declared a hard blocker and **idled 38 minutes**. The user said to open the PR; the **identical command succeeded immediately**.
- Another had `gh pr merge` blocked, retried with a trailing pipe removed, and it went through.
- A third saw about ten denied and rephrased calls, with two merges passing while a third was blocked twice in thirty seconds.
- **Four runs refused to reach the merge by another route**, reasoning that a local `git merge` after a blocked `gh pr merge` is *"exactly the irreversible outward-facing action the block exists to guard, through a different command."*

**Those four read the rule correctly as it was written. The rule was wrong.** It conflated the harness's permission classifier with the project's correctness gates. The classifier guards an authorisation this skill's invocation already granted, so a refusal closes a *route*; the project's hooks guard whether the code is sound, and a refusal there closes the *change*. The four handovers each cost hours and every branch landed unchanged once the user ran the command himself.

What survives from them is the half that was always right: **do not reach a denied effect by disarming a correctness gate**, and do not reason around a check that could not run. What changes is that taking a different *sanctioned route* to an authorised effect — `git merge` where the project merges locally, `gh api` where the forge supports it — is a route change to be announced, not a bypass to be refused.

- **The counter-case still stands:** a blocked non-mutating merge preflight was *not* retried; the session reasoned around the missing evidence and merged anyway. **A check that could not run is not a check that ran green.**

Empirical note, with its own caveat: `gh` write commands issued **bare** — no pipe, no redirect, body via `--body-file` — correlate with success. It is a good first retry and **not** a cure: one run was refused **twice**, once with an inline `--body` heredoc and once with `--body-file`.
```

- [ ] **Step 4: Add the pre-push migration-ledger gate to `step-05-push-and-pr.md`**

```markdown
## The pre-push migration-ledger gate, and the one remedy you must not take

Fired in **6 of 20** observed close-outs, at this step's own push points. Where concurrent sessions apply migrations from unmerged branches, the remote ledger holding rows with no local file is the **normal** state, not a fault.

The hook blocks and recommends a ledger reconcile. **Do not run it.** As one run put it: *"`db:doctor`, which the hook's own message recommends, would have reconciled the ledger by reverting peers' applied work."*

The sanctioned route, executed identically in three runs:

1. Restore the peer files from **their owning refs** — `git show <ref>:<path> > <path>`, or `git restore --source=<ref> --worktree -- <paths>`. **Never `git checkout`**, which writes the index.
2. Leave them **untracked and unstaged**. Verify it: `git diff --cached --name-only` must be empty.
3. Push with the hook running and passing **on its own terms**.
4. Delete the borrowed files immediately afterwards.

No hook is disabled, no flag bypassed, no link state altered — which is exactly why this is the sanctioned route and the reconcile is not.

**Re-derive the row list at the moment of use.** One run watched it go 9 → 13 → 14 → 15 → 16 within hours as peers kept applying.
```

- [ ] **Step 5: Add split-by-ancestry to `step-05-push-and-pr.md`**

```markdown
## A branch that cannot merge as one unit

When two pipelines react to the same push with nothing ordering them — a host's git integration and a CI workflow, say — and the branch's code calls something that exists only after its own migration applies, **splitting commits inside one pull request does not help.** As the run that met it wrote: *"the race is between two pipelines reacting to one push."*

Split **by ancestry**, which needs no cherry-pick and rewrites no history:

1. `git grep <new interface names> <commit>` to prove the earlier commit introduces no call to it.
2. `git log -S<name>` to name the commit that does.
3. PR A is `origin/<default>..<that commit minus one>`; PR B is the remainder, which appears automatically once A merges.

**The gate between them is the first pipeline going green — not elapsed time.** Read the job, not the clock.
```

- [ ] **Step 6: Add the two conflict lanes and the default-branch pre-check to `step-07-merge.md`**

```markdown
| `generated` | The file is produced by a tool from a source of truth — generated types, a lockfile, a compiled catalogue | **Regenerate it from that source.** Never a merge, never a side. One close-out hit `types.ts` **four times** and regenerated every time. |
| `union-already-computed` | One side already contains the other's content, because it was computed across all the branches while the others carry the stale base | **Take the side that already holds the union.** This looks *exactly* like `additive-vs-additive` and taking "both" re-introduces stale rows. The test: does either side's content already contain the other's? Then it is not additive. |
```

And before the merge itself:

```markdown
### Who holds the default branch

Ask before the local merge, because the two failures are opposite and four days apart.

- **The main checkout is on a peer's branch, with uncommitted work.** `git checkout <default>` would yank the branch out from under a live session. **Merge in a dedicated worktree on the default branch instead** — bootstrapped and hook-verified — and never touch the peer's files. One run did exactly this.
- **A peer worktree already holds the default branch**, so `git checkout` is refused outright. **Stop, report, resume later.** One run did, and completed its cleanup in a later turn once the peer released it. Step 9 says plainly that this is a terminal state and not a failure.
```

- [ ] **Step 7: Run the assertions and verify they pass**

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

Expected: twenty-five `PASS`, `exit=0`.

- [ ] **Step 8: Byte budgets, then commit**

```bash
cd "$WT" && bash skills/session-end/verify/budgets.sh
```

Expected: exit 0. Round 5: a bare `wc -c` here only printed sizes, so an oversized file could be committed past a budget the plan claims to enforce.

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-end/SKILL.md skills/session-end/steps/step-05-push-and-pr.md skills/session-end/steps/step-07-merge.md skills/session-end/references/traps.md skills/session-end/verify/assert-findings.sh && git commit -F- <<'EOF'
feat(session-end): separate the permission guard from the correctness guard

The router told a blocked run to fall back to a local merge; traps.md, in
the same skill, praised two runs for refusing to do exactly that. Four runs
refused it in the end, each costing hours, each branch landing unchanged
once the user ran the command himself.

Both halves were reading one word -- bypass -- that covers two unrelated
things. The harness classifier guards an authorisation this skill's
invocation already granted, so a refusal closes a route: retry bare, take
another sanctioned route, name it in the report. The project's hooks guard
whether the code is sound, so a refusal there closes the change: escalate,
and never disarm one to get past it.

traps.md#classifier-denials is rewritten rather than deleted. Those four
runs read the rule correctly as written and the incidents are worth keeping;
what changed is the verdict, and the entry says so.

Also lands three things the runs had and the skill did not: the pre-push
migration-ledger gate with the borrow-and-restore route (6 of 20 runs, and
the remedy the hook itself recommends is the one that reverts peers' work),
splitting a branch by ancestry when two pipelines race on one push, and two
conflict lanes -- generated, and union-already-computed, which looks exactly
like additive-vs-additive and corrupts when treated as one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 9: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "6/10 the ruling landed. SKILL.md's bypass section is now the two-guard table (permission vs correctness); traps.md#classifier-denials REWRITTEN not deleted, incidents kept and verdict changed with the reason stated in the file. Plus the pre-push ledger gate with borrow-and-restore, split-by-ancestry, and the generated + union-already-computed conflict lanes, and the who-holds-the-default-branch pre-check with both exits. 11 assertions written first, observed failing, then passing. Running total 25/25."
```

---

## Task 7: Steps 8-9 — the merged SHA, and three cleanup facts

**Evidence C5, A4, A5, D5.**

**Files:**
- Modify: `skills/session-end/steps/step-08-sync-and-cleanup.md`
- Modify: `skills/session-end/verify/assert-findings.sh`

- [ ] **Step 1: Add the assertions and watch them fail**

```bash
# --- Steps 8-9 --------------------------------------------------------------
want C5-merged-sha   steps/step-08-sync-and-cleanup.md 'Verify production serves the **merged SHA, by identifier**'
want A4-two-preds    steps/step-08-sync-and-cleanup.md '`git branch -d` has two predicates, not one'
want A4-detach       steps/step-08-sync-and-cleanup.md 'git worktree add --no-checkout --detach <merge-sha>'
want A5-tree-level   steps/step-08-sync-and-cleanup.md 'Record that tree-level proof, per file, in the ledger'
want D5-nongit       steps/step-08-sync-and-cleanup.md '`Permission denied`, `Directory not empty`, `Filename too long`'
want D5-exit0-lie    steps/step-08-sync-and-cleanup.md 'exited 0 while leaving the directory in place'
want D1-partial      steps/step-08-sync-and-cleanup.md 'Partial cleanup is a legitimate terminal state'
```

- [ ] **Step 2: Add the merged-SHA proof to Step 8**

```markdown
**"Up and green" and "running the code we merged" are different claims, and only the second is the goal.** Verify production serves the **merged SHA, by identifier** — the deployment id, the image version, the commit the host reports — not that a health endpoint answers 200.

Measured: a post-merge deploy failed, the cause was fixed, and the host redeployed **the old image** on its own. Production was healthy and still not running the merged code. The run caught it, re-ran the failed job, and confirmed the new version by id.
```

- [ ] **Step 3: Add the three cleanup facts to Step 9**

```markdown
**`git branch -d` has two predicates, not one.** It measures against the branch's **upstream** *and* against the **HEAD of the checkout you run it in**. Different runs have hit each half, and neither refusal means "use `-D`":

- Upstream behind → prove containment with `git log <branch> --not origin/<default>` empty, **delete the remote ref first**, then `-d` succeeds on its own.
- The shared checkout's HEAD is a peer's branch and cannot be moved → create `git worktree add --no-checkout --detach <merge-sha>` and run `-d` from there. **The deletion succeeding there is itself the containment proof.** A `--no-checkout` tree only *looks* dirty, so removing it needs no `--force`.

**`-D` keeps its prohibition, with exactly one escape.** A branch whose commit is not an ancestor of the default branch but whose **tree is identical** — `git diff origin/<default> <branch>` empty — carries no content to lose. Record that tree-level proof, per file, in the ledger. Never `-D` on age, on a hunch, or to clear a refusal you did not diagnose.

**`git worktree remove` fails for reasons that are not git refusals.** `Permission denied`, `Directory not empty`, `Filename too long` — on Windows these are filesystem path limits over deep dependency trees, and `git worktree list` will show the worktree **already deregistered**. Confirm that, run `git worktree prune`, then remove the directory.

**And confirm removal by listing, not by the exit code.** One run's background `rm -rf` **exited 0 while leaving the directory in place**. It was caught by listing the directory. That run then left a lock-held cache tree alone on purpose — gitignored, regenerable, and *"killing processes blind to remove cosmetic residue is a worse trade."*

**Partial cleanup is a legitimate terminal state.** If the default branch cannot be made current safely — a peer holds it, or pulling would collide with their uncommitted work — stop, leave the branch, and report. To resume: confirm the peer released it, `git checkout <default>` and `git pull`, prove containment with `git merge-base --is-ancestor <sha> HEAD`, then delete remote ref and local branch. One run closed exactly this way, a turn later. It is not a failure and it is never a reason to force anything.
```

- [ ] **Step 4: Assertions pass, byte budget, commit**

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

```bash
cd "$WT" && bash skills/session-end/verify/budgets.sh
```

Expected: exit 0 from both, thirty-seven assertions passing.

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-end/steps/step-08-sync-and-cleanup.md skills/session-end/verify/assert-findings.sh && git commit -F- <<'EOF'
feat(session-end): prove production runs the merged code, and finish cleanup honestly

A post-merge deploy failed, was fixed, and the host redeployed the old image
by itself. Production was healthy and still not running what we merged.
Step 8 now verifies the merged SHA by identifier, not a 200.

Step 9 gains what the runs learned the hard way: git branch -d measures
against the upstream AND against the HEAD of the checkout you run it in, and
the remedy for the second is a --no-checkout --detach worktree whose
successful -d is itself the containment proof. -D keeps its prohibition with
one escape, a recorded tree-level proof. worktree remove fails for Windows
path reasons that are not git refusals. And rm -rf has been observed exiting
0 while leaving the directory in place, so removal is confirmed by listing.

Partial cleanup is named as a terminal state with a resume procedure. One
run ended there correctly and closed a turn later; the skill treated that as
an incomplete run.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 5: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "7/10 Steps 8-9. Merged-SHA-by-identifier proof, the two -d predicates with the --no-checkout --detach remedy, -D's single tree-level escape, non-git worktree removal failures, rm -rf exiting 0 over an undeleted directory, and partial cleanup as a terminal state with its resume procedure. 6 assertions first-fail-then-pass. Running total 31/31."
```

---

## Task 8: Decision 4 — the interfaces outside `session-end/`

**Files:**
- Modify: `skills/session-build/scripts/ledger.py`
- Modify: `skills/session-build/steps/step-06-closeout.md`
- Modify: `docs/cadeia-session.md:205-213`
- Modify: `skills/session-end/verify/assert-findings.sh`

- [ ] **Step 1: Assertions first**

```bash
# --- Decision 4 -------------------------------------------------------------
want I-ledger-vocab  ../session-build/scripts/ledger.py 'PENDINGS-RULING'
want I-fork-init     ../session-build/scripts/ledger.py 'fork'
want I-agentid       ../session-build/steps/step-06-closeout.md 'agentId'
```

`docs/cadeia-session.md` sits outside `$HERE`, so assert it separately in the script with an absolute-from-repo-root path.

- [ ] **Step 2: Fix the fork-ledger-creation defect and extend the vocabulary**

**The defect, found at this fork's own bootstrap and reproduced:** `cmd_append` dies with `no ledger at <path> - run ledger.py init first` when the file is absent, but the `init` subparser is wired `common(sp, fork=False)`, so `--fork` is not an accepted argument for `init` and `target()` can never resolve to `fork-<slug>.md` from that command. **A fork cannot create its own ledger file through the script at all.** Every fork in every previous run either hit this or wrote its checkpoints somewhere the sweep does not read — which is the precise failure the sweep's format rule exists to prevent.

Fix by letting `init` take `--fork`:

```python
    sp = sub.add_parser("init", help="create the orchestrator ledger, or a fork's")
    common(sp)                      # was: common(sp, fork=False)
    sp.add_argument("--run-id", required=True)
    sp.add_argument("--specs", default="")
    sp.set_defaults(func=cmd_init)
```

Extend the vocabulary:

```python
BOOKKEEPING = {
    "RULING", "READING", "ESCALATION", "RELAY", "PROFILE", "NOTE",
    "PENDINGS-SOURCE",
    # PENDINGS-RULING: one per pendings entry a session-end fork ruled against
    # its own diff - `PENDINGS-RULING <entry heading> <lane> <evidence>`, where
    # lane is resolved / stale-cause / moved / untouched. The fork RULES; the
    # orchestrator performs the single write. Closing N branches in sequence
    # runs Half A N times over one file and each pass can reopen what the last
    # one closed.
    "PENDINGS-RULING",
    "CLOSED",
}
```

`READY` is already in the checkpoint set — verify before adding it twice:

```bash
cd "$WT" && test "$(grep -c '"READY"' skills/session-build/scripts/ledger.py)" -eq 1
```

Expected: exit 0 — `READY` is already declared exactly once in the checkpoint vocabulary, so it must not be added again. A non-zero exit means either it is absent (add it) or already duplicated (fix that first). Round 7: the first draft only printed the matches, which cannot detect zero or two. Note `grep -c` is safe **here** because the result is compared with `test`; it is banned in `assert-findings.sh`, where its exit status would be read directly and would invert on a zero count.

- [ ] **Step 3: Prove the fix behaviourally, not by parsing**

Round 1: a Python parse check plus one happy path does not verify the init safety invariants or the new vocabulary. `skills/session-end/verify/ledger-probe.sh`:

```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/verify/lib.sh"
L="$(cd "$HERE/../.." && pwd)/skills/session-build/scripts/ledger.py"
D="$TMPBASE/ledger-probe.$$"
rm -rf "$D"; mkdir -p "$D"
trap 'rm -rf "$D"' EXIT

# 1. init --fork creates fork-<slug>.md and NOT ledger.md
if python "$L" init --dir "$D" --run-id probe --fork probe-slug >/dev/null 2>&1; then ok "init --fork accepted"; else bad "init --fork rejected"; fi
if [ -f "$D/fork-probe-slug.md" ]; then ok "fork file created"; else bad "fork file missing"; fi
if [ ! -f "$D/ledger.md" ]; then ok "init --fork did not create the orchestrator ledger"; else bad "init --fork also wrote ledger.md"; fi

# 2. re-init REFUSES rather than truncating an existing ledger.
#    Round 2: "any nonzero" also passes on a syntax error or a missing
#    interpreter, so require the specific exit code AND the specific message.
err="$D/reinit.err"
python "$L" init --dir "$D" --run-id probe --fork probe-slug >/dev/null 2>"$err"; rc=$?
if [ "$rc" -eq 2 ] && grep -qF "refusing to re-init" "$err"; then
  ok "re-init refused with exit 2 and the expected message"
else
  bad "re-init: want exit 2 + 'refusing to re-init', got rc=$rc msg=$(head -1 "$err")"
fi

# 3. both new vocabulary entries append
for t in PENDINGS-RULING CLOSED READY; do
  if python "$L" append --dir "$D" --fork probe-slug --type "$t" --text "probe $t" >/dev/null 2>&1; then ok "append $t"; else bad "append $t rejected"; fi
done

# 4. an unknown type is still refused - the vocabulary is a gate, not a suggestion
if python "$L" append --dir "$D" --fork probe-slug --type NOT-A-REAL-TYPE --text x >/dev/null 2>&1; then bad "unknown type accepted"; else ok "unknown type refused"; fi

# 5. a hand-written CODEX APPROVED line is still refused
if python "$L" append --dir "$D" --fork probe-slug --type CODEX --text "APPROVED ROUNDS 1" >/dev/null 2>&1; then bad "hand-written CODEX APPROVED accepted"; else ok "hand-written CODEX APPROVED refused"; fi

finish
```

```bash
cd "$WT" && bash skills/session-end/verify/ledger-probe.sh
```

Expected: exit 0, nine `PASS`. **Run it once before the fix** — case 1 must fail on `init --fork rejected`, which is the defect this task exists to close.

- [ ] **Step 4: `handoff.md` gains the agentId map**

In `step-06-closeout.md` §6.6, the handoff field list gains, and the reason is stated:

```markdown
**and the `spec slug → agentId` map for every fork.** `/session-end`'s fork lane cannot revive a fork without it, and a real handoff recorded only *"Fork: alive, worktree untouched"* — true, and useless as an address. Names are not unique on this machine; the agentId is what makes one unambiguous. If a fork is dead, say so and give the id anyway: the lane spawns a fresh fork pointed at `fork-<slug>.md` on disk, and never assumes a fork remembers anything.
```

- [ ] **Step 5: Correct `docs/cadeia-session.md`**

Two changes. First, the *"Depois do run"* passage now names the three lanes rather than only the fresh-session path. Second — and this one is a **factual correction** — line 213 currently states `EnterWorktree` is refused *"para a orquestradora e para toda filha"*. That is false and `session-build`'s own `steps/step-03-isolate.md` §3.2 already says so: the refusal binds **forks**; a plain session enters freely, and one orchestrator entered five worktrees in sequence. Rewrite it to match, in the file's own Portuguese.

- [ ] **Step 6: Gates, assertions, commit**

```bash
cd "$WT" && "$SKILL/scripts/gate.sh" ledger-py-parse python -c "import ast; ast.parse(open('skills/session-build/scripts/ledger.py',encoding='utf-8').read())" && bash skills/session-end/verify/assert-findings.sh
```

Expected: `EXIT 0`, then exit 0 from the assertion script with forty passing.

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-build/scripts/ledger.py skills/session-build/steps/step-06-closeout.md docs/cadeia-session.md skills/session-end/verify/assert-findings.sh && git commit -F- <<'EOF'
fix(ledger): a fork could not create its own ledger file

cmd_append refuses when the file is absent and tells you to run init; init's
subparser is wired fork=False, so --fork is not a valid argument and target()
can never resolve to fork-<slug>.md from it. Every fork in every run either
hit this or wrote its checkpoints where the sweep does not read -- which is
the exact failure the sweep's format rule exists to prevent. Found by this
fork at its own bootstrap.

Also adds PENDINGS-RULING and CLOSED, the vocabulary session-end's fork lane
reports in, and puts the spec slug -> agentId map into handoff.md. A real
handoff said "Fork: alive, worktree untouched" -- true, and useless as an
address.

And corrects cadeia-session.md, which still says EnterWorktree is refused
for the orchestrator as well as the forks. It is not: the refusal binds
forks, one orchestrator entered five worktrees in sequence, and
session-build's own step-03 was corrected months ago.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 7: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "8/10 Decision 4 interfaces. ledger.py: init now accepts --fork (a fork previously could not create its own ledger at all), plus PENDINGS-RULING and CLOSED. step-06-closeout: handoff.md carries spec slug -> agentId with the reason. cadeia-session.md: three lanes, and the false EnterWorktree claim corrected against session-build's own step-03. Fix proved by re-running the exact command that failed at bootstrap. Running total 40/40."
```

---

## Task 9: The fork lane

**Files:**
- Create: `skills/session-end/steps/lane-fork-orchestrator.md`
- Create: `skills/session-end/references/fork-contract.md`
- Create: `skills/session-end/dispatch-prompts.md`
- Modify: `skills/session-build/references/fork-contract.md` (`--expect`, `MERGE origin/<default> BEFORE verify`)
- Modify: `skills/session-end/verify/assert-findings.sh`

**Interfaces:**
- Consumes: `gate.sh --expect` (Task 3) and the `PENDINGS-RULING` checkpoint (Task 8). **Round 1 caught this ordering inverted:** the fork lane documents a protocol that `ledger.py` rejects until the vocabulary exists, so a commit landing the lane first would ship a documented checkpoint the tooling refuses.
- Produces: the vocabulary `GO <slug> verify <branch>`, `RELEASE verify <branch>`, `PENDINGS-RULING <heading> <lane> <evidence>`, `MERGE origin/<default> BEFORE verify`.

- [ ] **Step 1: Assertions first**

```bash
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
```

- [ ] **Step 2: Write `steps/lane-fork-orchestrator.md`**

Carries, from spec Decision 2: the single dispatch with the first fork in merge order holding `GO <slug> verify <branch>` and the rest in `HOLD`; what a fork does while holding (Step 0 inventory, Step 4 Half A **rulings only, never editing the file**, the Half B dossier); the serialised verify; the orchestrator keeping PR, merge, post-merge and the pendings write; the four consequences (orchestrator never enters a worktree, no fork-side deploy, pendings written once on the last branch in merge order, `handoff.md` carries agentIds); the degradation ladder; and the measurements behind `LOCK verify` — load average 80.61 peaking at 98.88 on ~10 cores, a `git push` stuck 43 minutes in its pre-push hook, and `LOCK verify` already used inside a real `session-end` when a peer held it.

It must also carry, plainly: **this lane is unexercised.** No real `N ≥ 2` close-out has run it. The inline and sequential lanes are unchanged, so the blast radius is the lane itself.

And the named limitation: *"resolve from a measurement" is weaker for the last branch in merge order* — entries touched by branches 1..N-1 are measured against a default branch that already carries those merges; the last branch's own are measured against its tree before merging. The residual exists in the per-branch lane too.

- [ ] **Step 3: Write `references/fork-contract.md` and `dispatch-prompts.md`**

The `session-end` fork's contract differs from `session-build`'s in three ways, and the file says so: it performs **no** deploy, it emits `PENDINGS-RULING` lines and **never writes the pendings file**, and it may perform exactly one merge — `MERGE origin/<default> BEFORE verify`, ordered by the orchestrator alongside the verify grant.

- [ ] **Step 4: Add `--expect` and the merge directive to `session-build/references/fork-contract.md`**

Under the reporting lines, after the `gate.sh` mention:

```markdown
**A gate that did not finish did not decide.** Run gates with `--expect <the runner's own summary line>`. A log without it prints `GATE <label> UNDECIDED` and exits 75 — that is **absent verification**, not a red. Report it as `BLOCKED gate did not complete`, never as a failing test: an orchestrator that receives `BLOCKED gate red` triages it `regression` and stops the run over a suite that was merely killed.
```

- [ ] **Step 5: Assertions pass, budgets, commit**

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

```bash
cd "$WT" && bash skills/session-end/verify/budgets.sh
```

Expected: exit 0 from both, fifty assertions passing. Round 2: the first draft still used a bare `wc -c` here, which cannot fail, so an oversized lane file could have been committed past a budget the plan claims to enforce.

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902" && git add skills/session-end/steps/lane-fork-orchestrator.md skills/session-end/references/fork-contract.md skills/session-end/dispatch-prompts.md skills/session-build/references/fork-contract.md skills/session-end/verify/assert-findings.sh && git commit -F- <<'EOF'
feat(session-end): a fork lane for closing N branches without dying on context

session-build with N>=2 ends holding N pushed branches, N worktrees and a
handoff, and session-end had one bullet about it: enter each worktree in
turn. That works -- one orchestrator did five -- and it dies on context,
carrying five inventories, five suite logs and five diffs at once.

The split is by what is global. Forks do the reading: their own Step 0
inventory, Step 4 Half A rulings against their own diff, and a dossier from
their PARKED lines. They never edit the pendings file. The orchestrator
keeps every global act -- PR, merge, post-merge sync, cleanup, and one
single write of the pendings file on the last branch in merge order.

Verification is serialised through LOCK verify <branch>, named resource and
all: two forks in a real run sent a bare LOCK verify and left permanently
outstanding false positives in the sweep. The orchestrator takes the same
lock for its own post-merge union suite, because it is not exempt from the
rule it enforces.

Stated in the file, not buried: this lane is unexercised. No real N>=2
close-out has run it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

- [ ] **Step 6: Ledger**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type TASK --text "9/10 fork lane written: steps/lane-fork-orchestrator.md, references/fork-contract.md, dispatch-prompts.md, plus --expect and MERGE origin/<default> BEFORE verify in session-build's fork contract. Lane is marked UNEXERCISED in its own text. 9 assertions first-fail-then-pass. Running total 50/50."
```

---

## Task 10: Full verification, the two dry reads, and push

**Files:** none modified — this task only measures.

- [ ] **Step 1: Every gate the project has, accumulating failures**

Round 1: a bare `for` loop over gates returns the last iteration's status, so one failure followed by one pass reads green. `skills/session-end/verify/all-gates.sh`:

```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
. "$HERE/verify/lib.sh"
G="$HOME/.claude/skills/session-build/scripts/gate.sh"
cd "$REPO" || { bad "cannot cd $REPO"; finish; }

run() {  # run <label> <command...>
  line=$("$G" "$@" 2>&1) ; rc=$?
  printf '%s\n' "$line"
  case "$line" in
    *" EXIT 0 "*)      ok   "$1" ;;
    *" UNDECIDED "*)   bad  "$1 - gate did not complete" ;;
    *WRAPPER_ERROR*)   bad  "$1 - wrapper error" ;;
    *)                 bad  "$1 - rc=$rc" ;;
  esac
}

run install-sh-parse bash -n install.sh
run statusline-parse node --check statusline/statusline.mjs
run settings-json node -e "JSON.parse(require('fs').readFileSync('settings.example.json','utf8'))"

# `for f in $(find ...)` splits on whitespace, which breaks on any path
# containing a space. Round 2 caught it; -print0 with a while-read avoids it.
# The loop body runs in THIS shell (process substitution, not a pipe), so
# FAILED survives - a pipe would put it in a subshell and lose every failure.
while IFS= read -r -d '' f; do
  run "sh-$(printf '%s' "$f" | tr '/.' '--')" bash -n "$f"
done < <(find skills -name '*.sh' -print0)

while IFS= read -r -d '' f; do
  run "js-$(printf '%s' "$f" | tr '/.' '--')" node --check "$f"
done < <(find skills \( -name '*.mjs' -o -name '*.js' \) -print0)

while IFS= read -r -d '' f; do
  run "py-$(printf '%s' "$f" | tr '/.' '--')" python -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$f"
done < <(find skills -name '*.py' -print0)

finish
```

```bash
cd "$WT" && bash skills/session-end/verify/all-gates.sh
```

Expected: exit 0. **`install.sh` and `lint.yml` belong to the peer fork — gated here, never edited.** Note the `UNDECIDED` case is handled explicitly: this harness must not read its own new state as a pass.

- [ ] **Step 2: The three structural checks, against the trees where their claims hold**

`assert-findings.sh`, `budgets.sh` and `xrefs.sh` run against the current tree:

```bash
cd "$WT" && bash skills/session-end/verify/assert-findings.sh
```

```bash
cd "$WT" && bash skills/session-end/verify/budgets.sh
```

```bash
cd "$WT" && bash skills/session-end/verify/xrefs.sh
```

Expected: exit 0 from each, with fifty assertions passing in the first.

**`reconstruct.sh` is different, and round 1 caught the first draft handling it incoherently.** Its claim — *this split moved text and wrote none* — is true only of the Task 2 commit; Tasks 4 through 9 deliberately wrote content the original never had, so running it against the current tree must fail and proves nothing either way. Re-run it against the **Task 2 tree**, exported whole:

```bash
cd "$WT" && T2=$(git log --format=%H --grep='^refactor(session-end): split the monolith' -n 1) && test -n "$T2" && echo "task2=$T2"
```

Expected: a SHA and exit 0. The literal `<task-2-sha>` in the first draft was worse than a placeholder — in bash, `<` is a redirection and the command could not have run at all.

```bash
cd "$WT" && T2=$(git log --format=%H --grep='^refactor(session-end): split the monolith' -n 1) && rm -rf "$TMPBASE/t2" && mkdir -p "$TMPBASE/t2" && git archive "$T2" skills/session-end | tar -x -C "$TMPBASE/t2" && git show "$T2^:skills/session-end/SKILL.md" > "$TMPBASE/t2/presplit.md" && bash "$TMPBASE/t2/skills/session-end/verify/reconstruct.sh" "$TMPBASE/t2/presplit.md" "$TMPBASE/t2/skills/session-end"
```

Expected: exit 0. **Everything comes from git**: the checker and the step files from the split commit, and the pre-split original from its parent via `git show "$T2^:..."`. Round 2 caught the first draft still reaching for `$TMPBASE/session-end-presplit.md`, an untracked snapshot that may not survive between tasks or sessions — which contradicted this step's own claim that nothing is read from outside the commit.

- [ ] **Step 3: `gate.sh --expect` behavioural tests, both shells**

```bash
cd "$WT" && bash skills/session-end/verify/expect-flag.sh skills/session-build/scripts/gate.sh
```

```bash
cd "$WT" && bash skills/session-end/verify/expect-flag.sh skills/session-end/scripts/gate.sh
```

```bash
cd "$WT" && pwsh -NoProfile -File skills/session-end/verify/expect-flag.ps1 -Gate skills/session-build/scripts/gate.ps1
```

Expected: exit 0 from each. If no PowerShell host runs, record `gate.ps1 UNVERIFIED` in the ledger and the final report — never as a pass.

- [ ] **Step 4: Dry read one — the fork lane against a real handoff**

Read `C:/dev/Projects/MCPlace/.superpowers/session-build/20260901-0055/handoff.md`. For each field the lane consumes — branch list, worktree paths, merge order and its reasons, deploy set, migrations and whether their branch merged, live-fork status, project profile, `PENDINGS-SOURCE` — state whether the lane would have **found** it or **improvised** it. Write the answers into the ledger, one line per field.

**`spec slug → agentId` will be absent.** That is the gap Task 8 closes, and this dry read is the evidence the fix was needed rather than assumed.

- [ ] **Step 5: Dry read two — the content against three ledgers it was not drawn from**

Pick three `session-end` ledgers the evidence document does not quote. Candidates, all unquoted: `Kidsy Hub/20260823-1900`, `Kidsy Hub/20260819-0600`, `Projeto Polo Fenix/20260811-2300`.

For each, answer in the ledger: **would the rewritten skill have produced this run's behaviour, or fought it?** Record any place the new text would have made a *correct* run harder — that is the finding this read exists to surface, and reporting none from three ledgers is a result to be suspicious of rather than proud of.

- [ ] **Step 6: Push**

```bash
cd "$WT" && test "$(git branch --show-current)" = "refactor/session-end-router-fork-lane-20260902"
```

Expected: exit 0.

```bash
cd "$WT" && test -z "$(git status --porcelain)" || { git status --porcelain; false; }
```

Expected: exit 0. On a dirty tree this prints what is dirty and exits non-zero — a bare `git status --porcelain` exits 0 regardless, so the first draft could have pushed with uncommitted artifacts. Anything dirty is either an uncommitted change or a stray artifact: resolve it before pushing, and name any deliberate leftover in the report.

```bash
cd "$WT" && git push -u origin refactor/session-end-router-fork-lane-20260902
```

Never force-push. Confirm the ref arrived by querying the remote, not by the command's exit code:

```bash
cd "$WT" && LOCAL=$(git rev-parse HEAD) && REMOTE=$(git ls-remote origin refs/heads/refactor/session-end-router-fork-lane-20260902 | cut -f1) && test "$LOCAL" = "$REMOTE" && echo "ref confirmed $LOCAL"
```

Expected: exit 0. The `test` is the gate — a push that hung or was rejected leaves the SHAs different and this exits non-zero.

- [ ] **Step 7: Ledger and report**

```bash
python "$SKILL/scripts/ledger.py" append --dir "$LEDGER" --fork "$SLUG" --type PUSHED --text "refactor/session-end-router-fork-lane-20260902 <first7>..<last7>, ref confirmed by comparing git rev-parse HEAD against git ls-remote."
```

---

## Rounds 1 and 2 of codex-review — what was applied, and what was not

All twenty findings were accepted; none was rejected. They share one root, and it is worth naming because it is the same defect this plan's own subject matter is about: **most of the first draft's verification was structurally incapable of failing.**

- `cmd; echo "exit=$?"` — the compound always exits 0 (findings 6, and the shape recurred in nine steps).
- `for` loops over gates returning only the last iteration's status (7, 19).
- Checks that printed `ORPHAN`, `DRIFT` or a byte count and then exited 0 regardless (17, 18, 19).
- Assertions matching bare words — `generated`, `fetch`, `fork`, `agentId` — that **already matched prose in the target files**, so the mandatory first-fail step could never have happened and the assertion would have certified content nobody wrote (12, 13).
- A reconstruction check whose only demonstrated failure mode was a missing file, comparing sorted multisets with blank lines dropped, and not stripping the `# Step <N>` heading it knew each file would gain (1, 2, 3).
- Task 10 re-running that checker against the wrong tree, via a literal `<task-2-sha>` that bash would have parsed as a redirection (4, 5).

Three further findings were design errors rather than verification errors, and each changed the plan's shape:

- **`--expect` was specified as a regex** and implemented with POSIX ERE in `sh` and .NET regex in PowerShell — one documented flag meaning two different things (10, 11). It is now a **fixed string** in both, which is also what the use case actually needs.
- **Task 8 consumed `PENDINGS-RULING` from Task 9**, so the fork lane would have shipped a documented protocol that `ledger.py` rejects until a later commit (16). The two tasks are swapped.
- **`expect-flag.sh` permitted its real-red case to `SKIP`**, so the suite could pass while leaving one of `--expect`'s core claims untested (8), and `gate.ps1` had only a parse check on the platform it exists for (9).

Two things were tightened beyond what the review asked, because the same reasoning applied:

- `assert-findings.sh` matches **fixed strings**, not regexes. The content is markdown full of backticks, asterisks and pipes; escaping that into an ERE is the same trap as finding 10 in a different costume.
- `all-gates.sh` treats `UNDECIDED` as a failure explicitly. Without that, the harness verifying this change would read its own new state as a pass — which would be a fitting way to ship a bug about gates that cannot fail.

### Round 2 — fifteen more, all accepted

Round 1 fixed the *checks*; round 2 found that two of the replacements **still could not pass**, and that the corrections had left contradictions behind.

- **`reconstruct.sh` could not have gone green** (1, 2). It appended the router verbatim without stripping the `<!-- split-addition -->` blocks the plan itself specifies, so coverage could never balance. Worse, fidelity assumed each step body is one contiguous run of the original — false the moment `Common mistakes` and `Red flags` rows are moved in from elsewhere, which this very plan requires. Fixed with `<!-- moved -->` fragment markers and per-block containment.
- **The mutation tests did not test what they claimed** (3, 4). `sed -i '4p'` would have duplicated a line inside a step body and broken fidelity too, so it never demonstrated a coverage-only failure; and the whole block sat at Step 3 while instructing the reader to run it after Step 5, which an executor following checkbox order cannot do. The duplicate now appends an original line to the **router**, which coverage sees and fidelity does not, and the block moved to Step 6b.
- **`TMPBASE` was defined only inside scripts that source `lib.sh`** while standalone steps used it bare (5). `rm -rf "$TMPBASE/t2"` could have expanded to `rm -rf /t2`. It is now defined and validated in the plan's global variables, with an explicit refusal of `/` and empty.
- **Task 10 still read an untracked snapshot** (6) while claiming everything came from the Task 2 commit. It now recreates the pre-split original with `git show "$T2^:skills/session-end/SKILL.md"`.
- **Checks that still could not fail** (8, 9): Task 1's drift survey printed differences without rejecting an extra or missing one — it now diffs an actual list against an expected list; and Task 9 still used a bare `wc -c` where `budgets.sh` exists.
- **Word-splitting** (10): `for f in $(find ...)` breaks on any path containing a space. Replaced with `-print0` and a `while read -d ''` fed by process substitution — a pipe would have put the loop in a subshell and lost every recorded failure.
- **Untested and uncommitted artifacts** (7, 11): `expect-flag.ps1` was created, depended on by Task 10, and never added to a commit; and only one of the two `gate.ps1` copies was behaviourally tested.
- **Assertions too weak to mean anything** (14): `ledger-probe.sh` treated *any* non-zero exit as proof that re-init refuses, which a syntax error or missing interpreter also satisfies. It now requires exit 2 **and** the specific `refusing to re-init` message.
- **A sweep narrower than its own claim** (15): `xrefs.sh` checked four hard-coded files while the plan asserts fourteen references live outside `SKILL.md`. It now derives them repo-wide with named exclusions.
- **Stale text contradicting the revision** (12, 13): the self-review still described `--expect` as an ERE checked with `grep -qE`, and Task 3 still offered "three passes plus one SKIP" for a test that no longer has a skip path.

### Round 3 — seven more, all accepted

- **The router's own retained text was never fidelity-checked** (3). Only its line multiset was compared, so its sections, tables and paragraphs could be reordered arbitrarily while reconstruction passed — the round-1 defect surviving in the one file nobody was checking. The router now goes through the same block model as every step file.
- **Repeated table headers broke the model** (1). The plan told the split to repeat a table header above a `<!-- moved -->` fragment as "ordinary new text", which the checker then counted as part of the preceding original block. Headers now go inside `<!-- split-addition -->`, and the marker mechanism is uniform across router and step files.
- **No marker validation** (2). `blocks.py` now rejects nested `<!-- split-addition -->`, unmatched closes and unclosed regions at EOF, and it is Python rather than layered `awk` precisely because that validation is what `awk` expresses badly. **`moved` is a single boundary and has no pairing to validate** - round 4 caught the plan claiming a check the code neither made nor needed.
- **A glob cannot detect a missing file** (6). The eight step filenames are enumerated explicitly, and an unexpected `step-*.md` is also a failure.
- **Globals were assigned, not exported** (4), while the plan claimed every step inherited them. Each Bash call is its own process; the block is now `export`ed and repeated where it matters.
- **GNU-specific `\?` in a portability-sensitive script** (5) — gone entirely, since `blocks.py` never emits a marker line.
- **Stale ledger text** (7) claiming a first failure of "exit 2, missing files" that the revised suite no longer produces.

### And then it was run

Codex reviews the document; it cannot execute it. So the model was extracted from this plan and **executed against a synthetic split** — a router with an addition and a trimmed table, two step files, one carrying a moved fragment.

It found two things no round had:

- **`contains.py`'s definition had been deleted** from the plan while round 3's replacement was applied, leaving two references to a script the plan no longer defined. Restored.
- **The coverage comparison could not pass on a correct split.** Blank lines adjacent to markers are structural glue the split legitimately rearranges, so counting them failed on faithful output. Coverage now compares **non-blank** lines — and that is sound rather than a weakening, because a blank line *inside* a moved block is already verified byte-exactly by fidelity's contiguous-substring check. Round 2 had asked for blanks to be included; that was right for a design where fidelity did not yet exist for every file, and wrong once it did.

It also corrected the mutation claims, which had the isolation backwards: deleting a *trailing* line leaves a block contiguous and proves nothing, and appending to the router extends its last block so fidelity fails too. Measured behaviour is now in Step 6b.

### Round 4 — eight more, all accepted, and one of them about the evidence itself

- **`contains.py` was syntactically invalid** (1). Restoring it in round 3 put a real newline inside `strip("...")`. The plan shipped a script that could not run.
- **Coverage still compared blank lines** (2, 7) despite the round-3 record saying otherwise. The round-3 rewrite of `reconstruct.sh` had silently reverted an earlier fix — a lost edit, not a disagreement — and the contract comment still promised "every line".
- **The marker protocol contradicted itself** (3, 4, 5). The implementation treated `<!-- moved -->` as a boundary while the instructions still called for a paired `<!-- /moved -->`, which would itself have become retained content and failed both checks; and the plan claimed `blocks.py` validated a pairing it does not track and does not need. One boundary marker, no closing form, and the validation claim now says exactly what is validated.
- **Router gaps were unspecified** (6). Trimming rows out of the router's `Common mistakes` and `Red flags` leaves the retained rows non-contiguous, so the router's fidelity fails without boundaries at each omission. The rule is now stated mechanically: a boundary wherever two consecutive retained lines were not consecutive in the original.
- **The synthetic run had not been performed from the current text** (8). Correct, and the sharpest finding of the four rounds. The run happened, then the plan was edited — including the edit that broke `contains.py` — so the evidence described a version that no longer existed.

**Re-run from the exact current text**, with the helpers extracted from these fenced blocks and `contains.py` invoked as a subprocess exactly as `reconstruct.sh` invokes it:

```
blocks.py    2360 bytes
  sha256 = fc3c5f29f44bab34926c95ef6c154a598ad3f44936cf8c17e4c33383cf227c2b
contains.py   281 bytes
  sha256 = d71e05c249004d486c499d418b6b65f25ac7d0f0b0d30a0744af73a7e6309195

CLEAN  fidelity_failures=[]  coverage_ok=True
MUT-b  fidelity_failures=1   coverage_ok=False   (delete a middle line: both claims fail)
MUT-c  fidelity_failures=0   coverage_ok=False   (duplicate a block: coverage only)
MARK   unclosed_addition rc=3  |  no_NEXT rc=3
RESULT PASS
```

Anyone re-deriving this: extract the two fenced `python` blocks verbatim, hash them, and the digests above must match. If they do not, the plan has been edited since and the run needs repeating — which is the whole point of recording them.

### Round 5 — six more, all accepted

- **Four byte-budget checks were still bare `wc -c`** (1), in Tasks 4 through 7, so an oversized file could be committed past a budget the plan claims to enforce. All four now call `budgets.sh`.
- **`xrefs.sh` was excluding the wrong directories** (2). `--exclude-dir` matches a *basename*, so `--exclude-dir=steps` silently dropped `skills/session-build/steps` — one of the known external reference sources, removed from a sweep whose entire job is to find them. Now excluded by path, and only `skills/session-end/steps`.
- **Task 2's ledger entry described a mutation that no longer exists** (3), still claiming an original line appended to the router when mutation C had become a duplicated block.
- **The coverage success message still said "every original line"** (4) while the implementation deliberately compares non-blank lines.
- **"exactly three such gaps" counted categories as instances** (5). An executor could have inserted three boundaries where a single trimmed table needs several. It now reads three *kinds*, with the adjacency rule as the specification.
- **The digests were 16 characters and labelled `sha256`** (6). Recorded in full.

Round 5 also returned the first positive finding of the review: the extracted hashes match the current fenced blocks, and the boundary/addition model *"is internally capable of passing and failing as intended."*

### Round 6 — four more, two of them self-inflicted

- **Task 1's ledger command was corrupted and Task 2's was stale** (1, 2). A substring extraction in the round-5 edit grabbed only `--type TASK --text "` — the first quote it found was the opening one — and so replaced the *first* matching command in the file, which was Task 1's. The wrong entry was overwritten and the intended one left untouched. Both restored, and it is a fair illustration of why this plan makes every check exit non-zero: a silent partial edit is the failure mode, and only a reader caught it.
- **The record claimed a Round 5 section that did not exist** (3) — this one.
- **`xargs -0` runs `grep` once with no filenames when its input is empty** (4), so `xrefs.sh` could fail for the wrong reason. `-r`.

### Round 7 — four more, and the same class a fourth time

Every one was a check that printed instead of failing, in a plan whose opening section is about checks that cannot fail.

- **`git status --porcelain` exits 0 even when it prints changes** (1, 2). Task 2's restoration check ran `git status ... && reconstruct.sh`, so the checker would have run over a tree still carrying a mutation; Task 10's clean-worktree gate could have pushed with uncommitted artifacts. Both are now `test -z "$(...)"`.
- **The branch checks only printed the branch name** (3), so nothing enforced the rule that this run never commits on the default branch. All three are now `test "$(git branch --show-current)" = ...`.
- **`grep -n 'READY'` cannot detect zero or two** (4), which was the entire purpose of a step whose text said "verify before adding it twice".

That this class survived six rounds of being the review's central theme is the most useful thing the argument produced. The lesson is not "be careful"; it is that a check reads as a check because of what it *looks* like, and only running it, or having someone hostile read it, tells you whether it can fail.

### Round 8 — two, and the loop converging

- **Nine commits, two branch assertions** (1). Round 7 fixed the three checks that existed; it did not ask whether every commit had one. An `onbranch` helper now guards all nine, so the check is not the one an executor skips.
- **The mutation tests could leave the tree contaminated** (2). Each deliberately exits non-zero and left restoration to a separate manual command; an executor interrupted between the two leaves a moved or edited file behind. They are now one script with a `trap` that restores on every exit path, including an interrupt.

### Round 9 — three, and the round-8 fix was itself wrong

- **The `onbranch` helper could never have worked** (2). The plan states two lines above its definition that every Bash call is a fresh process, so a function defined in the globals block is gone by the next command. Round 8's fix was the right requirement expressed in the wrong mechanism. The guard is now **inlined** at every commit site.
- **Task 1's guard and commit were separate invocations** (1), so the branch could change between them. All nine are now one invocation: guard `&&` add `&&` commit.
- **`trap restore EXIT INT TERM` restores on a signal but does not stop** (3), so bash resumes and applies the next mutation to a just-restored tree. `EXIT` cleans up; `INT` and `TERM` restore and exit 130/143.

**Nothing was rejected across nine rounds: sixty-nine findings, sixty-nine accepted.** Worth stating plainly rather than treating as a good score. Each round found a class the previous one did not — checks that could not fail, replacements wrong in their own right, a file exempted from its own contract, evidence for the fix being stale, budgets that printed instead of failing, and finally damage introduced by the fixing itself. The executed run then found two defects the reviewer structurally could not see, because it reads the document and cannot run it.

## Self-Review

**1. Spec coverage.** Every Decision 3 subsection maps to a task: 3.1→T3, 3.2→T4, 3.3→T5 and T7, 3.4→T4, 3.5→T6, 3.6→T6, 3.7→T6, 3.8→T6, 3.9→T7, 3.10→T5, 3.11→T2 and T3, 3.12→T6, 3.13→T6. Decisions 1→T2, 2→T8, 4→T9. *What must survive, verbatim*→T1 and T2. Implementation phasing→T1/T2/T3-9. Verification→T10.

**2. The spec says "twenty-one assertions" and this plan writes fifty.** The spec's number was an estimate; enumerating Decision 3 by subsection yields more, because several sections carry multiple independently-assertable claims, and round 1 of codex-review added more still by rejecting the loose ones. **Fifty is the real count and the plan is the authority.** Flagged rather than silently reconciled.

**3. Placeholder scan.** Two steps deliberately describe content rather than quoting it in full — Task 8 Step 2 (`lane-fork-orchestrator.md`) and Task 9 Step 5 (`cadeia-session.md`). Both name every element that must appear, and both are covered by assertions that fail until the element exists. Every other step carries the literal text or command.

**4. Type consistency.** `--expect` takes a **fixed string** and is checked with `grep -qF` in `sh` and `Select-String -SimpleMatch` in PowerShell — identical semantics on both platforms, which is the whole reason it is not a regex. `assert-findings.sh`'s `want` helper uses `grep -qF` for the same reason. `UNDECIDED`/75 is used identically in `gate.sh`, `gate.ps1`, `step-01-verify.md` and both fork contracts. `PENDINGS-RULING <heading> <lane> <evidence>` has the same shape in `ledger.py`, `lane-fork-orchestrator.md` and `references/fork-contract.md`. `GO <slug> verify <branch>` and `RELEASE verify <branch>` always carry the branch as the named resource.

**5. One gap, named rather than hidden.** `verify/reconstruct.sh` is only meaningful at the Task 2 commit; after Task 4 it must fail by design. Task 10 Step 2 says so explicitly rather than leaving a check that a later reader would think is broken.

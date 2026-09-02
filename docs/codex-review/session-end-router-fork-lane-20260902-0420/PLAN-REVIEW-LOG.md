# Plan Review Log: session-end router + fork lane + content rewrite
Started 2026-09-02T07:20Z. MAX_ROUNDS=until-approved (uncapped).

## Round 1 — Codex

1. Task 2’s reconstruction cannot pass as written: every step adds a new `# Step <N>` heading, but `strip()` removes only the invariant line, `## NEXT`, and marked router additions. Fix: mark and strip the new file headings, or omit them.

2. The reconstruction check ignores blank lines and all ordering, so it cannot prove the stated “concatenates the pieces back together” or preserve Markdown structure; shuffled table rows and paragraph order pass. Fix: reconstruct in original order and use an ordered normalized diff, handling split tables explicitly.

3. The reconstruction “red” only proves missing-file detection, not that altered, duplicated, or dropped content fails. Fix: after achieving green, deliberately delete and duplicate an original line and require both mutations to fail.

4. Task 10 does not rerun reconstruction against Task 2: it extracts only Task 2’s router, leaves the checker reading current step files, and merely echoes that the old result was recorded. Fix: export the complete Task 2 `skills/session-end` tree to a temporary directory and run its checker against its snapshot.

5. Task 10 contains the literal placeholder `<task-2-sha>`; in Bash, `<` is parsed as redirection, so the command cannot run. Fix: capture the commit SHA during Task 2 or resolve it deterministically with `git log --grep`.

6. Commands such as `bash ...; echo "exit=$?"` always leave the compound command with exit 0, so the advertised verification cannot stop subsequent work. Fix: use `bash ...; rc=$?; echo "exit=$rc"; exit "$rc"` or run the check under `set -e`.

7. Task 10’s shell/JS loops return only the last iteration’s status; an earlier failure followed by a pass makes the loop green. Fix: accumulate a failure flag or exit immediately on the first failed gate.

8. `expect-flag.sh` explicitly permits the real-red test to `SKIP`, so the test suite can pass without verifying one of `--expect`’s core claims. Fix: invoke the case with `--shell` and make any skip a failure.

9. `expect-flag.sh` tests only `gate.sh`; `gate.ps1` receives merely a parse check, so its matching, exit-75, real-red, and no-flag behavior are unverified. Fix: add equivalent behavioral tests executed through Windows PowerShell 5.1, the stated target runtime.

10. The plan exposes one `--expect <ERE>` interface but uses POSIX ERE in Bash and .NET regex in PowerShell; these regex languages are not equivalent. Fix: specify and validate a portable subset, or make `--expect` a literal fixed-string match in both scripts.

11. Task 3’s pattern example is not a reliable runner-completion contract: `Tests:? +[0-9]+ (passed|failed)` can match partial or incidental output and does not require a complete summary line. Fix: anchor a runner-specific full-line pattern and document one pattern per configured gate.

12. The content assertions mostly prove that a word occurs, not that the rule is correct; for example, `D2-generated` will already match existing Step 7 generated-file prose, so the required first-fail phase cannot occur. Fix: assert distinctive full clauses or structural table rows and verify each new assertion actually fails before editing.

13. Several other assertions can pass on unrelated or contradictory prose—e.g. `fetch`, `fork`, `agentId`, `generated`, and `UNDECIDED`—while the intended interface remains absent. Fix: scope patterns to headings/rows and assert the complete command or vocabulary shape.

14. Task 1 calls the copies “byte-exact” but verifies only after deleting every carriage return; that permits byte differences and even removal of meaningful embedded CR bytes. Fix: use `cmp` for byte identity and separately normalize only when reviewing textual diffs.

15. The plan assumes `$TMPDIR` is defined, but Git Bash does not guarantee it; with `set -u` or direct expansion, snapshot and probe commands can fail before testing anything. Fix: define `TMPBASE="${TMPDIR:-/tmp}"` once and use it consistently.

16. Task 8 declares that it consumes `PENDINGS-RULING` from Task 9, creating a commit with a documented protocol the ledger rejects until a later commit. Fix: implement the ledger vocabulary and fork initialization before adding the fork lane.

17. The cross-reference check prints `ORPHAN` for all eleven numbers and relies on a human to compare that output with a separate list; it has no failing condition. Fix: compute referenced numbers and exit nonzero for any number lacking a matching heading.

18. Byte-budget checks only print sizes and cannot fail when limits are exceeded. Fix: add an `awk` or shell loop that exits nonzero for `SKILL.md > 12288` or any step file `> 7168`.

19. Pairwise identity checking prints `DRIFT` but the loop can still exit 0 if the final comparison succeeds. Fix: accumulate drift and exit nonzero, or use `cmp` commands chained with explicit failure handling.

20. Task 9’s proof checks only Python parsing, not ledger behavior beyond one happy path; it does not verify that fork init refuses overwrite, creates the correct file exclusively, or that `PENDINGS-RULING` and `CLOSED` append successfully. Fix: add a temporary behavioral test covering both new vocabulary entries and the init safety invariants.

VERDICT: REVISE
### Claude's response — round 1

All twenty findings accepted, none rejected. Root cause shared by twelve of them:
most of the plan's verification was structurally incapable of failing — the exact
defect the skill under rewrite exists to prevent.

Applied:
- New "Every check in this plan must be able to fail" section + verify/lib.sh with
  ok/bad/finish. Every check script now exits non-zero on failure.
- Stripped `; echo "exit=$?"` from 9 command steps (findings 6). Expected results are
  now stated as exit codes.
- Loops accumulate (7, 19): Task 1 copy check, gate identity, all-gates.sh.
- budgets.sh and xrefs.sh created — the first versions only printed (17, 18).
  xrefs.sh guards against a vacuous pass when its paths are wrong.
- reconstruct.sh redesigned (1, 2, 3): FIDELITY (each body is a verbatim contiguous
  substring of the original) + COVERAGE (line multiset WITH blank lines). body()
  excludes the H1 and recap at extraction rather than stripping after, which was
  finding 1. Prove-red is now three mutations: missing file, deleted line,
  duplicated line.
- Task 10 exports the whole Task 2 tree with git archive and runs that commit's own
  checker against it (4). `<task-2-sha>` replaced with `git log --grep` (5) — as
  written, bash would have parsed `<` as a redirection.
- --expect is a FIXED STRING in both shells (10, 11): grep -qF / Select-String
  -SimpleMatch. One flag documented as "a regex" meant two different languages.
- expect-flag.sh real-red case uses --shell and can no longer SKIP (8).
  expect-flag.ps1 added: four behavioural cases on the target runtime (9).
- All assertions rewritten as distinctive fixed-string clauses (12, 13). The helper
  uses grep -qF — markdown escaped into an ERE is finding 10 in another costume.
- Task 1 separates byte identity (cmp) from textual identity (normalised diff) and
  no longer calls the second "byte-exact" (14).
- TMPBASE="${TMPDIR:-/tmp}" throughout (15).
- Tasks 8 and 9 swapped (16): the fork lane consumed PENDINGS-RULING from the ledger
  task, so it would have shipped a protocol ledger.py rejects.
- ledger-probe.sh added (20): init --fork accepted, fork file created, ledger.md NOT
  created, re-init refused, all three vocabulary entries append, unknown type
  refused, hand-written CODEX APPROVED still refused.

Tightened beyond the review, same reasoning: all-gates.sh treats UNDECIDED as a
failure explicitly, so the harness verifying this change cannot read its own new
state as a pass.

Assertion count: 21 (spec estimate) -> 43 (enumeration) -> 50 (after tightening).

## Round 2 — Codex

1. `reconstruct.sh` still cannot pass: it copies the router directly into `all_n` and never removes `<!-- split-addition -->...<!-- /split-addition -->` blocks. Fix: strip marked router additions before appending `SKILL.md`.

2. Fidelity assumes each step body is one contiguous substring of the original, but step-specific `Common mistakes` and `Red flags` rows are moved from earlier sections into step files, making those bodies non-contiguous. Fix: verify explicitly marked source fragments independently, or preserve those tables wholly in the router.

3. The duplicate-line mutation `sed -i '4p'` will likely duplicate the blank line after the invariant recap, changing the extracted body and therefore failing fidelity as well as coverage; it does not demonstrate the claimed “coverage only” failure. Fix: duplicate an entire already-valid body outside its owning step body, then require fidelity to pass and coverage to fail.

4. Task 2 Step 3 is ordered before the split exists even though it says to run after Step 5. An executor following checkbox order cannot perform it. Fix: move the mutation tests after the first clean reconstruction pass.

5. `$TMPBASE` is defined only inside scripts that source `lib.sh`, not in the plan’s global shell variables. Later standalone commands expand it without initializing it, including `rm -rf "$TMPBASE/t2"`, which can target `/t2`. Fix: define and validate `TMPBASE="${TMPDIR:-/tmp}"` globally before any use.

6. Task 10 depends on `$TMPBASE/session-end-presplit.md`, an untracked temporary snapshot that may disappear between tasks or sessions; contrary to the plan’s claim, not everything comes from the Task 2 commit. Fix: recreate the original with `git show "$T2^:skills/session-end/SKILL.md"` during Task 10.

7. Task 3’s commit command omits `skills/session-end/verify/expect-flag.ps1`. It remains untracked, Task 10 depends on it, and the final clean-status check fails. Fix: add `expect-flag.ps1` to Task 3’s `git add`.

8. Task 1’s “confirm exactly which files differ” loop still only prints differences and always exits successfully; it neither rejects extra files nor detects a missing expected difference. Fix: write actual and expected lists to temporary files and `diff` them.

9. Task 9 still uses `wc -c` as a non-failing budget check, despite the new `budgets.sh`; an oversized lane can be committed. Fix: replace that command with `bash skills/session-end/verify/budgets.sh`.

10. `all-gates.sh` uses `for f in $(find ...)`, which splits paths on whitespace under Windows Git Bash. Fix: use `find ... -print0 | while IFS= read -r -d '' f`, while preserving failure state outside the subshell.

11. The PowerShell behavioral test is committed only after being run in the proposed order: Step 6b runs the newly created untracked script, but the stated commit excludes it. Beyond the omission, the session-end `gate.ps1` copy is never behaviorally tested independently. Fix: test both PowerShell copies and commit the test script with them.

12. The self-review still says `--expect` takes an ERE and uses `grep -qE`/`Select-String -Pattern`, directly contradicting the revised fixed-string design. Fix: update the self-review to `grep -qF` and `Select-String -SimpleMatch`.

13. Task 3 Step 4 still says “four PASS lines (or three plus one SKIP)” even though the revised test has no skip path. Fix: require exactly four passes and remove the stale alternative.

14. `ledger-probe.sh` treats any nonzero re-init result as proof of safe refusal; a syntax error, missing interpreter, or unrelated crash passes that assertion. Fix: capture stderr/status and require exit 2 plus the specific “refusing to re-init” message.

15. `xrefs.sh` verifies only references in four hard-coded files despite the global claim that fourteen references live outside `SKILL.md`; references elsewhere can be orphaned unnoticed. Fix: derive references repo-wide with explicit exclusions, or assert that the discovered reference count/source list matches the known inventory.

VERDICT: REVISE
### Claude's response — round 2

All fifteen accepted, none rejected. The plan's 'Rounds 1 and 2' section records each. Headline: reconstruct.sh STILL could not have passed (router split-addition blocks never stripped; fidelity assumed contiguous bodies while the plan itself moves table rows in from two other sections). Fixed with <!-- moved --> fragment markers and per-block containment. TMPBASE now defined and validated globally after round 2 showed rm -rf "$TMPBASE/t2" could expand to rm -rf /t2. Task 10 now rebuilds the pre-split original with git show "$T2^:..." instead of an untracked snapshot.

## Round 3 — Codex

1. `reconstruct.sh` still cannot pass with the prescribed repeated table headers. The plan says headers above `<!-- moved -->` are “ordinary new text,” but the checker treats them as part of the preceding original block and includes them in coverage, causing both fidelity and duplication failures. Fix: wrap repeated headers in a separately stripped addition marker and teach the body parser to exclude it.

2. The AWK block splitter does not validate marker balance or nesting. A missing closing `<!-- /moved -->` at the end of a file can still pass fidelity and coverage. Fix: track `inside`, reject nested opens, unmatched closes, and nonzero `inside` at EOF.

3. Fidelity still does not protect the router’s retained original text. Router lines are checked only as a sorted multiset, so its sections, table rows, or paragraphs can be arbitrarily reordered while reconstruction passes—the original round-1 defect remains for the router. Fix: divide retained router content into marked source blocks and run each through `contains.py` as well as coverage.

4. The plan’s shell variables are assigned but not exported despite saying every step assumes they are exported. Separate Git Bash invocations will not inherit them, and standalone `$TMPBASE` uses remain unsafe after a context break. Fix: use `export WT SKILL HOME_SE LEDGER SLUG TMPBASE` and repeat the initialization in each independent execution context.

5. The coverage marker removal uses GNU-BRE-specific `\?` in `grep -v '^<!-- /\?moved -->$'`. It works with typical GNU grep but is needlessly fragile for a script described as Bash-portable. Fix: use two fixed-string exclusions or `grep -vE '^<!-- (/?moved) -->$'`.

6. The missing-file mutation does not specifically prove file enumeration: because the glob silently omits one missing file, only aggregate coverage catches it. A compensating duplicate elsewhere could hide the missing file. Fix: enumerate the exact eight expected filenames and fail immediately when any is absent or any unexpected `step-*.md` exists.

7. Task 2’s ledger text remains stale: it claims the checker first failed with “exit 2, missing files,” but the revised mutation suite runs after the split and `finish` returns 1. Fix: update the ledger entry to describe the three current mutations and their actual exit status.

VERDICT: REVISE
### Claude's response — round 3

All seven accepted. Headline: finding 3 - the router's retained text was only multiset-checked, so the round-1 defect survived in the one file nobody checked. Router now goes through the same block model. Markers unified: split-addition = anything written (including repeated table headers, finding 1), moved = block boundary. awk replaced by blocks.py, which validates nesting/balance/EOF (finding 2). Step filenames enumerated (6). Globals exported (4). GNU \? gone (5). Task 2 ledger text corrected (7).

THEN THE MODEL WAS EXECUTED against a synthetic split, which found two things no round did: contains.py's definition had been deleted from the plan during the round-3 edit, and the coverage comparison could not pass on a correct split because blank lines adjacent to markers are glue the split legitimately moves. Coverage now compares non-blank lines, which is sound because fidelity verifies blanks inside blocks byte-exactly. The mutation claims were also backwards and are now measured: delete-middle-line -> fidelity+coverage; duplicate-block -> coverage only.

## Round 4 — Codex

1. The plan’s `contains.py` is syntactically invalid: `.strip("\n")` has been split across two physical lines inside the quoted code block. Fix: restore it as `read().strip("\n")` on one line.

2. `reconstruct.sh` still compares blank lines despite the new explanation claiming otherwise: it runs `sort "$W/orig"` and `sort "$W/all"` directly, and its comments still say blanks are included. Fix: filter blank lines from both streams before sorting and update the contract text consistently.

3. The marker protocol remains contradictory. The implementation recognizes `<!-- moved -->` only as a boundary, while the split instructions still require paired `<!-- moved -->` / `<!-- /moved -->`; the closing marker becomes retained content and makes fidelity and coverage fail. Fix: choose one protocol—prefer a single boundary marker—and remove every closing-marker instruction/reference.

4. The plan claims `blocks.py` rejects unmatched or unclosed moved regions, but it keeps no moved-marker state and cannot perform either check. Fix: either remove that claim for boundary-only markers or implement genuinely paired moved regions.

5. The repeated-header instruction is still stale: it says the table header is “ordinary new text,” although the round record says headers now use `split-addition`. Ordinary repeated headers fail both fidelity and coverage. Fix: explicitly require the whole repeated header inside `<!-- split-addition -->` markers.

6. Router gaps are not specified. Removing step-specific rows from the router’s `Common mistakes` and `Red flags` tables leaves retained rows that were non-contiguous in the original; router fidelity fails unless each jump is marked. Fix: require `<!-- moved -->` boundaries in the router wherever omitted original rows create a source discontinuity.

7. The reconstruction contract still says coverage accounts for “every line,” while the intended implementation deliberately ignores blank lines. Fix: state that coverage is an exact non-blank-line multiset and fidelity preserves blank lines internal to retained blocks.

8. The advertised syntax checks would catch the broken `contains.py`, but they occur only during implementation; the plan currently contains code that cannot be created and pass as written. The claimed synthetic execution therefore was not performed from the exact current plan text. Fix: re-extract and rerun the precise fenced definitions after correcting them, then record their hashes or exact revision.

VERDICT: REVISE
### Claude's response — round 4

All eight accepted. contains.py was syntactically invalid (a real newline inside strip) - the plan shipped a script that could not run. Coverage still compared blank lines because the round-3 rewrite of reconstruct.sh silently reverted an earlier fix. Marker protocol unified on a single boundary with no closing form, and the false pairing-validation claim removed. Router gaps now specified mechanically. Finding 8 was correct and is the sharpest of the four rounds: the synthetic run predated the edits, so the evidence described a version that no longer existed. Re-extracted from the current text and re-ran, with contains.py invoked as a subprocess exactly as reconstruct.sh does; digests recorded in the plan (blocks.py fc3c5f29f44bab34, contains.py d71e05c249004d48) so the claim is re-derivable.

## Round 5 — Codex

1. Four byte-budget “checks” still cannot fail: Tasks 4–7 use bare `wc -c` commands. Oversized files can be committed despite the global rule. Fix: invoke `verify/budgets.sh` before every affected commit.

2. `xrefs.sh` uses `--exclude-dir=steps`, excluding every `steps/` directory—including `skills/session-build/steps/step-06-closeout.md`, one of the explicitly known external-reference sources. Fix: exclude only `skills/session-end/steps`, not all directories named `steps`.

3. Task 2’s ledger entry is stale again: mutation C now duplicates a step block, but the ledger claims an original line was appended to the router. Fix: describe the actual `<!-- moved -->` duplicate-block mutation.

4. Reconstruction’s success message still says “every original line accounted for” although coverage deliberately compares only non-blank lines. Fix: say “every original non-blank line.”

5. The “exactly three such gaps” statement actually lists three categories of gaps, not three concrete gaps; trimmed tables can require several boundaries. An executor may insert only three markers. Fix: say “three kinds of gap” and retain the mechanical adjacency rule.

6. The recorded digests are only 16 hexadecimal characters while labeled `sha256`. They match the current scripts’ SHA-256 prefixes, but they are not full digests and permit far more ambiguity than necessary. Fix: record the complete 64-character hashes.

The reconstructed Python hashes otherwise match the current fenced blocks, and the revised boundary/addition model is internally capable of passing and failing as intended.

VERDICT: REVISE
### Claude's response — round 5

All six accepted. Four bare wc -c budget checks in Tasks 4-7 replaced with budgets.sh. xrefs.sh: --exclude-dir matches a BASENAME, so --exclude-dir=steps was silently excluding skills/session-build/steps, one of the known external reference sources - now excluded by path, and only skills/session-end/steps. Task 2 ledger text rewritten to describe the actual mutation C (duplicate a block as its own <!-- moved --> block, coverage-only). Coverage success message says NON-BLANK. 'exactly three such gaps' -> three KINDS of gap, with the adjacency rule as the specification. Digests recorded in full 64 hex characters. Codex also confirmed the extracted hashes match the current fenced blocks and that the boundary/addition model is internally capable of passing and failing as intended.

## Round 6 — Codex

1. Task 1’s ledger command is corrupted: Task 2’s ledger text was inserted before the original `1/10` text, producing one malformed combined argument and recording the wrong task. Fix: restore Task 1 to a single clean `1/10 baseline landed...` entry.

2. Task 2 still contains a second, stale ledger command claiming mutation C appended a line to the router. Fix: replace that duplicate with the revised moved-block description and keep only one Task 2 ledger entry.

3. The plan claims the round-5 findings are recorded, but the review record ends at Round 4. Fix: add the Round 5 section or remove the claim that it exists.

4. `xrefs.sh` can still fail incorrectly when its filtered file list is empty because GNU `xargs` invokes `grep` once with no filenames by default. Fix: use `xargs -0 -r` on Git Bash or materialize and explicitly validate the file list before the second grep.

The reconstruction implementation, marker model, full helper hashes, non-blank coverage, and budget enforcement are now internally sound.

VERDICT: REVISE
### Claude's response — round 6

All four accepted. Two were self-inflicted: a substring extraction in the round-5 edit grabbed only '--type TASK --text "' because the first quote it found was the opening one, so it overwrote Task 1's ledger command instead of Task 2's. Both restored. Round 5 and Round 6 record sections added - the plan had claimed a section that did not exist. xargs -0 -r so an empty file list does not invoke grep on stdin. Codex confirmed the reconstruction implementation, marker model, helper hashes, non-blank coverage and budget enforcement are now internally sound.

## Round 7 — Codex

1. Task 2’s restoration check still cannot fail on a dirty tree: `git status --porcelain ... && reconstruct.sh` proceeds because `git status` exits 0 even when it prints changes. Fix: capture the output and require it to be empty before reconstruction.

2. Task 10’s clean-worktree gate has the same defect: bare `git status --porcelain` always exits 0 on dirtiness, so the plan can push with uncommitted artifacts. Fix: use `test -z "$(git status --porcelain)"`.

3. The branch checks only print the current branch and therefore cannot enforce the forbidden-default-branch rule. Fix: use `test "$(git branch --show-current)" = refactor/session-end-router-fork-lane-20260902` before every commit and push.

4. Task 8’s `grep -n READY` only prints matches and cannot detect zero or duplicate definitions, despite its purpose being “verify before adding it twice.” Fix: assert exactly one intended `READY` vocabulary occurrence with a count test scoped to the declaration.

The two fenced Python hashes match their recorded full SHA-256 digests, and the reconstruction/xrefs/budget logic is otherwise coherent.

VERDICT: REVISE
### Claude's response — round 7

All four accepted, all the same class a fourth time: checks that print instead of failing. git status --porcelain exits 0 even when printing changes, so Task 2's restoration check would have run the checker over a mutated tree and Task 10 could have pushed dirty - both now test -z. All three branch checks now assert equality rather than printing. The READY check asserts a count of exactly one, with a note on why grep -c is safe there (compared with test) and banned in assert-findings.sh (exit status read directly, inverts on zero).

## Round 8 — Codex

1. The plan still has nine commits but only two pre-commit branch assertions. Tasks 3–9 commit without executing the mandatory branch check immediately beforehand. Fix: add the equality assertion before every `git commit`, or wrap commits in a helper that enforces it.

2. The mutation tests intentionally return nonzero before restoration, leaving restoration as a later manual command. An interrupted executor can leave a file moved or modified and contaminate subsequent checks. Fix: wrap each mutation in a function with a restoration `trap`, then assert the expected failure.

Everything else reviewed—including reconstruction, hashes, budgets, xrefs, READY counting, status gates, and exit propagation—is structurally sound.

VERDICT: REVISE
### Claude's response — round 8

Both accepted. An onbranch() helper now guards all nine commits - round 7 fixed the three branch checks that existed without asking whether every commit had one. The three mutations became verify/prove-red.sh, one script with a trap restoring on every exit path including INT/TERM, so an interrupted executor cannot leave the tree contaminated; each mutation now also asserts WHICH claim fired, so (c) failing on fidelity as well would be reported as the claims not being isolated.

## Round 9 — Codex

1. Task 1 still does not guard its commit: `onbranch` runs with `git add`, then `git commit` runs in a separate Bash call. The branch can change between them. Fix: combine `onbranch && git add ... && git commit ...` in one invocation, as Tasks 2–9 do.

2. `onbranch()` is only defined in the global example, while the plan explicitly says each Bash tool call is a fresh process. Commands invoking `onbranch` therefore fail unless the executor manually prepends the block. Fix: place the helper in a committed/sourceable script and explicitly source it at every commit site, or inline the equality test.

3. `trap restore EXIT INT TERM` restores on `INT`/`TERM` but does not terminate the script; Bash can continue and apply later mutations after restoration. Fix: use separate signal handlers that restore and exit nonzero, plus `trap restore EXIT`.

The mutation assertions themselves correctly distinguish enumeration, fidelity-plus-coverage, and coverage-only failures.

VERDICT: REVISE
### Claude's response — round 9

All three accepted, and finding 2 shows round 8's fix was itself wrong: an onbranch() helper defined in the globals block could never survive, because the plan states two lines above that every Bash call is a fresh process. The guard is now inlined at all nine commit sites. Task 1's guard, add and commit are one invocation like the other eight. The trap now separates EXIT cleanup from INT/TERM handlers that restore AND exit 130/143, so an interrupt cannot let the script resume and mutate a just-restored tree.

## Round 9 — Codex

No material issues remain. All nine commits inline the branch guard with add/commit, and `prove-red.sh` restores safely on normal exit, interruption, and termination while asserting the specific expected failure modes.

VERDICT: APPROVED

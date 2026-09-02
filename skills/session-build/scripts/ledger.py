#!/usr/bin/env python3
"""ledger.py - append-only run ledger for session-build.

Three prose rules in an earlier version of this skill exist only because the
ledger was hand-written markdown. This script makes all three unnecessary:

  1. "Say WHICH checkout, or the sweep silently reads nothing."
     Every command takes an absolute --dir. A relative path put fork files
     inside the worktrees, where the orchestrator's lock sweep read an empty
     directory and reported no pending locks - confidently, about the one
     deadlock this design produces on its own.

  2. "The sweep only works if the fork ledger has the format it greps for."
     Forks wrote prose; the sweep greps for '^LOCK '; it matched zero, and zero
     was indistinguishable from clean. This script owns the format, so prose
     cannot happen.

  3. "Record dated readings, not only decisions."
     Every entry is stamped. A reading with no timestamp is an instruction with
     an expiry date that does not say what it is.

Invariants, borrowed from a design that states them well:
  - Append-only. No edit, no delete subcommand, by design. History is never
    rewritten.
  - Blind write. Every command is atomic and context-free and echoes the new
    entry as one line, so the caller never re-reads the file mid-session.
  - Completion is an entry, not a status field.

Usage:
  ledger.py init   --dir <abs> --run-id <id> --specs "a,b,c"
  ledger.py append --dir <abs> [--fork <slug>] --type <TYPE> --text "..."
  ledger.py codex  --dir <abs> [--fork <slug>] --rundir <dir> --plan <path> --rounds <n>
  ledger.py sweep  --dir <abs>
  ledger.py show   --dir <abs> [--fork <slug>] [--type <TYPE>]

TYPE is one of the checkpoint or directive keywords. The set is deliberately
open at the tail - lock kinds especially are open-ended, and a run inventing a
new one is normal - but the leading keyword must be upper-case and known, or
the sweep loses its grip.
"""

import argparse
import hashlib
import os
import re
import sys
from datetime import datetime, timezone

CHECKPOINTS = {
    "READY", "PLAN", "CODEX", "SURFACES", "TASK", "LOCK", "RELEASE", "APPLIED",
    "DEPLOYED", "PUSHED", "BLOCKED", "WAITING", "PARKED", "DONE",
}
DIRECTIVES = {"GO", "HOLD", "COORDINATE", "MERGE"}
# PENDINGS-SOURCE: which entries of the project's pendings file a spec was built
# from, quoted by heading. Written at step-02, carried into handoff.md at step-06,
# and read by /session-end so it can close those entries BY NAME. Without it that
# skill can only grep its diff, which finds an entry naming a file it touched and
# misses one describing a behaviour it fixed - the observed failure being a user
# who starts a run from the pendings file and finds the same items still there
# after the close-out.
BOOKKEEPING = {
    "RULING", "READING", "ESCALATION", "RELAY", "PROFILE", "NOTE",
    "PENDINGS-SOURCE",
    # PENDINGS-RULING: one per pendings entry a session-end fork ruled against
    # its own diff - `PENDINGS-RULING <entry heading> <lane> <evidence>`, lane
    # being resolved / stale-cause / moved / untouched. The fork RULES; the
    # orchestrator performs the single write. Closing N branches in sequence
    # runs Step 4's Half A N times over one file, and each pass can reopen what
    # the last one closed.
    "PENDINGS-RULING",
    # CLOSED: an entry deleted because this run resolved it, named so the
    # close-out can report closures, which are otherwise invisible - a run
    # reported 13 opened and said nothing about 17 closed until asked.
    "CLOSED",
}
KNOWN = CHECKPOINTS | DIRECTIVES | BOOKKEEPING


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def target(args):
    if not os.path.isabs(args.dir):
        die(
            "--dir must be ABSOLUTE and point into the main checkout. "
            "A relative path puts fork files inside the worktrees, where the "
            "orchestrator's sweep cannot see them."
        )
    name = "ledger.md" if not getattr(args, "fork", None) else "fork-%s.md" % args.fork
    return os.path.join(args.dir, name)


def die(msg):
    sys.stderr.write("ledger.py: %s\n" % msg)
    raise SystemExit(2)


def atomic_append(path, line):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(line + "\n")
        fh.flush()
        os.fsync(fh.fileno())


def cmd_init(args):
    path = target(args)
    if os.path.exists(path):
        die("refusing to re-init an existing ledger: %s" % path)
    os.makedirs(args.dir, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# session-build - run %s\n" % args.run_id)
        fh.write("# specs: %s\n" % (args.specs or ""))
        fh.write("# every line below starts with a TYPE keyword; prose goes on a line beginning with two spaces\n")
    print("LEDGER INIT %s" % path)


def _sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def cmd_codex(args):
    """Record a codex-review approval as EVIDENCE, not as a claim.

    An agent that skipped the review can satisfy a prose rule by writing a line
    saying it did not, so this refuses the entry unless the artifacts exist and
    agree. Four checks, and the third is the one that matters most:

      1. <rundir> exists and holds PLAN-REVIEW-LOG.md;
      2. that log records at least <rounds> verdicts, last one APPROVED;
      3. <rundir>/PLAN.md and the canonical --plan file have the SAME digest -
         otherwise an unrelated earlier approved run authorises a plan nobody
         reviewed, and the copy-the-hardened-plan-back step goes unverified.
         Implementation reads ONLY the canonical path, so this is the check
         that ties the approval to the thing that will actually be built;
      4. the digest is written into the ledger, so it stays checkable later.

    Paths arrive as options, not inside the text, so a Windows path with spaces
    works and nobody computes a hash by hand.
    """
    rundir, plan = args.rundir, args.plan

    if not os.path.isdir(rundir):
        die("codex run dir does not exist: %s" % rundir)
    log = os.path.join(rundir, "PLAN-REVIEW-LOG.md")
    if not os.path.isfile(log):
        die("no PLAN-REVIEW-LOG.md in %s - a review that ran leaves its transcript" % rundir)
    body = open(log, encoding="utf-8", errors="replace").read()
    verdicts = re.findall(r"VERDICT:[ 	]*(APPROVED|REVISE)", body)
    if not verdicts:
        die("no VERDICT line in %s - that log is not a completed review" % log)
    if verdicts[-1] != "APPROVED":
        die("last verdict in %s is %s, not APPROVED" % (log, verdicts[-1]))
    if len(verdicts) < args.rounds:
        die("--rounds says %d but %s records only %d verdict(s)"
            % (args.rounds, log, len(verdicts)))

    reviewed = os.path.join(rundir, "PLAN.md")
    if not os.path.isfile(reviewed):
        die("no PLAN.md in %s - nothing proves what was reviewed" % rundir)
    if not os.path.isfile(plan):
        die("plan file does not exist: %s - implementation reads this path" % plan)

    sha_reviewed, sha_plan = _sha(reviewed), _sha(plan)
    if sha_reviewed != sha_plan:
        die("the REVIEWED plan and the CANONICAL plan differ. reviewed=%s %s ; canonical=%s %s  -- copy the hardened plan back over the canonical path before recording approval:  implementation reads only that path, so an approval recorded now would authorise  a plan nobody reviewed."
            % (reviewed, sha_reviewed, plan, sha_plan))

    args.type = "CODEX"
    args.text = ("APPROVED ROUNDS %d RUNDIR %s PLAN %s SHA %s"
                 % (args.rounds, rundir, plan, sha_plan))
    return cmd_append(args, _validated=True)

def cmd_append(args, _validated=False):
    kw = args.type.strip().upper()
    if kw == "CODEX" and args.text.strip().upper().startswith("APPROVED") and not _validated:
        die("record a codex approval with `ledger.py codex --rundir <dir> --plan <path> "
            "--rounds <n>`, which verifies the artifacts. A hand-written APPROVED line is an "
            "assertion, and this is the one entry that must be evidence.")
    if kw not in KNOWN:
        die(
            "unknown type %r. Known: %s. If a run needs a genuinely new kind, "
            "add it here rather than writing prose - the sweep greps these."
            % (kw, ", ".join(sorted(KNOWN)))
        )
    path = target(args)
    if not os.path.exists(path):
        die("no ledger at %s - run `ledger.py init` first" % path)
    line = "%s %s  # %s" % (kw, args.text.strip(), now())
    atomic_append(path, line)
    print(line)


def read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [l.rstrip("\n") for l in fh]


# Lock kinds are open-ended but must be SINGLE canonical tokens, or the parser
# cannot tell a multiword kind from a kind plus identifiers: a lock written with
# spaces in the kind reads as kind "external" holding "live", "service", "redis".
CANONICAL_KINDS = (
    "migration", "deploy", "verify", "file",
    "external-live-service", "local-stack",
)


def _kv(tokens, keyword):
    """(kind, [resources]) for a LOCK / RELEASE / GO line.

    Resources are named individually; a lock over three files is three units.
    That is what makes partial release and per-resource grants possible.
    """
    i = tokens.index(keyword)
    kind = tokens[i + 1] if len(tokens) > i + 1 else "?"
    rest = tokens[i + 2:]
    if "VERIFIED" in rest:
        rest = rest[:rest.index("VERIFIED")]
    return kind, [r for r in rest if r]


def _warn_kind(kind, seen):
    if kind not in CANONICAL_KINDS and kind not in seen:
        seen.add(kind)
        print("SWEEP WARNING non-canonical lock kind %r - use a single hyphenated token "
              "(known: %s), or a multiword kind parses as kind + identifiers"
              % (kind, ", ".join(CANONICAL_KINDS)))


def cmd_sweep(args):
    """Report locked resources with no matching release.

    The unit is a RESOURCE, not a lock line. `LOCK deploy funcA funcB` is two
    units. Three defects that model removes, each found by review:

      * positional counting (an unrelated APPLIED released the wrong lock);
      * kind-only release, so a `verify` or any open-ended kind could never be
        released - every kind is released by `RELEASE <kind> <resources>`;
      * all-or-nothing release and all-or-nothing grants, where one matching
        resource released or granted a whole multi-resource lock.

    A resource with no name is tracked under the sentinel "-", so an unnamed
    lock still has to be released explicitly.
    """
    if not os.path.isdir(args.dir):
        die("no such ledger directory: %s (absolute path into the MAIN checkout)" % args.dir)

    fork_files = sorted(
        f for f in os.listdir(args.dir)
        if f.startswith("fork-") and f.endswith(".md")
    )
    if not fork_files:
        print("SWEEP WARNING 0 fork ledger files in %s - if forks were dispatched, "
              "they were given the wrong path and this result means nothing" % args.dir)

    warned = set()

    # GO <spec-slug> <kind> <resources...>  - the ONE sanctioned grant format.
    granted = set()          # (fork, kind, resource)
    grant_count, malformed = 0, 0
    for line in read_lines(os.path.join(args.dir, "ledger.md")):
        toks = line.split("#")[0].split()
        if not toks or toks[0] != "GO":
            continue
        grant_count += 1
        if len(toks) < 3:
            malformed += 1
            continue
        # GO <spec-slug> <kind> <resources...> - the fork token sits between the
        # keyword and the kind, so this cannot go through _kv().
        fork = toks[1][len("fork-"):] if toks[1].startswith("fork-") else toks[1]
        kind = toks[2]
        res = [r for r in toks[3:] if r]
        if kind == "phase":
            continue                      # a non-lock go-ahead grants no resource
        _warn_kind(kind, warned)
        if not res:
            malformed += 1                # `GO <fork> <kind>` names nothing. That is NOT a
            continue                      # wildcard over that fork's locks of that kind.
        for r in res:
            granted.add((fork, kind, r))

    outstanding = []
    for fname in fork_files:
        slug = fname[len("fork-"):-len(".md")]
        held = {}            # (kind, resource) -> raw line that requested it
        for line in read_lines(os.path.join(args.dir, fname)):
            body = line.split("#")[0]
            toks = body.split()
            if not toks:
                continue

            # Only the FIRST token may declare a lock event. Matching the keyword
            # anywhere let arbitrary prose move locks: `NOTE waiting for LOCK deploy
            # funcA` created a phantom lock, and `NOTE observed RELEASE deploy funcA`
            # silently released a real one.
            if toks[0] == "LOCK":
                kind, res = _kv(toks, "LOCK")
                _warn_kind(kind, warned)
                for r in (res or ["-"]):
                    held[(kind, r)] = body.strip()
                continue

            if toks[0] == "RELEASE":
                kind, res = _kv(toks, "RELEASE")
                if not res:
                    print("SWEEP WARNING %s: 'RELEASE %s' names no resource and releases "
                          "nothing - a resource-less release is not a wildcard. Use "
                          "'RELEASE %s -' only for a lock that was itself unnamed."
                          % (slug, kind, kind))
                    continue
            elif toks[0] == "APPLIED":
                kind, res = "migration", toks[1:]
            elif toks[0] == "DEPLOYED":
                kind, res = _kv(["DEPLOYED_", "DEPLOYED"] + toks, "DEPLOYED")
                kind = "deploy"
            else:
                continue                  # PUSHED / DONE release nothing

            for r in res:
                held.pop((kind, r), None)

        for (kind, resource), raw in sorted(held.items()):
            state = ("GRANTED-NOT-RELEASED"
                     if (slug, kind, resource) in granted
                     else "UNGRANTED")
            outstanding.append((slug, kind, resource, state, raw))

    for slug, kind, resource, state, raw in outstanding:
        print("SWEEP OUTSTANDING %s %s %s [%s] %s" % (slug, kind, resource, state, raw))
    if malformed:
        print("SWEEP WARNING %d GO line(s) not in 'GO <spec-slug> <kind> <resource...>' form "
              "- a grant naming no resource grants nothing; it is not a wildcard" % malformed)
    print("SWEEP SUMMARY forks=%d grants=%d outstanding=%d ungranted=%d"
          % (len(fork_files), grant_count, len(outstanding),
             sum(1 for o in outstanding if o[3] == "UNGRANTED")))
    return 1 if outstanding else 0


def cmd_show(args):
    path = target(args)
    want = args.type.strip().upper() if args.type else None
    for line in read_lines(path):
        if line.startswith("#"):
            continue
        if want and not line.split("#")[0].strip().startswith(want):
            continue
        print(line)
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp, fork=True):
        sp.add_argument("--dir", required=True, help="ABSOLUTE ledger dir in the MAIN checkout")
        if fork:
            sp.add_argument("--fork", help="spec slug; omit for the orchestrator ledger")

    sp = sub.add_parser("init", help="create the orchestrator ledger, or a fork's")
    # Until 2026-09-02 this was common(sp, fork=False), so --fork was not an
    # accepted argument for init and target() could never resolve to
    # fork-<slug>.md from here. cmd_append refuses when the file is absent and
    # tells you to run init, so **a fork could not create its own ledger** by
    # any route through this script. Every fork either hand-wrote the header or
    # put its checkpoints somewhere the sweep does not read - which is the exact
    # failure the sweep's format rule exists to prevent. Found by a fork at its
    # own bootstrap, and it had to hand-write the header to report the finding.
    common(sp)
    sp.add_argument("--run-id", required=True)
    sp.add_argument("--specs", default="")
    sp.set_defaults(func=cmd_init)

    sp = sub.add_parser("append", help="append one entry")
    common(sp)
    sp.add_argument("--type", required=True)
    sp.add_argument("--text", required=True)
    sp.set_defaults(func=cmd_append)

    sp = sub.add_parser("codex", help="record a VERIFIED codex-review approval")
    common(sp)
    sp.add_argument("--rundir", required=True, help="the codex-review run directory")
    sp.add_argument("--plan", required=True, help="canonical plan path implementation reads")
    sp.add_argument("--rounds", required=True, type=int)
    sp.set_defaults(func=cmd_codex)

    sp = sub.add_parser("sweep", help="report LOCK requests with no release")
    sp.add_argument("--dir", required=True)
    sp.set_defaults(func=cmd_sweep)

    sp = sub.add_parser("show", help="print entries")
    common(sp)
    sp.add_argument("--type")
    sp.set_defaults(func=cmd_show)

    args = p.parse_args()
    raise SystemExit(args.func(args) or 0)


if __name__ == "__main__":
    main()

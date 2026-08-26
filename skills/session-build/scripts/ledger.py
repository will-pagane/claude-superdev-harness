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
  ledger.py sweep  --dir <abs>
  ledger.py show   --dir <abs> [--fork <slug>] [--type <TYPE>]

TYPE is one of the checkpoint or directive keywords. The set is deliberately
open at the tail - lock kinds especially are open-ended, and a run inventing a
new one is normal - but the leading keyword must be upper-case and known, or
the sweep loses its grip.
"""

import argparse
import os
import sys
from datetime import datetime, timezone

CHECKPOINTS = {
    "READY", "PLAN", "CODEX", "SURFACES", "TASK", "LOCK", "APPLIED",
    "DEPLOYED", "PUSHED", "BLOCKED", "WAITING", "PARKED", "DONE",
}
DIRECTIVES = {"GO", "HOLD", "COORDINATE", "MERGE"}
BOOKKEEPING = {"RULING", "READING", "ESCALATION", "RELAY", "PROFILE", "NOTE"}
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


def cmd_append(args):
    kw = args.type.strip().upper()
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


def cmd_sweep(args):
    """Find LOCK requests with no matching grant. Defensive on purpose: it does
    not require the keyword to be anchored, because a sweep whose empty result
    cannot be distinguished from a healthy one is the false green this whole
    design most needs not to have."""
    if not os.path.isdir(args.dir):
        die("no such ledger directory: %s (absolute path into the MAIN checkout)" % args.dir)

    fork_files = sorted(
        f for f in os.listdir(args.dir)
        if f.startswith("fork-") and f.endswith(".md")
    )
    if not fork_files:
        print("SWEEP WARNING 0 fork ledger files in %s - if forks were dispatched, "
              "they were given the wrong path and this result means nothing" % args.dir)

    grants = 0
    for line in read_lines(os.path.join(args.dir, "ledger.md")):
        if "GO" in line.split("#")[0].split():
            grants += 1

    outstanding = []
    for fname in fork_files:
        slug = fname[len("fork-"):-len(".md")]
        locks, releases = [], 0
        for line in read_lines(os.path.join(args.dir, fname)):
            body = line.split("#")[0]
            toks = body.split()
            if not toks:
                continue
            if "LOCK" in toks:
                locks.append(body.strip())
            if toks[0] in ("APPLIED", "DEPLOYED", "PUSHED", "DONE"):
                releases += 1
        if len(locks) > releases:
            for l in locks[releases:]:
                outstanding.append((slug, l))

    for slug, l in outstanding:
        print("SWEEP OUTSTANDING %s %s" % (slug, l))
    print("SWEEP SUMMARY forks=%d grants_recorded=%d outstanding=%d"
          % (len(fork_files), grants, len(outstanding)))
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

    sp = sub.add_parser("init", help="create the orchestrator ledger")
    common(sp, fork=False)
    sp.add_argument("--run-id", required=True)
    sp.add_argument("--specs", default="")
    sp.set_defaults(func=cmd_init)

    sp = sub.add_parser("append", help="append one entry")
    common(sp)
    sp.add_argument("--type", required=True)
    sp.add_argument("--text", required=True)
    sp.set_defaults(func=cmd_append)

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

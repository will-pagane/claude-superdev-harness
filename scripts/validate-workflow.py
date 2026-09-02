#!/usr/bin/env python3
"""Validate a GitHub workflow structurally, not by substring.

Two things a `grep` cannot do and this can: reject a duplicate mapping key
(PyYAML's safe_load accepts them silently, last-one-wins), and assert that a
step lives inside a particular job's `steps` list rather than merely appearing
somewhere in the file - including inside a comment.
"""
import sys

import yaml


class NoDuplicatesLoader(yaml.SafeLoader):
    pass


def _no_duplicates(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.YAMLError(
                "duplicate key %r at line %d" % (key, key_node.start_mark.line + 1)
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


NoDuplicatesLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates
)


def runs_of(job):
    return [s.get("run", "") for s in job.get("steps", [])]


def main(path):
    with open(path, encoding="utf-8") as fh:
        doc = yaml.load(fh, Loader=NoDuplicatesLoader)

    jobs = doc["jobs"]
    problems = []

    if not any("check-drift.sh --repo-only" in r for r in runs_of(jobs.get("syntax-check", {}))):
        problems.append("repo-only step is not inside jobs.syntax-check.steps")

    if "drift-check-works" not in jobs:
        problems.append("job drift-check-works is missing")
    else:
        dw = runs_of(jobs["drift-check-works"])
        if not any("install.sh --skills --copy" in r for r in dw):
            problems.append("drift-check-works never installs")
        if not any(r.strip().endswith("check-drift.sh") for r in dw):
            problems.append("drift-check-works never runs comparison mode")

    if "symlink-probe-windows" not in jobs:
        problems.append("job symlink-probe-windows is missing")
    elif jobs["symlink-probe-windows"].get("runs-on") != "windows-latest":
        problems.append("symlink-probe-windows does not run on windows-latest")

    if problems:
        for p in problems:
            print("INVALID: %s" % p, file=sys.stderr)
        return 1
    print("%s: parses, no duplicate keys, all required steps structurally present" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ".github/workflows/lint.yml"))

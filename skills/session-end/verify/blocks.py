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

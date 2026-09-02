"""Exit 0 if the block is a verbatim contiguous substring of the original.

Usage: contains.py <original> <block>
"""
import io, sys

o = io.open(sys.argv[1], encoding="utf-8").read()
b = io.open(sys.argv[2], encoding="utf-8").read().strip("\n")
sys.exit(0 if b and b in o else 1)

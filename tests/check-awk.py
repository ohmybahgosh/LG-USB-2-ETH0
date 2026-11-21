#!/usr/bin/env python3
"""Checks every awk program in LG-USB-2-ETH0.sh for a name followed by a
space and "(", like  d = d (i > 3 ? " " : "") $i.  Newer awks read that as
joining two strings, but the older BusyBox awk on some TVs reads it as a call
to a function named d and prints "Call to undefined function", which broke
status --json and the TV app on a webOS 6 NANO85 (#57).  Put the parts in
their own statements instead.

Usage: python3 tests/check-awk.py [LG-USB-2-ETH0.sh]"""
import re, sys
src = open(sys.argv[1] if len(sys.argv) > 1 else 'LG-USB-2-ETH0.sh').read()
kw = set('if for while printf print return split gsub sub int substr length in match sprintf index tolower toupper getline close system exit delete else do and or not srand rand sqrt exp log sin cos atan2 next function'.split())
# awk programs: awk [opts] '...'
n = 0
for m in re.finditer(r"\bawk\b((?:\s+-[vF]\s*(?:\"[^\"]*\"|'[^']*'|\S+))*)\s+'((?:[^']|'\\''|'\"'\"')*)'", src):
    prog = m.group(2)
    start = src.count('\n', 0, m.start(2)) + 1
    # drop string literals and regexes
    clean = re.sub(r'"(?:[^"\\]|\\.)*"', '""', prog)
    clean = re.sub(r'(?<=[~(,!])\s*/(?:[^/\\\n]|\\.)+/', ' R', clean)
    clean = re.sub(r'^\s*/(?:[^/\\\n]|\\.)+/', 'R', clean, flags=re.M)
    for mm in re.finditer(r'\b([A-Za-z_][A-Za-z0-9_]*)\s+\(', clean):
        name = mm.group(1)
        if name in kw:
            continue
        line = start + clean.count('\n', 0, mm.start())
        n += 1
        print('%d: %s (  ...  %s' % (line, name, clean[max(0, mm.start() - 30):mm.end() + 30].replace('\n', ' ')))
print('awk: %d problem(s)' % n if n else 'awk: ok')
sys.exit(1 if n else 0)

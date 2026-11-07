#!/usr/bin/env python3
"""Check that a kernel image exports every symbol a module imports.

Usage: check-exports.py IMAGE|Module.symvers IMPORTS_FILE [EXTRA_EXPORTS]

IMAGE is the decompressed kernel (as kernel-info.py saves it).  A symbol
counts as exported when its name is in the image as a NUL-terminated
string, as in __ksymtab_strings.  Without the TV's own image, a
Module.symvers from a full build of LG's source with the TV's config lists
the exports instead.  IMPORTS_FILE has one symbol per line (`nm -u
module.ko`).  EXTRA_EXPORTS, one symbol per line, lists exports of our own
modules loaded first (like usbnet.ko where the kernel leaves it out).
Exits 1 and lists the missing ones if any aren't there.
"""
import sys


def main(image, imports, extra=None):
    names = [line.strip() for line in open(imports) if line.strip()]
    ours = set(line.strip() for line in open(extra) if line.strip()) if extra else set()
    names = [n for n in names if n not in ours]
    if image.endswith('Module.symvers'):
        have = set(line.split()[1] for line in open(image) if len(line.split()) > 1)
        missing = [n for n in names if n not in have]
    else:
        data = open(image, 'rb').read()
        missing = [n for n in names if b'\0' + n.encode() + b'\0' not in data]
    if missing:
        print('missing exports: ' + ' '.join(missing))
        sys.exit(1)
    print('%d imports, all exported' % len(names))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)

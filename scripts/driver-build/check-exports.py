#!/usr/bin/env python3
"""Check that a kernel image exports every symbol a module imports.

Usage: check-exports.py IMAGE|Module.symvers IMPORTS_FILE

IMAGE is the decompressed kernel (as kernel-info.py saves it).  A symbol
counts as exported when its name is in the image as a NUL-terminated
string, as in __ksymtab_strings.  Without the TV's own image, a
Module.symvers from a full build of LG's source with the TV's config lists
the exports instead.  IMPORTS_FILE has one symbol per line (`nm -u
module.ko`).  Exits 1 and lists the missing ones if any aren't there.
"""
import sys


def main(image, imports):
    names = [line.strip() for line in open(imports) if line.strip()]
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
    main(sys.argv[1], sys.argv[2])

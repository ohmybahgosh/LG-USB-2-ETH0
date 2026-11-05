#!/usr/bin/env python3
"""Check that a kernel image exports every symbol a module imports.

Usage: check-exports.py IMAGE IMPORTS_FILE

IMAGE is the decompressed kernel (as kernel-info.py saves it).  IMPORTS_FILE
has one symbol per line (`nm -u module.ko`).  A symbol counts as exported
when its name is in the image as a NUL-terminated string, as in
__ksymtab_strings.  Exits 1 and lists the missing ones if any aren't there.
"""
import sys


def main(image, imports):
    data = open(image, 'rb').read()
    names = [line.strip() for line in open(imports) if line.strip()]
    missing = [n for n in names if b'\0' + n.encode() + b'\0' not in data]
    if missing:
        print('missing exports: ' + ' '.join(missing))
        sys.exit(1)
    print('%d imports, all exported' % len(names))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

#!/usr/bin/env python3
"""Write Kconfig declarations for options a TV's config has but LG's
published source doesn't define, so they survive `make olddefconfig`.

Usage: kconfig-stub.py TV_CONFIG CONFIG_DIFFERENCES > Kconfig

CONFIG_DIFFERENCES is build.sh's config-differences.txt (scripts/diffconfig
output) from a first build: its "-NAME value" lines are the options the
source dropped.  Some of them change kernel headers (Realtek's options in
include/linux/page-flags.h or arch/arm64/include/asm/thread_info.h, for
example), and a module built without them gets a different struct layout.
Put the output where the source's Kconfig expects the missing file (like
arch/arm64/mach-k8/Kconfig for CHIP_NAME=k8) and build again.  Each option
gets the type its value implies and that value as its default, which is
all olddefconfig needs to keep it.
"""
import re
import sys


def main(config, diff):
    values = {}
    for line in open(config):
        m = re.match(r'^CONFIG_(\w+)=(.*)$', line.strip())
        if m:
            values[m.group(1)] = m.group(2)
        m = re.match(r'^# CONFIG_(\w+) is not set$', line.strip())
        if m:
            values[m.group(1)] = 'n'
    dropped = [m.group(1) for m in (re.match(r'^-(\w+) ', l) for l in open(diff)) if m]
    print('# Made by LG-USB-2-ETH0 scripts/driver-build/kconfig-stub.py: the')
    print('# options this TV\'s config has that the published source leaves out,')
    print('# with the TV\'s values.  Only for building modules against it.')
    for name in dropped:
        v = values.get(name)
        if v is None:
            continue
        if v in ('y', 'n'):
            kind, default = 'bool', v
        elif v == 'm':
            kind, default = 'tristate', v
        elif re.match(r'^-?\d+$', v):
            kind, default = 'int', v
        elif re.match(r'^0x[0-9a-fA-F]+$', v):
            kind, default = 'hex', v
        else:
            kind, default = 'string', v if v.startswith('"') else '"%s"' % v
        print('\nconfig %s\n\t%s\n\tdefault %s' % (name, kind, default))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

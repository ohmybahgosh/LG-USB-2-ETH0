#!/usr/bin/env python3
"""Checks for scripts/driver-build/abi-check.py that need no cross tools:
reading kallsyms out of a made-up 32-bit image, picking struct offsets out
of objdump lines (and leaving globals' offsets out), and the net_device
size."""
import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('abi', os.path.join(HERE, '..', 'scripts', 'driver-build', 'abi-check.py'))
abi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(abi)

fails = 0


def check(what, ok):
    global fails
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails += 1


def fake_image(n=600, start=0x80008000):
    """A 32-bit kallsyms layout: addresses, num_syms, names, markers, token
    table and token index, with token i standing for byte i."""
    names = ['T' + ('func%d' % i) for i in range(n)]
    addrs = [start + 0x40 * i for i in range(n)]
    out = bytearray(b'\xaa' * 256)
    out += struct.pack('<%dI' % n, *addrs)
    out += struct.pack('<I', n)
    while len(out) % 16:
        out += b'\0'
    names_at = len(out)
    markers = []
    for i, nm in enumerate(names):
        if i % 256 == 0:
            markers.append(len(out) - names_at)
        b = nm.encode()
        out += bytes([len(b)]) + b
    while len(out) % 4:
        out += b'\0'
    out += struct.pack('<%dI' % len(markers), *markers)
    toks = [b'Z'] + [bytes([i]) for i in range(1, 256)]
    idx = []
    tt = bytearray()
    for t in toks:
        idx.append(len(tt))
        tt += t + b'\0'
    out += tt
    while len(out) % 4:
        out += b'\0'
    out += struct.pack('<256H', *idx)
    out += b'\0' * 64
    return bytes(out), names, addrs


d, names, addrs = fake_image()
tables = abi.find_kallsyms(d, 4)
check('kallsyms found in a made-up image', bool(tables))
if tables:
    t = tables[0]
    check('every symbol read back', len(t) == len(names))
    check('names and types read back', all(t[i][1] == 'T' and t[i][2] == names[i][1:] for i in range(len(names))))
    check('addresses read back', all(t[i][0] == addrs[i] for i in range(len(names))))
check('no kallsyms in random bytes', not abi.find_kallsyms(bytes(range(256)) * 64, 4))

arm = '''
 3a4:	e280cc02 	add	ip, r0, #512	@ 0x200
 3a8:	e3003000 	movw	r3, #0
 3ac:	e3403000 	movt	r3, #0
 3b0:	e5803134 	str	r3, [r0, #308]	@ 0x134
 3b4:	e5933010 	ldr	r3, [r3, #16]
 3b8:	e590313c 	ldr	r3, [r0, #316]	@ 0x13c
 3bc:	e5933008 	ldr	r3, [r3, #8]
 3f4:	e1cc20b4 	strh	r2, [ip, #4]
'''
check('32-bit: struct offsets kept, a movw/movt global\'s left out', abi.offsets(arm) == {308, 316, 8, 4, 516})
a64 = '''
ffffffc010e8d104:	90000003 	adrp	x3, 0xffffffc010e8d000
ffffffc010e8d10c:	9101c063 	add	x3, x3, #0x70
ffffffc010e8d110:	f9401861 	ldr	x1, [x3, #48]
ffffffc010e8d114:	f9400401 	ldr	x1, [x0, #8]
ffffffc010e8d118:	b9013c02 	str	w2, [x0, #316]
'''
check('64-bit: struct offsets kept, an adrp global\'s left out', abi.offsets(a64) == {8, 316})
tv = '   addne	r4, r4, #1232	@ 0x4d0\n'
check('net_device size: same', abi.netdev_size(tv, '    add	r4, r4, #1232\n')[0])
check('net_device size: different', not abi.netdev_size(tv, '    add	r4, r4, #1296\n')[0])

sys.exit(1 if fails else 0)

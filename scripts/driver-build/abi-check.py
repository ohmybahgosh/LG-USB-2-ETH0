#!/usr/bin/env python3
"""Check that kernel code built from LG's source uses the same struct offsets
as the TV's own kernel.

Usage: abi-check.py IMAGE OBJDUMP OBJECT...

IMAGE is the TV's decompressed kernel (as kernel-info.py saves it), OBJDUMP
the cross objdump (arm or aarch64), and each OBJECT a kernel object built
from the source with the TV's config (net/core/dev.o, net/ethernet/eth.o,
net/core/skbuff.o, drivers/usb/core/urb.o, drivers/usb/core/driver.o).

The TV's symbol table is read from the image (kallsyms), and for a fixed set
of small functions that a USB network driver depends on, the struct offsets
in their loads and stores ([reg, #offset]) are compared with the same
functions in the objects.  A struct that grew or moved shows up as offsets
the TV's code uses that ours never does.  Offsets only ours uses are
allowed: a newer compiler inlines more.  The size of struct net_device (the
driver's private data starts right after it) is compared on its own.

Prints one line per function.  Exits 0 when everything matches, 1 when an
offset differs, and 2 when the image can't be read (no kallsyms, unknown
layout): then nothing was checked.
"""
import collections
import re
import struct
import subprocess
import sys

# Small functions whose code is all loads and stores of the structs a driver
# uses (net_device, sk_buff, urb, usb_driver, usb_interface, struct device).
# Bigger ones differ between compilers by what they inline.
FUNCS = [
    'ether_setup', 'eth_type_trans', 'eth_validate_addr', 'netif_napi_add',
    '__netif_schedule', 'dev_set_mtu', 'skb_put', 'skb_pull', 'skb_trim',
    '__netdev_alloc_skb', 'usb_alloc_urb', 'usb_unlink_urb', 'usb_anchor_urb',
    'usb_register_driver', 'usb_deregister', 'usb_driver_claim_interface',
    'usb_autopm_put_interface',
]


def find_kallsyms(d, ptr):
    """Return [(addr, type, name)] from a kernel image, or None."""
    ti = None
    for off in range(0, len(d) - 512, 4):
        if d[off] or d[off + 1]:
            continue
        v = struct.unpack_from('<256H', d, off)
        if all(1 < v[i + 1] - v[i] < 40 for i in range(255)):
            ti = off
            break
    if ti is None:
        return None
    idx = struct.unpack_from('<256H', d, ti)
    # the token table ends right before the index: the closest start that
    # puts a NUL before every token
    for ts in range(ti - idx[255] - 2, ti - 4096, -1):
        if all(d[ts + idx[i] - 1] == 0 for i in range(1, 256)):
            break
    else:
        return None
    toks = [d[ts + idx[i]:d.index(b'\0', ts + idx[i])] for i in range(256)]
    # kallsyms_markers ends right before the token table (u32, or a pointer
    # on older 64-bit kernels), after alignment padding
    for msize in (4, ptr) if ptr == 8 else (4,):
        fmt = '<I' if msize == 4 else '<Q'
        m = ts - msize
        while m > ts - 64 and struct.unpack_from(fmt, d, m)[0] == 0:
            m -= msize
        markers = []
        while m > 0:
            v = struct.unpack_from(fmt, d, m)[0]
            markers.append(v)
            if v == 0:
                break
            m -= msize
        markers.reverse()
        if len(markers) > 2 and all(markers[i] < markers[i + 1] for i in range(len(markers) - 1)):
            break
    else:
        return None
    lo, hi = (len(markers) - 1) * 256, len(markers) * 256
    s = m - 4
    names = None
    while s > max(0, m - 32 * 1024 * 1024):
        num = struct.unpack_from('<I', d, s)[0]
        if lo < num <= hi:
            for st in range(s + 4, s + 68, 4):
                o, offs = st, []
                for i in range(min(num, 768) + 1):
                    if i % 256 == 0:
                        offs.append(o - st)
                    o += 1 + d[o]
                if offs[:3] == markers[:3]:
                    names = st
                    break
        if names:
            break
        s -= 4
    if not names:
        return None
    cands = read_addresses(d, s, num, ptr)
    if not cands:
        return None
    names_list = []
    o = names
    for i in range(num):
        ln = d[o]
        nm = b''.join(toks[b] for b in d[o + 1:o + 1 + ln])
        o += 1 + ln
        names_list.append((chr(nm[0]), nm[1:].decode('latin1')))
    # Every way the address table could line up with the names (padding
    # around it varies): main() keeps the one that puts functions on
    # function prologues
    return [[(a, t, n) for a, (t, n) in zip(addrs, names_list)] for addrs in cands]


def plausible(addrs):
    hits = sum(1 for i in range(len(addrs) - 1) if addrs[i] <= addrs[i + 1])
    return hits > 0.9 * len(addrs)


def table_end(d, end):
    """Where a table that ends at or before `end` really ends: alignment
    padding (zeros) can sit between it and what follows.  Its last entry,
    the highest address or offset, is never 0."""
    e = end
    while e > end - 64 and struct.unpack_from('<I', d, e - 4)[0] == 0:
        e -= 4
    return e


def read_addresses(d, s, num, ptr):
    """The address of every symbol: a pointer array that ends right before
    num_syms, or (KALLSYMS_BASE_RELATIVE) 32-bit offsets from
    kallsyms_relative_base, which sits right before num_syms.  Either can be
    followed by alignment padding.  Returns the candidates that look sorted
    (one, unless the layout is unusual)."""
    top = 0xffff000000000000 if ptr == 8 else 0x40000000
    fmt = '<Q' if ptr == 8 else '<I'
    found = []
    b = s - ptr
    base = struct.unpack_from(fmt, d, b)[0] if b >= 0 else 0
    if base >= top:
        a = table_end(d, b) - 4 * num
        if a >= 0:
            offs = struct.unpack_from('<%di' % num, d, a)
            addrs = [base + v if v >= 0 else base - 1 - v for v in offs]
            if plausible(addrs[:2000]):
                found.append(addrs)
    a = table_end(d, s) - ptr * num
    if a >= 0:
        addrs = struct.unpack_from('<%d%s' % (num, fmt[1]), d, a)
        if addrs[0] >= top and plausible(addrs[:2000]):
            found.append(list(addrs))
    return found


OFF = re.compile(r'\[((?:r|x)\d+|ip|fp|lr)\s*, #(-?(?:0x)?[0-9a-f]+)\]')
INSN = re.compile(r'^\s*[0-9a-f]+:\s+(?:[0-9a-f]{8}|[0-9a-f]{4} [0-9a-f]{4})\s+(\S+)\s*([^;@/]*)')


def accesses(text):
    """Offsets of loads and stores off a register that holds a pointer.  A
    register set to a global's address (adrp, movw/movt, a pc-relative
    literal) doesn't count: its offsets come from where the linker put
    things, not from a struct.  A register set to another plus a constant
    (add x2, x19, #512) counts from the first one, so [x2, #-168] is offset
    344, whichever way the compiler chose to reach it.  Returns each access
    as (offset as written, offset from the first register): a compiler can
    also get the second pointer from somewhere else, so both count."""
    c = set()
    glob = set()
    delta = {}
    for line in text.splitlines():
        m = INSN.match(line)
        if not m:
            continue
        op, args = m.group(1), m.group(2).strip()
        regs = [r.strip() for r in args.split(',')]
        dst = regs[0] if regs else ''
        if re.match(r'w\d+$', dst):
            dst = 'x' + dst[1:]
        for mm in OFF.finditer(args):
            if mm.group(1) not in glob:
                raw = int(mm.group(2), 0)
                off = raw + delta.get(mm.group(1), 0)
                c.add((raw, off))
                # a pair (stp, ldp, ldrd, strd) also touches the next field
                if op in ('stp', 'ldp', 'stnp', 'ldnp', 'ldrd', 'strd'):
                    w = 8 if dst.startswith(('x', 'd')) else 4
                    c.add((raw + w, off + w))
        imm = re.match(r'#(-?(?:0x)?[0-9a-f]+)$', regs[2]) if len(regs) == 3 else None
        if op in ('bl', 'blx', 'blr'):
            # a call leaves the argument and scratch registers undefined
            for r in list(glob) + list(delta):
                n = re.match(r'[rx](\d+)$', r)
                if (n and int(n.group(1)) <= 18) or r in ('ip', 'lr'):
                    glob.discard(r)
                    delta.pop(r, None)
        elif op in ('adrp', 'adr', 'movw', 'movt') or (op.startswith('ldr') and '[pc' in args):
            glob.add(dst)
            delta.pop(dst, None)
        elif op in ('add', 'sub') and imm and regs[1] in glob:
            glob.add(dst)
        elif op in ('add', 'sub') and imm and re.match(r'(r|x)\d+$|ip|fp$', regs[1]):
            v = int(imm.group(1), 0)
            delta[dst] = delta.get(regs[1], 0) + (v if op == 'add' else -v)
            glob.discard(dst)
        elif op.startswith(('str', 'stp', 'stur', 'cmp', 'cmn', 'tst', 'teq', 'b', 'cb', 'tb', 'push', 'stm', 'ret', 'nop', 'hint', 'dmb', 'dsb', 'isb', 'prfm')) and not op.startswith(('bic', 'bfi', 'bfx', 'bfc')):
            pass
        else:
            glob.discard(dst)
            delta.pop(dst, None)
    return c


def offsets(text):
    """Every offset an access could mean (see accesses)."""
    return {o for pair in accesses(text) for o in pair}


def main(image, objdump, objs):
    d = open(image, 'rb').read()
    arm64 = d[56:60] == b'ARM\x64'
    ptr = 8 if arm64 else 4
    tables = find_kallsyms(d, ptr)
    if not tables:
        print('no kallsyms in the image: struct offsets not checked')
        return 2
    best = None
    for syms in tables:
        t = sorted((a, n) for a, ty, n in syms if ty in 'Tt')
        sc, b = find_base(d, t, arm64)
        if best is None or sc > best[0]:
            best = (sc, b, t)
    _, base, text = best
    where = {}
    count = collections.Counter(n for a, n in text)
    for i, (a, n) in enumerate(text[:-1]):
        if count[n] == 1:
            # the function ends at the next symbol with a higher address
            # (aliases share an address)
            j = i + 1
            while j < len(text) - 1 and text[j][0] <= a:
                j += 1
            where[n] = (a, text[j][0])
    mach = 'aarch64' if arm64 else 'arm'

    def tv(fn):
        a, e = where[fn]
        r = subprocess.run([objdump, '-D', '-b', 'binary', '-m', mach, '--adjust-vma=%#x' % base,
                            '--start-address=%#x' % a, '--stop-address=%#x' % e, image],
                           capture_output=True, text=True)
        return r.stdout

    ours = {}
    for obj in objs:
        r = subprocess.run([objdump, '-d', obj], capture_output=True, text=True).stdout
        for part in re.split(r'\n(?=[0-9a-f]+ <)', r):
            mm = re.match(r'[0-9a-f]+ <([^>]+)>:', part)
            if mm:
                ours[mm.group(1)] = part
    bad = 0
    checked = 0
    for fn in FUNCS:
        if fn not in where or fn not in ours:
            print('%-28s skipped (%s)' % (fn, 'not in the image' if fn not in where else 'not built'))
            continue
        t, o = accesses(tv(fn)), offsets(ours[fn])
        if not t:
            print('%-28s skipped (no loads or stores found)' % fn)
            continue
        checked += 1
        # an access matches when either reading of it is one ours makes
        miss = sorted({raw for raw, norm in t if raw not in o and norm not in o})
        if miss:
            bad += 1
            print('%-28s DIFFERS: the TV uses offsets %s, this source never does' % (fn, miss))
        else:
            print('%-28s ok (%d offsets)' % (fn, len(t)))
    nd = netdev_size(tv('alloc_netdev_mqs') if 'alloc_netdev_mqs' in where else '', ours.get('alloc_netdev_mqs', ''))
    if nd:
        print('%-28s %s' % ('sizeof(struct net_device)', nd[1]))
        bad += 0 if nd[0] else 1
    if checked < 6:
        print('only %d functions could be compared: struct offsets not checked' % checked)
        return 2
    print('struct offsets %s' % ('differ' if bad else 'match the TV\'s kernel'))
    return 1 if bad else 0


def netdev_size(tv_code, our_code):
    """alloc_netdev_mqs adds sizeof(struct net_device) to the private size."""
    pat = re.compile(r'\badd(?:ne)?\s+[rx]\d+, [rx]\d+, #(\d+)')
    t = sorted({int(v) for v in pat.findall(tv_code) if 256 <= int(v) <= 8192})
    o = sorted({int(v) for v in pat.findall(our_code) if 256 <= int(v) <= 8192})
    if not t or not o:
        return None
    if set(t) & set(o):
        return True, 'ok (%d)' % max(set(t) & set(o))
    return False, 'DIFFERS: the TV adds %s, this source %s' % (t, o)


def find_base(d, text, arm64):
    """The image's load address: the one that puts most function symbols on a
    function prologue (64-bit: stp x29, x30, [sp, #-N]! or paciasp; 32-bit:
    push {..., lr} or mov ip, sp).  Tried up to 2 MiB below the lowest text
    symbol, in 4 KiB steps (64-bit) or 64-byte steps (32-bit)."""
    addrs = [a for a, n in text]
    sample = addrs[::50][:400]

    def score(base):
        sc = 0
        for a in sample:
            o = a - base
            if 0 <= o < len(d) - 4:
                w = struct.unpack_from('<I', d, o)[0]
                if arm64:
                    if (w & 0xffc07fff) == 0xa9807bfd or w in (0xd503233f, 0xd503245f, 0xd503249f):
                        sc += 1
                elif (w & 0xffff4000) == 0xe92d4000 or w == 0xe1a0c00d:
                    sc += 1
        return sc
    if arm64:
        lo = min(addrs) & ~0xfff
        cands = range(lo - 0x200000, lo + 0x1000, 0x1000)
    else:
        lo = min(addrs) & ~0x3f
        cands = range(lo - 0x200000, lo + 0x40, 0x40)
    return max((score(b), b) for b in cands)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))

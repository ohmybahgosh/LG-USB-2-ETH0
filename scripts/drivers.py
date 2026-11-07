#!/usr/bin/env python3
"""The drivers built here, waiting for testers or reported working.

Reads TESTED_DRIVERS and EXPERIMENTAL_DRIVERS from LG-USB-2-ETH0.sh and keeps
the README and its badge in step with them.

  scripts/drivers.py check [--sums FILE]
      Fails if the README's list, its counts or the badge don't match the
      script, or a row's SHA-256 isn't the mirror's.  Without --sums it
      fetches experimental/SHA256SUMS from the mirror commit the script pins.
  scripts/drivers.py update
      Rewrites the README's list, its counts and the badge from the script.
  scripts/drivers.py promote REPORT_FILE
      Reads a driver test report (the issue body, or test-driver --last).  If
      the result is "works", moves that driver's row from EXPERIMENTAL_DRIVERS
      to TESTED_DRIVERS and runs update.  Prints what it moved, or why not.

Nothing from the report is copied into the script: it only picks a row that
is already there, by folder, file and the start of its SHA-256.
"""
import os
import re
import sys
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SCRIPT = os.path.join(ROOT, 'LG-USB-2-ETH0.sh')
README = os.path.join(ROOT, 'README.md')
BADGE = os.path.join(ROOT, 'assets', 'badge-drivers-to-test.svg')
MIRROR = 'https://github.com/ohmybahgosh/lg-webos-usb-drivers'
CHIPS = {'k24': 'K24', 'k24n': 'K24N', 'k24t': 'K24T', 'k25lp': 'K25Lp', 'k8hp': 'K8Hp', 'k8hpp': 'K8Hpp',
         'k8hpt': 'K8HpT', 'k8lp': 'K8Lp', 'k8lpn': 'K8LpN', 'k8lpn2': 'K8LpN2', 'k8ap': 'K8Ap', 'k6lp': 'K6Lp',
         'k6hp': 'K6Hp', 'k7lp': 'K7LP'}
# Drivers for chips other than Realtek's and ASIX's AX88179, as the list names them
OTHER = {'aqc111.ko': 'Aquantia AQC111', 'dm9601.ko': 'Davicom DM9601', 'lan78xx.ko': 'Microchip LAN78xx'}
START, END = '<!-- drivers:start -->', '<!-- drivers:end -->'
ROW = re.compile(r'^([0-9][A-Za-z0-9._-]*) ([a-z0-9]+|-) ([a-z0-9_]+\.ko) ([0-9a-f]{64})$')


def table(src, name):
    m = re.search(r'^%s="([^"]*)"' % name, src, re.M)
    if not m:
        sys.exit('%s not found in LG-USB-2-ETH0.sh' % name)
    rows = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line:
            continue
        r = ROW.match(line)
        if not r:
            sys.exit('bad %s row: %s' % (name, line))
        rows.append(r.groups())
    return rows, m


def folder(k, ch):
    return k if ch == '-' else '%s-%s' % (k, ch)


def webos(k):
    if k.startswith('4.4.84-61'):
        return 'webOS 5'
    if k.startswith('4.4.84-899') or k.startswith('4.4.84-723'):
        return 'webOS 6'
    if '-329.' in k or '-294.' in k or '-966.15.' in k:
        return 'webOS 25'
    if k.startswith('5.4.268-320') or '-223.' in k or '-966.8.' in k or '-955.16.' in k:
        return 'webOS 24'
    if k.startswith('5.4.96-307') or '-132.' in k or '-955.20.' in k:
        return 'webOS 23'
    if '-115.' in k or '-934.' in k:
        return 'webOS 22'
    return 'other'


# usbnet.ko rows are a helper some drivers load first, not a driver to list
HELPERS = ('usbnet.ko',)
# Kernels with no chip in their row: LG's LM21A-family LCD chips, or LG's own
LM_CHIPS = (('-934.', 'LM21AN'), ('-955.20.namtok', 'LM21ANN'), ('-966.', 'LM21ANN'),
            ('-899.', 'LM21A'), ('-955.16.nbr4tv', 'LM21UT'))


def lm_chip(k):
    return next((c for m, c in LM_CHIPS if m in k), 'LG chips')


def listing(rows):
    rows = [r for r in rows if r[2] not in HELPERS]
    kern = {}
    for k, ch, f, _ in rows:
        e = kern.setdefault(k, {'chips': [], 'realtek': False, 'asix': False, 'other': set()})
        fo = folder(k, ch)
        link = '[%s](%s/tree/main/experimental/%s)' % (CHIPS.get(ch, ch.upper()) if ch != '-' else lm_chip(k), MIRROR, fo)
        if link not in e['chips']:
            e['chips'].append(link)
        e['realtek'] |= f.startswith('r8152')
        e['asix'] |= f.startswith('ax88179')
        if f in OTHER:
            e['other'].add(OTHER[f])
    out = []
    for g in ('webOS 25', 'webOS 24', 'webOS 23', 'webOS 22', 'webOS 6', 'webOS 5', 'other'):
        ks = sorted((k for k in kern if webos(k) == g), reverse=True)
        if not ks:
            continue
        out += ['**%s**' % g, '', '| Kernel (`uname -r`) | Chips | Realtek | ASIX | Others |', '|---|---|:-:|:-:|---|']
        for k in ks:
            e = kern[k]
            others = ', '.join(o for o in OTHER.values() if o in e['other'])
            out.append('| `%s` | %s | %s | %s | %s |' % (k, ', '.join(e['chips']), 'yes' if e['realtek'] else '', 'yes' if e['asix'] else '', others))
        out.append('')
    chips = {ch for _, ch, _, _ in rows if ch != '-'}
    return '\n'.join(out).rstrip() + '\n', len(rows), len(kern), len(chips)


# Verdana 11px advance widths, as ohmybahgosh.dev's badges use
W = {**{c: 7.0 for c in '0123456789'}, 'a': 6.8, 'b': 6.9, 'c': 5.9, 'd': 6.9, 'e': 6.7, 'f': 3.9, 'g': 6.9,
     'h': 7.0, 'i': 3.0, 'j': 3.8, 'k': 6.5, 'l': 3.0, 'm': 10.7, 'n': 7.0, 'o': 6.7, 'p': 6.9, 'q': 6.9,
     'r': 4.7, 's': 5.7, 't': 4.3, 'u': 7.0, 'v': 6.5, 'w': 9.0, 'x': 6.5, 'y': 6.5, 'z': 5.8, ' ': 3.5}


def badge(label, value, colour='ffb547'):
    w = lambda t: sum(W.get(c, 7.5) for c in t)
    lw, vw = round(w(label)) + 12, round(w(value)) + 12
    tw = lw + vw
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{tw}" height="20" role="img" aria-label="{label}: {value}">'
            f'<title>{label}: {value}</title><g shape-rendering="crispEdges">'
            f'<rect width="{lw}" height="20" fill="#0a0e1a"/><rect x="{lw}" width="{vw}" height="20" fill="#{colour}"/></g>'
            f'<g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="11" '
            f'text-rendering="geometricPrecision"><text x="{lw / 2}" y="14" textLength="{round(w(label))}" '
            f'lengthAdjust="spacingAndGlyphs">{label}</text><text x="{lw + vw / 2}" y="14" textLength="{round(w(value))}" '
            f'lengthAdjust="spacingAndGlyphs">{value}</text></g></svg>')


def render(readme, rows, tested=()):
    body, n, nk, nc = listing(rows)
    if tested:
        tb = listing(list(tested))[0].replace('**webOS', '**Reported working, now offered by get-driver: webOS')
        body = tb + '\n' + body
    i, j = readme.index(START), readme.index(END)
    readme = readme[:i + len(START)] + '\n\n' + body + '\n' + readme[j:]
    readme = re.sub(r'\*\*\d+ more drivers are built and waiting for testers\.\*\*',
                    '**%d more drivers are built and waiting for testers.**' % n, readme)
    readme = re.sub(r'All \d+ drivers: \d+ kernels, \d+ Realtek chips',
                    'All %d drivers: %d kernels, %d Realtek chips' % (n, nk, nc), readme)
    return readme, badge('drivers to test', str(n))


def update():
    src = open(SCRIPT).read()
    rows, _ = table(src, 'EXPERIMENTAL_DRIVERS')
    tested, _ = table(src, 'TESTED_DRIVERS')
    readme, svg = render(open(README).read(), rows, tested)
    open(README, 'w').write(readme)
    open(BADGE, 'w').write(svg)
    print('README and badge: %d drivers waiting for testers' % len([r for r in rows if r[2] not in HELPERS]))


def check(sums_file=None):
    src = open(SCRIPT).read()
    exp, _ = table(src, 'EXPERIMENTAL_DRIVERS')
    tested, _ = table(src, 'TESTED_DRIVERS')
    bad = []
    readme = open(README).read()
    want, svg = render(readme, exp, tested)
    if want != readme:
        bad.append('README.md: the driver list or its counts are out of date (run scripts/drivers.py update)')
    if not os.path.exists(BADGE) or open(BADGE).read() != svg:
        bad.append('assets/badge-drivers-to-test.svg is out of date (run scripts/drivers.py update)')
    seen = set()
    for r in exp + tested:
        key = (folder(r[0], r[1]), r[2])
        if key in seen:
            bad.append('%s/%s is listed twice' % key)
        seen.add(key)
    url = re.search(r'^EXPERIMENTAL_URL="([^"]+)"', src, re.M).group(1)
    if sums_file:
        sums = open(sums_file).read()
    else:
        with urllib.request.urlopen(url + '/SHA256SUMS', timeout=60) as f:
            sums = f.read().decode()
    mirror = {}
    for line in sums.splitlines():
        p = line.split()
        if len(p) == 2:
            mirror[p[1]] = p[0]
    for k, ch, f, sha in exp + tested:
        path = '%s/%s' % (folder(k, ch), f)
        if path not in mirror:
            bad.append('%s is not in the mirror at %s' % (path, url))
        elif mirror[path] != sha:
            bad.append('%s: the script says %s, the mirror %s' % (path, sha, mirror[path]))
    listed = {'%s/%s' % (folder(k, ch), f) for k, ch, f, _ in exp + tested}
    for path in sorted(set(mirror) - listed):
        bad.append('%s is in the mirror but not in the script' % path)
    for b in bad:
        print('FAIL ' + b)
    print('%d waiting for testers, %d tested, %d in the mirror: %s' % (len(exp), len(tested), len(mirror), 'ok' if not bad else 'problems'))
    return not bad


def promote(report_file):
    rep = open(report_file, encoding='utf-8', errors='replace').read()
    m = re.search(r'Driver:\s+experimental/([A-Za-z0-9._-]+)/([a-z0-9_]+\.ko)\s+\(([0-9a-f]{16})\)', rep)
    if not m:
        print('No driver line in the report, so nothing to move.')
        return 2
    fo, f, short = m.groups()
    if not re.search(r'^\s*Result:\s+works\s*$', rep, re.M):
        print('The result for %s/%s is not "works", so it stays a driver to test.' % (fo, f))
        return 2
    src = open(SCRIPT).read()
    exp, em = table(src, 'EXPERIMENTAL_DRIVERS')
    tested, tm = table(src, 'TESTED_DRIVERS')
    hit = [r for r in exp if folder(r[0], r[1]) == fo and r[2] == f and r[3].startswith(short)]
    if len(hit) != 1:
        if any(folder(r[0], r[1]) == fo and r[2] == f for r in tested):
            print('%s/%s is already a tested driver.' % (fo, f))
        else:
            print('%s/%s (%s) matches no driver waiting for testers.' % (fo, f, short))
        return 2
    row = hit[0]
    exp.remove(row)
    tested.append(row)
    # A driver built on usbnet, for a kernel that leaves it out, takes its
    # usbnet.ko along
    helper = [r for r in exp if folder(r[0], r[1]) == fo and r[2] in HELPERS]
    for h in helper:
        exp.remove(h)
        tested.append(h)
    fmt = lambda rows: '\n'.join(' '.join(r) for r in rows)
    # Replace the later table first, so the earlier match's offsets still hold
    for m2, rows in sorted(((em, exp), (tm, tested)), key=lambda x: -x[0].start(1)):
        src = src[:m2.start(1)] + fmt(rows) + src[m2.end(1):]
    open(SCRIPT, 'w').write(src)
    update()
    print('Moved %s/%s to TESTED_DRIVERS: get-driver now offers it for kernel %s%s.' % (
        fo, f, row[0], '' if row[1] == '-' else ' on the %s chip' % CHIPS.get(row[1], row[1])))
    return 0


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['check']:
        s = a[a.index('--sums') + 1] if '--sums' in a else None
        sys.exit(0 if check(s) else 1)
    if a[:1] == ['update']:
        update()
        sys.exit(0)
    if a[:1] == ['promote'] and len(a) == 2:
        sys.exit(promote(a[1]))
    sys.exit(__doc__)

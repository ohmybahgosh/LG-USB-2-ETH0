#!/usr/bin/env python3
"""Watch LG's firmware releases for kernels this project doesn't cover yet.

Reads the firmware index of the EPK archive (https://tv.slada.sk/), where
every LG firmware file is listed with its kernel version and chip, and
compares it with what the project knows: the kernels with drivers in
LG-USB-2-ETH0.sh, and the firmware already audited in results.tsv.

Usage:
  monitor.py new INDEX SINCE [MAX]
      One JSON line per (kernel, chip) pair released on or after SINCE
      (YYYY-MM-DD) that has no drivers and no audit yet, newest first, at
      most MAX (default 3).  Kernel 4.4 and later only.  Each has the newest firmware file for it.
  monitor.py coverage INDEX
      A Markdown table of every pair with kernel 4.4 or later, newest first,
      with what the project has for it.
  monitor.py body PAIR.json AUDIT.tsv [CONFIG]
      The issue text for a pair, from its audit line (audit.sh's output)
      and, when the firmware has one, the kernel's config.

INDEX is the archive's processed_fw.json (a path, or - to download it).
"""
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INDEX_URL = 'https://tv.slada.sk/processed_fw.json'
REALTEK = ('r8152',)
ASIX = ('ax88179_178a',)


def load_index(path):
    if path == '-':
        req = urllib.request.Request(INDEX_URL, headers={'User-Agent': 'LG-USB-2-ETH0 firmware monitor'})
        return json.load(urllib.request.urlopen(req, timeout=300))
    return json.load(open(path))


def pairs(index):
    """(kernel, chip) -> newest release date, firmware versions, models, newest file"""
    out = {}
    for path, v in index['fws'].items():
        li = v.get('lookupInfo') or {}
        date = (li.get('releaseDate') or '')[:10]
        for e in v.get('epks', []):
            kern = e.get('kernelVersion')
            m = re.search(r'secured[-_]([a-z0-9]+)[-_]', e.get('file', ''))
            if not kern or not m:
                continue
            x = out.setdefault((kern, m.group(1)), {'kernel': kern, 'chip': m.group(1), 'date': '',
                                                    'firmware': set(), 'models': set(), 'path': ''})
            x['firmware'].add('.'.join(e.get('firmwareversion', '').split('.')[:3]))
            x['models'].update(li.get('modelNames', []))
            if date >= x['date']:
                x['date'], x['path'] = date, path
    return out


def known():
    """Kernels with drivers (kernel, chip or '-'), and audited (kernel, chip) pairs"""
    s = open(os.path.join(ROOT, 'LG-USB-2-ETH0.sh')).read()
    drivers = set()
    for name in ('EXPERIMENTAL_DRIVERS="', 'TESTED_DRIVERS="'):
        i = s.index(name)
        j = s.index('"', i + len(name))
        for line in s[i + len(name):j].split('\n'):
            p = line.split()
            if len(p) >= 2:
                drivers.add((p[0], p[1]))
    audited = {}
    for line in open(os.path.join(ROOT, 'scripts/firmware-audit/results.tsv')).read().split('\n')[1:]:
        p = line.split('\t')
        if len(p) >= 7:
            audited[(p[4], p[2])] = (p[5], p[6])
    return drivers, audited


def modern(kernel):
    """Kernel 4.4 and later: webOS 3.5 (2017) on.  Older TVs can't run the script"""
    m = re.match(r'(\d+)\.(\d+)\.', kernel)
    return bool(m) and (int(m.group(1)), int(m.group(2))) >= (4, 4)


def status(x, drivers, audited):
    k, c = x['kernel'], x['chip']
    if (k, c) in drivers or (k, '-') in drivers:
        return 'drivers to test or tested'
    if (k, c) in audited:
        b, m = audited[(k, c)]
        have = (b + ' ' + m).split()
        if any(d in have for d in REALTEK) and any(d in have for d in ASIX):
            return 'works as is (Realtek and ASIX built in)'
        if any(d in have for d in REALTEK):
            return 'Realtek built in'
        return 'audited, no drivers yet'
    return 'not checked'


def short(values, n):
    values = sorted(v for v in values if v)
    return ', '.join(values[:n]) + (' and %d more' % (len(values) - n) if len(values) > n else '')


def cmd_new(index, since, limit=3):
    drivers, audited = known()
    todo = [x for x in pairs(index).values()
            if x['date'] >= since and modern(x['kernel'])
            and (x['kernel'], x['chip']) not in drivers and (x['kernel'], '-') not in drivers
            and (x['kernel'], x['chip']) not in audited]
    todo.sort(key=lambda x: x['date'], reverse=True)
    for x in todo[:int(limit)]:
        x = dict(x, firmware=sorted(x['firmware']), models=sorted(x['models']))
        print(json.dumps(x))


def cmd_coverage(index):
    drivers, audited = known()
    rows = [x for x in pairs(index).values() if modern(x['kernel'])]
    rows.sort(key=lambda x: (x['date'], x['kernel']), reverse=True)
    print('| Released | Kernel | Chip | Firmware | Models | Status |')
    print('|---|---|---|---|---|---|')
    for x in rows:
        print('| %s | `%s` | %s | %s | %s | %s |' % (x['date'] or '-', x['kernel'], x['chip'],
              short(x['firmware'], 3), short(x['models'], 3), status(x, drivers, audited)))


def cmd_body(pair, audit, config=None):
    x = json.load(open(pair))
    p = (open(audit).read().strip().split('\n') or [''])[-1].split('\t')
    built, mods = (p[5], p[6]) if len(p) >= 7 else ('', '')
    have = set((built + ' ' + mods).replace('none', '').split())
    cfg = dict(re.findall(r'^CONFIG_(\w+)=(\S+)', open(config).read(), re.M)) if config and os.path.exists(config) else {}
    lines = ['LG released firmware with a kernel this project has no drivers or audit for yet.', '',
             '- **Kernel:** `%s` (what `uname -r` prints)' % x['kernel'],
             '- **Chip:** %s' % x['chip'],
             '- **Released:** %s' % (x['date'] or 'unknown'),
             '- **Firmware:** %s' % short(x['firmware'], 8),
             '- **Models:** %s' % short(x['models'], 12),
             '- **File:** `%s` in the [EPK archive](https://tv.slada.sk/)' % x['path'], '']
    if not p or len(p) < 7 or p[4] == 'unknown':
        lines += ['The automatic audit couldn\'t read this firmware, so it needs a look by hand.']
    else:
        lines += ['**Audit:** built in: %s.  Modules: %s.' % (built or 'none', mods or 'none'), '']
        if cfg.get('MODULE_SIG_FORCE') == 'y':
            lines += ['**Module signing is enforced** (`CONFIG_MODULE_SIG_FORCE`), so the TV only loads modules LG signed.  No driver built here can load: only drivers already in the kernel can work.']
        elif cfg and cfg.get('MODULES') != 'y':
            lines += ['This kernel can\'t load modules at all, so only drivers already in it can work.']
        elif 'r8152' in have and 'ax88179_178a' in have:
            lines += ['Realtek and ASIX AX88179 drivers are already in the kernel: LG-USB-2-ETH0 works on it as is.  Nothing to build.']
        else:
            need = [n for d, n in (('r8152', 'Realtek'), ('ax88179_178a', 'ASIX AX88179'), ('dm9601', 'Davicom'), ('lan78xx', 'Microchip')) if d not in have]
            lines += ['Missing: %s.  Drivers need building for this kernel%s.' % (', '.join(need), '' if 'usbnet' in have else ', with `usbnet`')]
    lines += ['', 'Opened by the firmware monitor (`.github/workflows/firmware-monitor.yml`).  It\'s closed when the release with drivers for it, or its audit row, is out.']
    print('\n'.join(lines))


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['new'] and len(a) in (3, 4):
        cmd_new(load_index(a[1]), *a[2:])
    elif a[:1] == ['coverage'] and len(a) == 2:
        cmd_coverage(load_index(a[1]))
    elif a[:1] == ['body'] and len(a) in (3, 4):
        cmd_body(*a[1:])
    else:
        sys.exit(__doc__)

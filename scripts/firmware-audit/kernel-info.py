#!/usr/bin/env python3
"""Read a Linux kernel image from LG TV firmware: its version string, and
which USB network drivers its built-in config (CONFIG_IKCONFIG) has.

Usage: kernel-info.py KERNEL_IMAGE
Prints kernel=, config=yes|, builtin= and modules= lines.
"""
import gzip
import zlib
import re
import sys

# Config symbol -> driver (module) name, for the USB network drivers that
# matter for USB Ethernet adapters
DRIVERS = [
    ('USB_RTL8152', 'r8152'),
    ('USB_RTL8153_ECM', 'r8153_ecm'),
    ('USB_NET_AX8817X', 'asix'),
    ('USB_NET_AX88179_178A', 'ax88179_178a'),
    ('USB_NET_CDCETHER', 'cdc_ether'),
    ('USB_NET_CDC_NCM', 'cdc_ncm'),
    ('USB_NET_CDC_EEM', 'cdc_eem'),
    ('USB_NET_SMSC95XX', 'smsc95xx'),
    ('USB_NET_SMSC75XX', 'smsc75xx'),
    ('USB_LAN78XX', 'lan78xx'),
    ('USB_NET_AQC111', 'aqc111'),
    ('USB_NET_DM9601', 'dm9601'),
    ('USB_RTL8150', 'rtl8150'),
    ('USB_USBNET', 'usbnet'),
]


def lz4_block(src):
    """Decompress one LZ4 block (the format inside legacy LZ4 frames)."""
    out = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]
        i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        out += src[i:i + lit]
        i += lit
        if i >= n:
            break
        off = src[i] | (src[i + 1] << 8)
        i += 2
        ml = token & 15
        if ml == 15:
            while True:
                b = src[i]
                i += 1
                ml += b
                if b != 255:
                    break
        ml += 4
        start = len(out) - off
        for k in range(ml):
            out.append(out[start + k])
    return bytes(out)


def unlz4_legacy(data):
    """Legacy LZ4 frame (magic 0x184C2102), as some LG kernel.pak files use."""
    out = bytearray()
    i = 4
    while i + 4 <= len(data):
        size = int.from_bytes(data[i:i + 4], 'little')
        if size == 0x184C2102:
            i += 4
            continue
        i += 4
        if size == 0 or i + size > len(data):
            break
        out += lz4_block(data[i:i + size])
        i += size
    return bytes(out)


def main(path):
    data = open(path, 'rb').read()
    if data[:4] == bytes.fromhex('02214c18'):
        data = unlz4_legacy(data)
    elif data[:2] == b'\x1f\x8b':
        # Only the first gzip member: the image can have padding after it
        data = zlib.decompressobj(31).decompress(data)
    m = re.search(rb'Linux version (\S+) \(', data)
    print('kernel=' + (m.group(1).decode() if m else ''))
    start = data.find(b'IKCFG_ST')
    end = data.find(b'IKCFG_ED', start + 8)
    if start < 0 or end < 0:
        print('config=')
        return
    try:
        config = gzip.decompress(data[start + 8:end]).decode('utf-8', 'replace')
    except OSError:
        print('config=')
        return
    values = dict(re.findall(r'^CONFIG_(\w+)=(\S+)', config, re.M))
    print('config=yes')
    print('builtin=' + ' '.join(n for s, n in DRIVERS if values.get(s) == 'y'))
    print('modules=' + ' '.join(n for s, n in DRIVERS if values.get(s) == 'm'))


if __name__ == '__main__':
    main(sys.argv[1])

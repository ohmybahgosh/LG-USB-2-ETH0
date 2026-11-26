#!/usr/bin/env python3
"""Give an old ax88179_178a.c the 2022 RX fix.

LG's 4.4 and 5.4.96 sources have the ax88179_rx_fixup from before Linux's
"net: usb: ax88179_178a: Fix packet receiving" (f8ebb3ac881b, 2022).  Current
AX88179 firmware puts a dummy entry after each packet's entry in the table at
the end of a USB transfer, which the old code doesn't know about.  It hands up
the real packets, then treats the leftover table as one more packet: counted
as an RX length error when it's short, and passed up as a junk frame (counted
as dropped) when it's longer.

This swaps the function for the fixed one in ax88179-rx-fixup.c, which is
Linux 5.4.268's (the same as in LG's webOS 25 source), with the trailer read
by memcpy as the old code did, since 4.4's driver doesn't include
asm/unaligned.h.  A source that already has the fix is left as it is.

Usage: ax88179-rx-fixup.py DRIVER.c
"""
import os
import re
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8').read()
if 'Skip dummy header' in src:
    print('ax88179_rx_fixup: already fixed')
    sys.exit(0)
here = os.path.dirname(os.path.abspath(__file__))
new = open(os.path.join(here, 'ax88179-rx-fixup.c'), encoding='utf-8').read().rstrip('\n') + '\n'
m = re.search(r'^static int ax88179_rx_fixup\(struct usbnet \*dev, struct sk_buff \*skb\)\n\{.*?^\}\n',
              src, re.S | re.M)
if not m:
    sys.exit('ax88179_rx_fixup not found in ' + path)
open(path, 'w', encoding='utf-8').write(src[:m.start()] + new + src[m.end():])
print('ax88179_rx_fixup: replaced with the 2022 fix')

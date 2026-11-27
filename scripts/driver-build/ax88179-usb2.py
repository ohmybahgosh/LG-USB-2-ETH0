#!/usr/bin/env python3
"""Smaller USB 2.0 receive transfers for ax88179_178a.

On USB 2.0 at gigabit, Linux's driver has the adapter bundle packets into
24 KB transfers, and usbnet only keeps about 89 KB of them queued: 3 at a
time.  On a TV's USB 2.0 port that leaves the bus idle between them.  With
8 (10 KB transfers, 8 queued), a 2020 NANO91 downloaded about 60% faster
(134 to 212 Mbit/s) for about 7% slower upload; the adapter's timer made no
difference (issue #62).

This adds two module parameters, changeable at
/sys/module/ax88179_178a/parameters/ and used from the next link change:
  hs_size   the bulk-in size on USB 2.0 at gigabit: transfers are
            (hs_size + 2) KB.  8 by default, -1 for the stock 22.  When set
            to something else than 8 or -1, it's used at 100M too.
  hs_timer  the adapter's aggregation timer on USB 2.0, -1 (the default)
            for the stock one.
USB 3.0 is left as it is.  The kernel log says what's used
("USB 2.0 bulk-in: ...").

Usage: ax88179-usb2.py DRIVER.c
"""
import sys

p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'module_param(hs_size' in s:
    print('ax88179 USB 2.0 settings: already there')
    sys.exit(0)
a = '#include <linux/mdio.h>\n'
if s.count(a) != 1:
    sys.exit('no #include <linux/mdio.h> in ' + p)
s = s.replace(a, a + '''
/* USB 2.0 receive settings (LG-USB-2-ETH0, issue #62) */
static int hs_size = 8;
module_param(hs_size, int, 0644);
MODULE_PARM_DESC(hs_size, "USB 2.0 bulk-in size at gigabit, transfers are (hs_size + 2) KB (-1: stock 22)");
static int hs_timer = -1;
module_param(hs_timer, int, 0644);
MODULE_PARM_DESC(hs_timer, "USB 2.0 bulk-in aggregation timer (-1: stock)");
''')
a = '''	ax88179_write_cmd(dev, AX_ACCESS_MAC, AX_RX_BULKIN_QCTRL, 5, 5, tmp);

	dev->rx_urb_size = (1024 * (tmp[3] + 2));
'''
if s.count(a) != 1:
    sys.exit('link_reset bulk-in setup not found in ' + p)
s = s.replace(a, '''	if ((link_sts & AX_USB_HS) && !(link_sts & AX_USB_SS)) {
		int giga = GMII_PHY_PHYSR_GIGA == (tmp16 & GMII_PHY_PHYSR_SMASK);

		if (hs_size >= 1 && hs_size <= 0x30 && (giga || hs_size != 8))
			tmp[3] = hs_size;
		if (hs_timer >= 0 && hs_timer <= 0xffff) {
			tmp[1] = hs_timer & 0xff;
			tmp[2] = (hs_timer >> 8) & 0xff;
		}
		netdev_info(dev->net, "USB 2.0 bulk-in: size %u (%u KB transfers), timer 0x%x\\n",
			    tmp[3], tmp[3] + 2, tmp[1] | (tmp[2] << 8));
	}
''' + a)
open(p, 'w', encoding='utf-8').write(s)
print('ax88179 USB 2.0 settings: added (hs_size 8)')

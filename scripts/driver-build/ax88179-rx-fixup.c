/* ax88179_rx_fixup from Linux 5.4.268 (with "net: usb: ax88179_178a: Fix
 * packet receiving", f8ebb3ac881b), for ax88179-rx-fixup.py.  GPL-2.0, like
 * the driver.  The trailer is read by memcpy, as the old code did. */
static int ax88179_rx_fixup(struct usbnet *dev, struct sk_buff *skb)
{
	struct sk_buff *ax_skb;
	int pkt_cnt;
	u32 rx_hdr;
	u16 hdr_off;
	u32 *pkt_hdr;

	/* At the end of the SKB, there's a header telling us how many packets
	 * are bundled into this buffer and where we can find an array of
	 * per-packet metadata (which contains elements encoded into u16).
	 */

	/* SKB contents for current firmware:
	 *   <packet 1> <padding>
	 *   ...
	 *   <packet N> <padding>
	 *   <per-packet metadata entry 1> <dummy header>
	 *   ...
	 *   <per-packet metadata entry N> <dummy header>
	 *   <padding2> <rx_hdr>
	 *
	 * where:
	 *   <packet N> contains pkt_len bytes:
	 *		2 bytes of IP alignment pseudo header
	 *		packet received
	 *   <per-packet metadata entry N> contains 4 bytes:
	 *		pkt_len and fields AX_RXHDR_*
	 *   <padding>	0-7 bytes to terminate at
	 *		8 bytes boundary (64-bit).
	 *   <padding2> 4 bytes to make rx_hdr terminate at
	 *		8 bytes boundary (64-bit)
	 *   <dummy-header> contains 4 bytes:
	 *		pkt_len=0 and AX_RXHDR_DROP_ERR
	 *   <rx-hdr>	contains 4 bytes:
	 *		pkt_cnt and hdr_off (offset of
	 *		  <per-packet metadata entry 1>)
	 *
	 * pkt_cnt is number of entrys in the per-packet metadata.
	 * In current firmware there is 2 entrys per packet.
	 * The first points to the packet and the
	 *  second is a dummy header.
	 * This was done probably to align fields in 64-bit and
	 *  maintain compatibility with old firmware.
	 * This code assumes that <dummy header> and <padding2> are
	 *  optional.
	 */

	if (skb->len < 4)
		return 0;
	skb_trim(skb, skb->len - 4);
	memcpy(&rx_hdr, skb_tail_pointer(skb), 4);
	le32_to_cpus(&rx_hdr);
	pkt_cnt = (u16)rx_hdr;
	hdr_off = (u16)(rx_hdr >> 16);

	if (pkt_cnt == 0)
		return 0;

	/* Make sure that the bounds of the metadata array are inside the SKB
	 * (and in front of the counter at the end).
	 */
	if (pkt_cnt * 4 + hdr_off > skb->len)
		return 0;
	pkt_hdr = (u32 *)(skb->data + hdr_off);

	/* Packets must not overlap the metadata array */
	skb_trim(skb, hdr_off);

	for (; pkt_cnt > 0; pkt_cnt--, pkt_hdr++) {
		u16 pkt_len_plus_padd;
		u16 pkt_len;

		le32_to_cpus(pkt_hdr);
		pkt_len = (*pkt_hdr >> 16) & 0x1fff;
		pkt_len_plus_padd = (pkt_len + 7) & 0xfff8;

		/* Skip dummy header used for alignment
		 */
		if (pkt_len == 0)
			continue;

		if (pkt_len_plus_padd > skb->len)
			return 0;

		/* Check CRC or runt packet */
		if ((*pkt_hdr & (AX_RXHDR_CRC_ERR | AX_RXHDR_DROP_ERR)) ||
		    pkt_len < 2 + ETH_HLEN) {
			dev->net->stats.rx_errors++;
			skb_pull(skb, pkt_len_plus_padd);
			continue;
		}

		/* last packet */
		if (pkt_len_plus_padd == skb->len) {
			skb_trim(skb, pkt_len);

			/* Skip IP alignment pseudo header */
			skb_pull(skb, 2);

			skb->truesize = SKB_TRUESIZE(pkt_len_plus_padd);
			ax88179_rx_checksum(skb, pkt_hdr);
			return 1;
		}

		ax_skb = skb_clone(skb, GFP_ATOMIC);
		if (!ax_skb)
			return 0;
		skb_trim(ax_skb, pkt_len);

		/* Skip IP alignment pseudo header */
		skb_pull(ax_skb, 2);

		skb->truesize = pkt_len_plus_padd +
				SKB_DATA_ALIGN(sizeof(struct sk_buff));
		ax88179_rx_checksum(ax_skb, pkt_hdr);
		usbnet_skb_return(dev, ax_skb);

		skb_pull(skb, pkt_len_plus_padd);
	}

	return 0;
}

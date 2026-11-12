#!/usr/bin/env python3
"""M23: optional BTIF link knobs (wake pulse / handshake) for the ROM probe."""
import sys

D = "/home/l/m23-btif/"


def sub(path, old, new, count=1):
    p = D + path
    s = open(p).read()
    n = s.count(old)
    if n != count:
        sys.exit("%s: expected %d, found %d" % (path, count, n))
    open(p, "w").write(s.replace(old, new))
    print("%s: patched" % path)


sub("m23_board.h",
    "extern int m23_btif_rxdma_irq;",
    """extern int m23_btif_rxdma_irq;
extern int m23_wak_pulse;
extern int m23_no_handshake;""")

sub("m23_board.c",
    "int m23_selftest;",
    """/* >0: pulse BTIF_WAK once per open (wake the CONNSYS BTIF side). */
int m23_wak_pulse;
module_param(m23_wak_pulse, int, 0444);
MODULE_PARM_DESC(m23_wak_pulse, "T1100: write BTIF_WAK after hw init (wake CONNSYS BTIF)");

/* >0: clear BTIF_HANDSHAKE after hw init (no CTS/RTS flow control). */
int m23_no_handshake;
module_param(m23_no_handshake, int, 0444);
MODULE_PARM_DESC(m23_no_handshake, "T1100: clear BTIF_HANDSHAKE (disable flow control)");

int m23_selftest;""")

sub("btif_plat.c",
    """/*enable Rx IER by default*/
	hal_btif_rx_ier_ctrl(p_btif, true);
""",
    """/*enable Rx IER by default*/
	hal_btif_rx_ier_ctrl(p_btif, true);

	/*
	 * M23 knobs, used to tell "the AP never put the bytes on the wire" from
	 * "the chip does not answer": a WAK pulse asks the CONNSYS BTIF side to
	 * wake up, and clearing HANDSHAKE removes CTS/RTS pacing.
	 */
	if (m23_no_handshake) {
		btif_reg_sync_writel(0, BTIF_HANDSHAKE(base));
		BTIF_INFO_FUNC("m23: handshake disabled\\n");
	}
	if (m23_wak_pulse) {
		btif_reg_sync_writel(BTIF_WAK_BIT, BTIF_WAK(base));
		BTIF_INFO_FUNC("m23: wak pulse sent\\n");
	}
""")

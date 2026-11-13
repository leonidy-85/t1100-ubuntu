#!/usr/bin/env python3
"""M23 part 3: wlan_drv must not power CONNSYS on again when WMT already did."""
import sys

D = "/home/l/t1100-wifi-build/work/wlan/"


def sub(path, old, new, count=1):
    p = D + path
    s = open(p).read()
    n = s.count(old)
    if n != count:
        sys.exit("%s: expected %d, found %d of:\n%s" % (path, count, n, old[:300]))
    open(p, "w").write(s.replace(old, new))
    print("%s: patched" % path)


sub("os/linux/hif/ahb_sdioLike/ahb.c",
    """extern int t1100_probe_stage;""",
    """extern int t1100_probe_stage;

/*
 * T1100 (M23): when wmt_drv has already brought CONSYS up over BTIF/STP
 * (t1100_btif_stp=1 in wmt_drv, which also downloads the ROMv4 patch), the
 * chip must not be powered on a second time: wmt_plat_pwr_ctrl(FUNC_ON) runs
 * the whole CONSYS power-on sequence again, i.e. it resets the MCU and throws
 * the patch away.
 */
int t1100_pwr_on_done;
module_param(t1100_pwr_on_done, int, 0444);
MODULE_PARM_DESC(t1100_pwr_on_done,
		 "T1100: CONSYS is already powered on (and ROM-patched) by wmt_drv");""")

sub("os/linux/hif/ahb_sdioLike/ahb.c",
    """	DBGLOG(INIT, INFO, "t1100_wlan_probe: chip power on\\n");
	ret = wmt_plat_pwr_ctrl(0);	/* ENUM_FUNC_STATE: FUNC_ON */
	DBGLOG(INIT, INFO, "t1100_wlan_probe: wmt_plat_pwr_ctrl(FUNC_ON) = %d\\n", ret);
	if (ret) {
		DBGLOG(INIT, ERROR, "t1100_wlan_probe: chip power on failed\\n");
		return ret;
	}""",
    """	if (t1100_pwr_on_done) {
		DBGLOG(INIT, INFO,
		       "t1100_wlan_probe: CONSYS already up (wmt_drv BTIF STP)\\n");
	} else {
		DBGLOG(INIT, INFO, "t1100_wlan_probe: chip power on\\n");
		ret = wmt_plat_pwr_ctrl(0);	/* ENUM_FUNC_STATE: FUNC_ON */
		DBGLOG(INIT, INFO, "t1100_wlan_probe: wmt_plat_pwr_ctrl(FUNC_ON) = %d\\n", ret);
		if (ret) {
			DBGLOG(INIT, ERROR, "t1100_wlan_probe: chip power on failed\\n");
			return ret;
		}
	}""")

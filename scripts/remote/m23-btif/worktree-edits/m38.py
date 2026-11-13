p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()
if 't1100_stp_reinit_after_patch' not in s:
    s=s.replace('''static int t1100_pwr_cycle_after_patch;''','''static int t1100_stp_reinit_after_patch;
module_param(t1100_stp_reinit_after_patch, int, 0444);
MODULE_PARM_DESC(t1100_stp_reinit_after_patch,
		 "T1100: re-init STP right after the ROMv4 patch (no power cycle) and re-check hwcode");

static int t1100_pwr_cycle_after_patch;''')
    old='''		if (t1100_pwr_cycle_after_patch) {'''
    new='''		if (t1100_stp_reinit_after_patch) {
			ULONG p1, p2;
			INT32 rc1, rc2, rc3, rc4, rc5;
			UINT32 hw = 0;

			/* the patch delivery desyncs STP; re-init it exactly like
			 * wmt_core_stp_init() and see whether the chip answers */
			t1100_patch_active = 0;
			p1 = 0; p2 = 0;
			rc1 = wmt_core_ctrl(WMT_CTRL_STP_CLOSE, &p1, &p2);
			rc2 = wmt_core_ctrl(WMT_CTRL_STP_OPEN, &p1, &p2);
			p1 = WMT_STP_CONF_MODE; p2 = MTKSTP_BTIF_MAND_MODE;
			rc3 = wmt_core_ctrl(WMT_CTRL_STP_CONF, &p1, &p2);
			p1 = WMT_STP_CONF_EN; p2 = 1;
			rc4 = wmt_core_ctrl(WMT_CTRL_STP_CONF, &p1, &p2);
			WMT_INFO_FUNC("t1100: stp reinit (no cycle) close=%d open=%d mode=%d en=%d\\n",
				      rc1, rc2, rc3, rc4);
			rc5 = wmt_core_reg_rw_raw(0, 0x80000008, &hw, 0xffffffff);
			WMT_INFO_FUNC("t1100: hwcode after reinit = 0x%08x (ret %d)\\n", hw, rc5);
			if (t1100_patch_readback)
				t1100_readback("after-reinit");
			t1100_patch_active = 1;	/* keep STP alive for the reset */
		}
		if (t1100_pwr_cycle_after_patch) {'''
    assert s.count(old)==1
    s=s.replace(old,new)
    open(p,'w').write(s)
    print("patched")
else:
    print("already")

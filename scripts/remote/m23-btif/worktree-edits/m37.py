p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()
old='''		if (t1100_pwr_cycle_after_patch) {
			WMT_INFO_FUNC("t1100: power cycle CONSYS after patch\\n");
			wmt_plat_pwr_ctrl(FUNC_OFF);
			osal_sleep_ms(100);
			wmt_plat_pwr_ctrl(FUNC_ON);
			osal_sleep_ms(50);
			WMT_INFO_FUNC("t1100: power cycle done\\n");
		}'''
new='''		if (t1100_pwr_cycle_after_patch) {
			ULONG p1, p2;
			INT32 rc1, rc2, rc3, rc4, rc5;
			UINT32 hw = 0;

			WMT_INFO_FUNC("t1100: power cycle CONSYS after patch\\n");
			wmt_plat_pwr_ctrl(FUNC_OFF);
			osal_sleep_ms(100);
			wmt_plat_pwr_ctrl(FUNC_ON);
			osal_sleep_ms(50);
			WMT_INFO_FUNC("t1100: power cycle done\\n");

			/*
			 * The chip's STP state was reset with the domain; the host
			 * side must be re-initialised exactly like
			 * wmt_core_stp_init() does, otherwise frames go nowhere.
			 * Also stop freezing WMT_STAT_STP_* here.
			 */
			t1100_patch_active = 0;
			p1 = 0; p2 = 0;
			rc1 = wmt_core_ctrl(WMT_CTRL_STP_CLOSE, &p1, &p2);
			rc2 = wmt_core_ctrl(WMT_CTRL_STP_OPEN, &p1, &p2);
			p1 = WMT_STP_CONF_MODE; p2 = MTKSTP_BTIF_MAND_MODE;
			rc3 = wmt_core_ctrl(WMT_CTRL_STP_CONF, &p1, &p2);
			p1 = WMT_STP_CONF_EN; p2 = 1;
			rc4 = wmt_core_ctrl(WMT_CTRL_STP_CONF, &p1, &p2);
			WMT_INFO_FUNC("t1100: stp reinit close=%d open=%d mode=%d en=%d\\n",
				      rc1, rc2, rc3, rc4);

			rc5 = wmt_core_reg_rw_raw(0, 0x80000008, &hw, 0xffffffff);
			WMT_INFO_FUNC("t1100: hwcode after stp reinit = 0x%08x (ret %d)\\n",
				      hw, rc5);
			if (t1100_patch_readback)
				t1100_readback("after-reinit");
		}'''
assert s.count(old)==1
open(p,'w').write(s.replace(old,new))
print("patched")

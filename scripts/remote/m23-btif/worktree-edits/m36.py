p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()
if 't1100_pwr_cycle_after_patch' not in s:
    s=s.replace('''static int t1100_patch_readback;''','''static int t1100_pwr_cycle_after_patch;
module_param(t1100_pwr_cycle_after_patch, int, 0444);
MODULE_PARM_DESC(t1100_pwr_cycle_after_patch,
		 "T1100: power-cycle the CONSYS domain after the ROMv4 patch (hardware restart instead of WMT_RESET)");

static int t1100_patch_readback;''')
    old='''		if (t1100_patch_readback) {
			t1100_readback("after-patch");
			osal_sleep_ms(2000);
			t1100_readback("after-2s");
			iRet = 0;
		}'''
    new='''		if (t1100_pwr_cycle_after_patch) {
			WMT_INFO_FUNC("t1100: power cycle CONSYS after patch\\n");
			wmt_plat_pwr_ctrl(FUNC_OFF);
			osal_sleep_ms(100);
			wmt_plat_pwr_ctrl(FUNC_ON);
			osal_sleep_ms(50);
			WMT_INFO_FUNC("t1100: power cycle done\\n");
		}
		if (t1100_patch_readback) {
			t1100_readback("after-patch");
			osal_sleep_ms(2000);
			t1100_readback("after-2s");
			iRet = 0;
		}'''
    assert s.count(old)==1
    s=s.replace(old,new)
    open(p,'w').write(s)
    print("patched")
else:
    print("already")

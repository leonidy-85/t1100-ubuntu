# 1) global flag in wmt_ctrl.c, guard the assert on RX timeout
p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ctrl.c'
s=open(p).read()
if 't1100_patch_active' not in s:
    s=s.replace('#define WMT_CTRL_DATA_MAX',
                '/* T1100: while the ROMv4 patch is being delivered, an RX timeout must\n'
                ' * not fire the in-band assert: it tears STP down and every retry of the\n'
                ' * next command then fails with -2 before reaching the chip. */\n'
                'int t1100_patch_active;\n#define WMT_CTRL_DATA_MAX', 1)
    s=s.replace('wmt_lib_trigger_assert(WMTDRV_TYPE_WMT, 44);',
                'if (!t1100_patch_active)\n\t\t\t\t\twmt_lib_trigger_assert(WMTDRV_TYPE_WMT, 44);', 1)
    open(p,'w').write(s)
    print("wmt_ctrl.c patched")

# 2) set the flag for the whole sw_init when our patch file is used
p2='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s2=open(p2).read()
if 'extern int t1100_patch_active' not in s2:
    s2=s2.replace('static char t1100_rom_patch[128];',
                  'extern int t1100_patch_active;\nstatic char t1100_rom_patch[128];',1)
    # set right before the download, clear after the reset section
    s2=s2.replace('''	iRet = mtk_wcn_soc_normal_patch_dwn(buf + sizeof(*rh),
					   patchSize - sizeof(*rh),
					   addressByte);''','''	t1100_patch_active = 1;		/* keep STP alive across patch RX timeouts */
	iRet = mtk_wcn_soc_normal_patch_dwn(buf + sizeof(*rh),
					   patchSize - sizeof(*rh),
					   addressByte);''',1)
    s2=s2.replace('''			WMT_ERR_FUNC("init_table_3 fail(%d) after retries\\n", iRet);
			return -8;''','''			WMT_ERR_FUNC("init_table_3 fail(%d) after retries\\n", iRet);
			t1100_patch_active = 0;
			return -8;''',1)
    open(p2,'w').write(s2)
    print("wmt_ic_soc.c patched")

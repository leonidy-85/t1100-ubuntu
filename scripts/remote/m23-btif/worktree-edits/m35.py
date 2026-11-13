# 1) guard wmt_core_trigger_assert while the patch is in flight
p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_core.c'
s=open(p).read()
if 't1100: assert suppressed' not in s:
    old='static INT32 wmt_core_trigger_assert(VOID)\n{'
    new=('extern int t1100_patch_active;\n\nstatic INT32 wmt_core_trigger_assert(VOID)\n{\n'
         '\t/* T1100: do not fire the in-band assert while the ROMv4 patch is\n'
         '\t * being delivered - it leaves the chip unable to serve REG_READ. */\n'
         '\tif (t1100_patch_active) {\n'
         '\t\tWMT_INFO_FUNC("t1100: assert suppressed (patch in flight)\\n");\n'
         '\t\treturn 0;\n\t}\n')
    assert s.count(old)==1
    s=s.replace(old,new)
    open(p,'w').write(s)
    print("wmt_core.c patched")

# 2) readback helper + calls before patch / after patch / after +2s
p2='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s2=open(p2).read()
if 't1100_readback(' not in s2:
    helper='''static void t1100_readback(const char *tag)
{
	UINT32 a, v;
	int k, iRet;

	for (k = 0; k < 3; k++) {
		a = 0x80000000 | (0x00098020 + k * 4);
		v = 0;
		iRet = wmt_core_reg_rw_raw(0, a, &v, 0xffffffff);
		WMT_INFO_FUNC("t1100: %s patchmem[0x%08x] = 0x%08x (ret %d)\\n",
			      tag, a, v, iRet);
		if (iRet)
			break;
	}
	v = 0;
	iRet = wmt_core_reg_rw_raw(0, 0x80000008, &v, 0xffffffff);
	WMT_INFO_FUNC("t1100: %s ctrl GEN_HCR = 0x%08x (ret %d)\\n", tag, v, iRet);
}

'''
    # insert helper right before the multi-patch patch_dwn definition
    anchor='static INT32 mtk_wcn_soc_patch_dwn(UINT32 index)\n{'
    i=s2.index(anchor)
    s2=s2[:i]+helper+s2[i:]

    # call before the patch
    s2=s2.replace('''	t1100_patch_active = 1;		/* keep STP alive across patch RX timeouts */''',
                  '''	if (t1100_patch_readback)
		t1100_readback("before-patch");
	t1100_patch_active = 1;		/* keep STP alive across patch RX timeouts */''',1)

    # replace the old inline readback loop with the helper calls
    old_rb='''		if (t1100_patch_readback) {
			UINT32 a, v;
			int k;

			for (k = 0; k < 8; k++) {
				a = 0x80000000 | (0x00098020 + k * 4);
				v = 0;
				iRet = wmt_core_reg_rw_raw(0, a, &v, 0xffffffff);
				WMT_INFO_FUNC("t1100: patchmem[0x%08x] = 0x%08x (ret %d)\\n",
					      a, v, iRet);
			}
			v = 0;
			iRet = wmt_core_reg_rw_raw(0, 0x80000008, &v, 0xffffffff);
			WMT_INFO_FUNC("t1100: ctrl GEN_HCR = 0x%08x (ret %d)\\n", v, iRet);
			iRet = 0;
		}'''
    new_rb='''		if (t1100_patch_readback) {
			t1100_readback("after-patch");
			osal_sleep_ms(2000);
			t1100_readback("after-2s");
			iRet = 0;
		}'''
    assert s2.count(old_rb)==1, s2.count(old_rb)
    s2=s2.replace(old_rb,new_rb)
    open(p2,'w').write(s2)
    print("wmt_ic_soc.c patched")

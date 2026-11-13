p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()
if 't1100_patch_readback' not in s:
    s=s.replace('''MODULE_PARM_DESC(t1100_skip_reset, "T1100: do not send the post-patch WMT reset (init_table_3)");''',
'''MODULE_PARM_DESC(t1100_skip_reset, "T1100: do not send the post-patch WMT reset (init_table_3)");

/*
 * T1100 (M34): read the patch area back through the WMT REG_READ command
 * (opcode 0x08, the one wmt_core_hw_check() uses) to see whether the ROM kept
 * the ROMv4 patch in its RAM.
 */
static int t1100_patch_readback;
module_param(t1100_patch_readback, int, 0444);
MODULE_PARM_DESC(t1100_patch_readback, "T1100: read back 0x98020.. via WMT REG_READ after the patch");''')
    old='''			WMT_INFO_FUNC("t1100: reset ack: %s\\n", iRet ? "no" : "yes");
			iRet = 0;
		}'''
    new='''			WMT_INFO_FUNC("t1100: reset ack: %s\\n", iRet ? "no" : "yes");
			iRet = 0;
		}
		if (t1100_patch_readback) {
			UINT32 a, v;
			int k;

			for (k = 0; k < 8; k++) {
				a = 0x00098020 + k * 4;
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
    assert s.count(old)==1
    s=s.replace(old,new)
    open(p,'w').write(s)
    print("patched")
else:
    print("already")

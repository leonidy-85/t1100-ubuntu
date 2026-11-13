p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()
if 't1100_skip_reset' not in s:
    s=s.replace('''static char t1100_rom_patch[128];''','''static char t1100_rom_patch[128];''')
    s=s.replace('''MODULE_PARM_DESC(t1100_rom_patch,
		 "T1100: ROMv4 patch file under /lib/firmware (empty = ask userspace)");''','''MODULE_PARM_DESC(t1100_rom_patch,
		 "T1100: ROMv4 patch file under /lib/firmware (empty = ask userspace)");

/*
 * T1100: on MT6771 the ROM does not answer the post-patch WMT reset
 * (opcode 0x07/0x04, rx:0) and the resulting RX timeout tears STP down.  With
 * t1100_skip_reset=1 the reset (init_table_3) is not sent at all so we can see
 * whether the last patch fragment already started the patched code.
 */
static int t1100_skip_reset;
module_param(t1100_skip_reset, int, 0444);
MODULE_PARM_DESC(t1100_skip_reset, "T1100: do not send the post-patch WMT reset (init_table_3)");''')
    # first call site (multi-patch, inside the loop)
    s=s.replace('''		{
			int t1100_i;

			for (t1100_i = 0, iRet = -1; t1100_i < 3 && iRet; t1100_i++) {''','''		if (t1100_skip_reset) {
			WMT_INFO_FUNC("t1100: skip init_table_3 (reset) on request\\n");
			iRet = 0;
		} else {
			int t1100_i;

			for (t1100_i = 0, iRet = -1; t1100_i < 3 && iRet; t1100_i++) {''')
    open(p,'w').write(s)
    print("patched")
else:
    print("already")

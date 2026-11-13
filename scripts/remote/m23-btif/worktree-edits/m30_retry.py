p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()

# 1. let the ROM finish applying the patch before the first WMT command
old='''			WMT_INFO_FUNC("t1100: last fragment sent, ROM jumps (no EVT expected)\\n");
			iRet = 0;
			++fragSeq;
			break;'''
new='''			WMT_INFO_FUNC("t1100: last fragment sent, ROM jumps (no EVT expected)\\n");
			iRet = 0;
			++fragSeq;
			/* give the ROM time to apply the patch before the first
			 * post-patch command (the reset), otherwise it is lost */
			osal_sleep_ms(100);
			break;'''
assert s.count(old)==1
s=s.replace(old,new)

# 2. retry the post-patch reset a few times
old2='''		iRet = wmt_core_init_script(init_table_3, osal_array_size(init_table_3));
		if (iRet) {
			WMT_ERR_FUNC("init_table_3 fail(%d)\\n", iRet);
			return -8;
		}'''
new2='''		/* T1100: the first post-patch command is sometimes swallowed
		 * while the ROM applies the patch; retry it a few times. */
		for (i = 0, iRet = -1; i < 3 && iRet; i++) {
			if (i)
				osal_sleep_ms(200);
			iRet = wmt_core_init_script(init_table_3, osal_array_size(init_table_3));
		}
		if (iRet) {
			WMT_ERR_FUNC("init_table_3 fail(%d) after retries\\n", iRet);
			return -8;
		}'''
assert s.count(old2)==1
s=s.replace(old2,new2)
open(p,'w').write(s)
print("patched")

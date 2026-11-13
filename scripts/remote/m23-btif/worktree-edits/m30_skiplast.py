p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()

# drop the previous tolerance branch (dead once we skip the RX before it)
old_tol = '''		iRet = wmt_core_rx(evtBuf, sizeof(WMT_PATCH_EVT), &u4Res);
		if (iRet || (u4Res != sizeof(WMT_PATCH_EVT))) {
			/*
			 * T1100: after the LAST fragment the ROM applies the
			 * patch and jumps, so no WMT_PATCH_EVT comes back
			 * (observed: 229/230 fragments acked, the 230th times
			 * out).  Treat that as success and let the WMT reset
			 * command in init_table_3 start the patched code.
			 */
			if (fragSeq == fragNum - 1) {
				WMT_INFO_FUNC("t1100: no EVT for the last fragment (ROM jumps), continuing\\n");
				iRet = 0;
				++fragSeq;
				break;
			}
			WMT_ERR_FUNC("wmt_core: read WMT_PATCH_EVT length(%d, %d) fail(%d)\\n", sizeof(WMT_PATCH_EVT),
				     u4Res, iRet);'''
new_tol = '''		/*
		 * T1100: after the LAST fragment the ROM applies the patch and
		 * jumps, so no WMT_PATCH_EVT comes back.  Waiting for it makes
		 * wmt_ctrl_rx time out, wmt_lib_trigger_assert() fires, STP is
		 * torn down and the very next command ("wmt reset",
		 * init_table_3) fails with -2 (wmt_ctrl_tx_ex: "STP is not
		 * enabled yet").  So do not read an EVT for the last fragment.
		 */
		if (fragSeq == fragNum - 1) {
			WMT_INFO_FUNC("t1100: last fragment sent, ROM jumps (no EVT expected)\\n");
			iRet = 0;
			++fragSeq;
			break;
		}

		iRet = wmt_core_rx(evtBuf, sizeof(WMT_PATCH_EVT), &u4Res);
		if (iRet || (u4Res != sizeof(WMT_PATCH_EVT))) {
			WMT_ERR_FUNC("wmt_core: read WMT_PATCH_EVT length(%d, %d) fail(%d)\\n", sizeof(WMT_PATCH_EVT),
				     u4Res, iRet);'''
assert s.count(old_tol)==1, s.count(old_tol)
open(p,'w').write(s.replace(old_tol,new_tol))
print("patched")

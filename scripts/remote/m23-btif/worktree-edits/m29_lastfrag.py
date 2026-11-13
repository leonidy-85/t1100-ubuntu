p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()
old='''		iRet = wmt_core_rx(evtBuf, sizeof(WMT_PATCH_EVT), &u4Res);
		if (iRet || (u4Res != sizeof(WMT_PATCH_EVT))) {
			WMT_ERR_FUNC("wmt_core: read WMT_PATCH_EVT length(%d, %d) fail(%d)\\n", sizeof(WMT_PATCH_EVT),
				     u4Res, iRet);
			mtk_wcn_stp_dbg_dump_package();
			iRet = -1;
			break;
		}'''
new='''		iRet = wmt_core_rx(evtBuf, sizeof(WMT_PATCH_EVT), &u4Res);
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
				break;
			}
			WMT_ERR_FUNC("wmt_core: read WMT_PATCH_EVT length(%d, %d) fail(%d)\\n", sizeof(WMT_PATCH_EVT),
				     u4Res, iRet);
			mtk_wcn_stp_dbg_dump_package();
			iRet = -1;
			break;
		}'''
assert s.count(old)==1
open(p,'w').write(s.replace(old,new))
print("patched")

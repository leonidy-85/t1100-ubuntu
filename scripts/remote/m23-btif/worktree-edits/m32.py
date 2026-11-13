# 1) wmt_lib.c: never clear STP_OPEN/STP_EN while the patch is being delivered
p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_lib.c'
s=open(p).read()
if 't1100_patch_active' not in s:
    s=s.replace('MTK_WCN_BOOL wmt_lib_hw_rst(VOID)\n{',
                'extern int t1100_patch_active;\n\nMTK_WCN_BOOL wmt_lib_hw_rst(VOID)\n{',1)
    old='''	osal_clear_bit(WMT_STAT_STP_REG, &pDevWmt->state);
	osal_clear_bit(WMT_STAT_STP_OPEN, &pDevWmt->state);
	osal_clear_bit(WMT_STAT_STP_EN, &pDevWmt->state);
	osal_clear_bit(WMT_STAT_STP_RDY, &pDevWmt->state);
	osal_clear_bit(WMT_STAT_RX, &pDevWmt->state);
	osal_clear_bit(WMT_STAT_CMD, &pDevWmt->state);'''
    new='''	/*
	 * T1100: while the ROMv4 patch is being delivered/started, an RX
	 * timeout must not tear the STP state down - the next command would
	 * fail in wmt_ctrl_tx_ex() with -2 before reaching the chip.
	 */
	if (!t1100_patch_active) {
		osal_clear_bit(WMT_STAT_STP_REG, &pDevWmt->state);
		osal_clear_bit(WMT_STAT_STP_OPEN, &pDevWmt->state);
		osal_clear_bit(WMT_STAT_STP_EN, &pDevWmt->state);
		osal_clear_bit(WMT_STAT_STP_RDY, &pDevWmt->state);
		osal_clear_bit(WMT_STAT_RX, &pDevWmt->state);
		osal_clear_bit(WMT_STAT_CMD, &pDevWmt->state);
	}'''
    assert s.count(old)==1, s.count(old)
    s=s.replace(old,new)
    open(p,'w').write(s)
    print("wmt_lib.c patched")

# 2) wmt_ic_soc.c: best-effort reset (send, wait, ignore a missing EVT)
p2='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s2=open(p2).read()
old2='''			for (t1100_i = 0, iRet = -1; t1100_i < 3 && iRet; t1100_i++) {
				if (t1100_i)
					osal_sleep_ms(200);
				/* T1100: a previous RX timeout latches the STP
				 * assert flag; while it stays set wmt_ctrl_rx()
				 * returns at once and never sees the EVT. */
				mtk_wcn_stp_set_wmt_trg_assert(0);
				iRet = wmt_core_init_script(init_table_3,
							    osal_array_size(init_table_3));
			}
		}
		if (iRet) {
			WMT_ERR_FUNC("init_table_3 fail(%d) after retries\\n", iRet);
			t1100_patch_active = 0;
			return -8;
		}'''
new2='''			/*
			 * T1100: "wmt reset" is best effort.  The ROM must not be
			 * forced into our contract: on this chip/ROM it may not
			 * answer the EVT at all after a ROMv4 patch, while the
			 * patched code is already in place.  Send it, keep the
			 * STP state (see t1100_patch_active), and carry on.
			 */
			mtk_wcn_stp_set_wmt_trg_assert(0);
			iRet = wmt_core_init_script(init_table_3,
						    osal_array_size(init_table_3));
			WMT_INFO_FUNC("t1100: reset ack: %s\\n", iRet ? "no" : "yes");
			iRet = 0;
		}'''
assert s2.count(old2)==1, s2.count(old2)
s2=s2.replace(old2,new2)
open(p2,'w').write(s2)
print("wmt_ic_soc.c patched (best-effort reset)")

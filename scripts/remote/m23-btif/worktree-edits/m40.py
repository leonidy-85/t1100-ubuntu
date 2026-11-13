p='/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c'
s=open(p).read()
if 't1100_patch_hdr_len' not in s:
    s=s.replace('''static int t1100_stp_reinit_after_patch;''','''/*
 * T1100 (M40): how many bytes of the patch file are container header.  The
 * vendor WMT path only skips sizeof(WMT_PATCH) = 28 (wmt_ic_soc.c:3393),
 * while our file loader used sizeof(struct wmt_rom_patch) = 48.  Both are
 * testable without touching the file.
 */
static int t1100_patch_hdr_len = 48;
module_param(t1100_patch_hdr_len, int, 0444);
MODULE_PARM_DESC(t1100_patch_hdr_len, "T1100: patch container header length to skip (default 48)");

static int t1100_stp_reinit_after_patch;''')
    old='''	iRet = mtk_wcn_soc_normal_patch_dwn(buf + sizeof(*rh),
					   patchSize - sizeof(*rh),
					   addressByte);'''
    new='''	if (patchSize <= (UINT32)t1100_patch_hdr_len) {
		WMT_ERR_FUNC("t1100: patch too small for hdr %d\\n", t1100_patch_hdr_len);
		osal_free(buf);
		return -1;
	}
	iRet = mtk_wcn_soc_normal_patch_dwn(buf + t1100_patch_hdr_len,
					   patchSize - t1100_patch_hdr_len,
					   addressByte);'''
    assert s.count(old)==1
    s=s.replace(old,new)
    open(p,'w').write(s)
    print("patched")
else:
    print("already")

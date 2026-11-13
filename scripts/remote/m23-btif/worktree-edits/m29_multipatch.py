#!/usr/bin/env python3
"""M29: route t1100_rom_patch through the multi-patch (CFG_WMT_MULTI_PATCH) path."""
import re
import sys

p = "/home/l/t1100-wifi-build/work/common/common_main/core/wmt_ic_soc.c"
s = open(p).read()

# --- 1. lift the file loader out of the #else branch -----------------------
start = s.index("/*\n * T1100 (M23): load the ROMv4 patch from /lib/firmware")
end = s.index("static INT32 mtk_wcn_soc_patch_dwn(VOID)\n{", start)
block = s[start:end]
s = s[:start] + s[end:]

anchor = "static INT32 mtk_wcn_soc_patch_dwn(UINT32 index)\n{"
i = s.index(anchor)
s = s[:i] + block + s[i:]
print("moved loader above the multi/non-multi split")

# --- 2. multi variant: use the file when the param is set ------------------
old = """static INT32 mtk_wcn_soc_patch_dwn(UINT32 index)
{
	INT32 iRet = -1;
	P_WMT_PATCH patchHdr = NULL;"""
new = """static INT32 mtk_wcn_soc_patch_dwn(UINT32 index)
{
	INT32 iRet = -1;
	P_WMT_PATCH patchHdr = NULL;

	/* T1100: one ROMv4 patch from /lib/firmware, no userspace launcher */
	if (t1100_rom_patch[0]) {
		if (index)
			return 0;
		return t1100_rom_patch_dwn_file();
	}"""
assert s.count(old) == 1
s = s.replace(old, new)

# --- 3. sw_init: do not ask userspace for the patch list -------------------
old2 = """	patch_num = mtk_wcn_soc_get_patch_num();
	if (patch_num == 0) {
		iRet = mtk_wcn_soc_patch_info_prepare();
		if (iRet) {
			WMT_ERR_FUNC("patch info perpare fail(%d)\\n", iRet);
			return -6;
		}
		patch_num = mtk_wcn_soc_get_patch_num();
	}"""
new2 = """	patch_num = mtk_wcn_soc_get_patch_num();
	if (patch_num == 0) {
		if (t1100_rom_patch[0]) {
			/* T1100: the patch comes from /lib/firmware, not from
			 * the (absent) userspace launcher's srh_patch. */
			patch_num = 1;
		} else {
			iRet = mtk_wcn_soc_patch_info_prepare();
			if (iRet) {
				WMT_ERR_FUNC("patch info perpare fail(%d)\\n", iRet);
				return -6;
			}
			patch_num = mtk_wcn_soc_get_patch_num();
		}
	}"""
assert s.count(old2) == 1
s = s.replace(old2, new2)

open(p, "w").write(s)
print("patched multi-patch path")

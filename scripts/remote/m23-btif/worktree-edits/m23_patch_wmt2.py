#!/usr/bin/env python3
"""M23 part 2: wmt_ic_soc.c ROMv4 patch from /lib/firmware."""
import sys

D = "/home/l/t1100-wifi-build/work/common/"


def sub(path, old, new, count=1):
    p = D + path
    s = open(p).read()
    n = s.count(old)
    if n != count:
        sys.exit("%s: expected %d, found %d of:\n%s" % (path, count, n, old[:300]))
    open(p, "w").write(s.replace(old, new))
    print("%s: patched" % path)


sub("common_main/core/wmt_ic_soc.c",
    '#define DFT_TAG         "[WMT-IC]"',
    '''#define DFT_TAG         "[WMT-IC]"

/*
 * T1100 (M23): the ROMv4 patch for this chip (icId 0x0788) is delivered over
 * STP ("ROMv4 patch RAM base", mtk_wcn_soc_normal_patch_dwn()), and the vendor
 * launcher picks the file and its address from userspace.  Without a launcher
 * the kernel reads the file itself; an empty name keeps the vendor path.
 */
#include <linux/firmware.h>

static char t1100_rom_patch[128];
module_param_string(t1100_rom_patch, t1100_rom_patch,
		    sizeof(t1100_rom_patch), 0444);
MODULE_PARM_DESC(t1100_rom_patch,
		 "T1100: ROMv4 patch file under /lib/firmware (empty = ask userspace)");''')

sub("common_main/core/wmt_ic_soc.c",
    """static INT32 mtk_wcn_soc_patch_dwn(VOID)
{
	INT32 iRet = -1;
	P_WMT_PATCH patchHdr;
	PUINT8 pbuf;""",
    """/*
 * T1100 (M23): load the ROMv4 patch from /lib/firmware and hand the body to
 * the vendor downloader.  The file header is struct wmt_rom_patch (48 bytes:
 * date, platform, hw/sw version, u4PatchAddr, u4PatchType, CRC) -- the same
 * layout the vendor userspace parser reads; the body starts at offset 48 and
 * the first 28 bytes (WMT_PATCH) are kept for the version check.
 */
static INT32 t1100_rom_patch_dwn_file(VOID)
{
	const struct firmware *fw = NULL;
	struct wmt_rom_patch *rh;
	PUINT8 buf = NULL;
	UINT8 addressByte[4];
	UINT32 patchSize;
	INT32 iRet;

	iRet = request_firmware(&fw, t1100_rom_patch, NULL);
	if (iRet) {
		WMT_ERR_FUNC("t1100: request_firmware(%s) failed:%d\\n",
			     t1100_rom_patch, iRet);
		return iRet;
	}
	if (fw->size <= sizeof(*rh)) {
		WMT_ERR_FUNC("t1100: patch file too small (%zu)\\n", fw->size);
		release_firmware(fw);
		return -1;
	}
	buf = osal_malloc(fw->size);
	if (!buf) {
		release_firmware(fw);
		return -ENOMEM;
	}
	osal_memcpy(buf, fw->data, fw->size);
	patchSize = fw->size;
	release_firmware(fw);

	rh = (struct wmt_rom_patch *)buf;
	WMT_INFO_FUNC("t1100: patch %s size=%u plat=%c%c%c%c hw=0x%04x sw=0x%04x addr=0x%08x type=0x%08x\\n",
		      t1100_rom_patch, patchSize, rh->ucPLat[0], rh->ucPLat[1],
		      rh->ucPLat[2], rh->ucPLat[3], rh->u2HwVer, rh->u2SwVer,
		      rh->u4PatchAddr, rh->u4PatchType);

	osal_memcpy(&gp_soc_patch_info, rh, osal_sizeof(WMT_PATCH));
	addressByte[0] = rh->u4PatchAddr & 0xff;
	addressByte[1] = (rh->u4PatchAddr >> 8) & 0xff;
	addressByte[2] = (rh->u4PatchAddr >> 16) & 0xff;
	addressByte[3] = (rh->u4PatchAddr >> 24) & 0xff;

	iRet = mtk_wcn_soc_normal_patch_dwn(buf + sizeof(*rh),
					   patchSize - sizeof(*rh),
					   addressByte);
	WMT_INFO_FUNC("t1100: ROMv4 patch download -> %d\\n", iRet);
	osal_free(buf);
	return iRet;
}

static INT32 mtk_wcn_soc_patch_dwn(VOID)
{
	INT32 iRet = -1;
	P_WMT_PATCH patchHdr;
	PUINT8 pbuf;

	/* T1100: ROMv4 patch from /lib/firmware (M23) */
	if (t1100_rom_patch[0])
		return t1100_rom_patch_dwn_file();
""")

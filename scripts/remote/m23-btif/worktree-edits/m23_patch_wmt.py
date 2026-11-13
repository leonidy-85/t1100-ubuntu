#!/usr/bin/env python3
"""M23: wmt_drv side of the BTIF/STP transport (applied to the patched work tree).

  wmt_dev.c      t1100_btif_stp param: at WMT_init, select STP over BTIF,
                 run HIF_CONF and POWER_ON (which opens STP and downloads the
                 ROMv4 patch through mtk_wcn_soc_sw_init()).
  wmt_ic_soc.c   t1100_rom_patch param: when set, take the ROMv4 patch from
                 /lib/firmware instead of asking userspace "srh_patch".
"""
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


# ------------------------------------------------------------------ wmt_dev.c
sub("common_main/linux/wmt_dev.c",
    """#define WMT_DRIVER_NAME "mtk_stp_wmt\"""",
    """#define WMT_DRIVER_NAME "mtk_stp_wmt"

/*
 * T1100 (M23): bring the STP transport up over BTIF from the kernel.
 *
 * The vendor flow leaves this to the userspace launcher: WMT_IOCTL_SET_STP_MODE
 * (wmt_lib_set_hif + WMT_OPID_HIF_CONF) followed by a power on, which runs
 * wmt_core_stp_init() -> mtk_wcn_soc_sw_init() -> ROMv4 patch download.  There
 * is no launcher in this port, and the BTIF transport on MT6771 is only
 * reachable through those WMT operations, so the same two operations are
 * issued here once WMT_init() has created the device and the WMT thread.
 * t1100_btif_stp=0 keeps the old behaviour (wlan_drv powers the chip on).
 */
int t1100_btif_stp;
module_param(t1100_btif_stp, int, 0444);
MODULE_PARM_DESC(t1100_btif_stp,
		 "T1100: select STP over BTIF and power CONNSYS on at WMT_init (ROM patch download)");

static void t1100_btif_boot_work(struct work_struct *work);
static DECLARE_DELAYED_WORK(t1100_btif_boot_dw, t1100_btif_boot_work);""")

sub("common_main/linux/wmt_dev.c",
    """static INT32 WMT_init(VOID)
{""",
    """static void t1100_btif_boot_work(struct work_struct *work)
{
	P_OSAL_OP pOp;
	MTK_WCN_BOOL bRet;

	WMT_INFO_FUNC("t1100: STP over BTIF: hif conf\\n");
	if (wmt_lib_set_hif(STP_BTIF_FULL)) {
		WMT_ERR_FUNC("t1100: wmt_lib_set_hif(STP_BTIF_FULL) failed\\n");
		return;
	}

	pOp = wmt_lib_get_free_op();
	if (!pOp) {
		WMT_ERR_FUNC("t1100: no free op for HIF_CONF\\n");
		return;
	}
	osal_memcpy(&pOp->op.au4OpData[0], wmt_lib_get_hif(),
		    sizeof(WMT_HIF_CONF));
	pOp->op.opId = WMT_OPID_HIF_CONF;
	pOp->op.u4InfoBit = WMT_OP_HIF_BIT;
	pOp->signal.timeoutValue = 5000;
	bRet = wmt_lib_put_act_op(pOp);
	WMT_INFO_FUNC("t1100: WMT_OPID_HIF_CONF -> %d\\n", bRet);

	pOp = wmt_lib_get_free_op();
	if (!pOp) {
		WMT_ERR_FUNC("t1100: no free op for PWR_ON\\n");
		return;
	}
	pOp->op.opId = WMT_OPID_PWR_ON;
	pOp->op.u4InfoBit = 0;
	/* patch download + WMT reset run inside this op */
	pOp->signal.timeoutValue = 60000;
	bRet = wmt_lib_put_act_op(pOp);
	WMT_INFO_FUNC("t1100: WMT_OPID_PWR_ON (BTIF STP, ROM patch) -> %d\\n",
		      bRet);
}

static INT32 WMT_init(VOID)
{""")

sub("common_main/linux/wmt_dev.c",
    """#if (MTK_WCN_REMOVE_KO)
	/* called in do_common_drv_init() */
#else
	mtk_wcn_stp_uart_drv_init();
	mtk_wcn_stp_sdio_drv_init();
#endif

	return 0;""",
    """#if (MTK_WCN_REMOVE_KO)
	/* called in do_common_drv_init() */
#else
	mtk_wcn_stp_uart_drv_init();
	mtk_wcn_stp_sdio_drv_init();
#endif

	if (t1100_btif_stp) {
		WMT_INFO_FUNC("t1100: scheduling BTIF STP bring-up\\n");
		schedule_delayed_work(&t1100_btif_boot_dw,
				      msecs_to_jiffies(500));
	}

	return 0;""")

# -------------------------------------------------------------- wmt_ic_soc.c
sub("common_main/core/wmt_ic_soc.c",
    """#define DFT_TAG         "[WMT-IC]\"""",
    """#define DFT_TAG         "[WMT-IC]"

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
		 "T1100: ROMv4 patch file under /lib/firmware (empty = ask userspace)");""")

sub("common_main/core/wmt_ic_soc.c",
    """static INT32 mtk_wcn_soc_patch_dwn(VOID)
{
	INT32 iRet = -1;
	P_WMT_PATCH patchHdr;
	PUINT8 pbuf;""",
    """/*
 * T1100 (M23): load the ROMv4 patch from /lib/firmware and hand it to the
 * vendor downloader.  The file header is struct wmt_rom_patch (48 bytes:
 * date, platform, hw/sw version, u4PatchAddr, u4PatchType, CRC), which is what
 * the vendor userspace parser reads as well; the 28-byte WMT_PATCH prefix is
 * what mtk_wcn_soc_normal_patch_dwn() expects to strip, so the body is handed
 * over from offset 48 and the first 28 bytes are saved for the version check.
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

	if (t1100_rom_patch[0])
		return t1100_rom_patch_dwn_file();
""")

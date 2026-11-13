// SPDX-License-Identifier: GPL-2.0
/*
 * wmt-loader -- минимальный загрузчик вендорского connectivity-стека MTK.
 *
 * Зачем он нужен. В модульной сборке стека (наш случай: wmt_drv.ko +
 * wlan_drv_gen3.ko) единственный module_init во всём дереве common -- это
 * wmt_detect_driver_init(): он только создаёт /dev/wmtdetect. Ядро WMT
 * (WMT_init() в common_main/linux/wmt_dev.c) в этом режиме никто не вызывает:
 *
 *	wmt_detect.c, COMBO_IOCTL_DO_MODULE_INIT:
 *	#else /* kernel object mode *\/
 *		retval = mtk_wcn_common_drv_init();      <- вот это
 *
 * А на Android его дёргает userspace `wmt_loader` (открыл /dev/wmtdetect,
 * ioctl SET_CHIP_ID, ioctl DO_MODULE_INIT). У нас такого загрузчика нет, поэтому
 * без этой программы WMT не стартует вообще: нет /dev/stpwmt, нет wmt_lib_init,
 * не регистрируется platform-драйвер "mediatek,mt6771-consys" и CONSYS-чип
 * остаётся выключенным (см. docs/wifi-port-log.md, M27).
 *
 * Порядок (вендорный):
 *	1. open /dev/wmtdetect
 *	2. ioctl COMBO_IOCTL_SET_CHIP_ID, аргумент 0x6771 по значению
 *	   (wmt_detect_unlocked_ioctl читает `arg` напрямую, не копирует из
 *	   userspace!). Вендорский драйвер считает combo только 0x6620/0x6628/
 *	   0x6630/0x6632, всё прочее -- SOC; MT6771 = CONSYS_6771 = SOC.
 *	3. ioctl COMBO_IOCTL_DO_MODULE_INIT -> mtk_wcn_common_drv_init()
 *
 * После шага 3 появляются /dev/stpwmt и (если DT и питание в порядке) строка
 * "consys chipId(0x788)" в dmesg.
 *
 * Сборка (build-хост, статически, как остальные утилиты для планшета):
 *	aarch64-linux-gnu-gcc -O2 -static -o wmt-loader wmt-loader.c
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define WMT_DETECT_IOC_MAGIC 'w'
#define COMBO_IOCTL_SET_CHIP_ID _IOW(WMT_DETECT_IOC_MAGIC, 1, int)
#define COMBO_IOCTL_DO_MODULE_INIT _IOR(WMT_DETECT_IOC_MAGIC, 4, int)

#define WMT_DEV_DETECT "/dev/wmtdetect"
#define WMT_DEV_STP "/dev/stpwmt"
#define MT6771_CHIP_ID 0x6771

int main(void)
{
	int fd;
	int ret = 1;

	fd = open(WMT_DEV_DETECT, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "wmt-loader: open %s: %s\n", WMT_DEV_DETECT,
			strerror(errno));
		fprintf(stderr, "wmt-loader: is wmt_drv.ko loaded?\n");
		return 1;
	}

	/* _IOW, но драйвер читает arg по значению (wmt_detect.c:90). */
	if (ioctl(fd, COMBO_IOCTL_SET_CHIP_ID, (unsigned long)MT6771_CHIP_ID) < 0) {
		fprintf(stderr, "wmt-loader: COMBO_IOCTL_SET_CHIP_ID(0x%x): %s\n",
			MT6771_CHIP_ID, strerror(errno));
		goto out;
	}
	printf("wmt-loader: chip id 0x%x set\n", MT6771_CHIP_ID);

	/* Здесь ядро WMT стартует: wmt_lib_init -> wmt_plat_init -> (SOC)
	 * mtk_wcn_consys_hw_init -> platform_driver_register("mtk_wmt"),
	 * probe -> питание CONSYS -> ROM patch -> polling chip id 0x788. */
	if (ioctl(fd, COMBO_IOCTL_DO_MODULE_INIT, 0) < 0) {
		fprintf(stderr, "wmt-loader: COMBO_IOCTL_DO_MODULE_INIT: %s\n",
			strerror(errno));
		goto out;
	}
	printf("wmt-loader: DO_MODULE_INIT ok\n");

	if (access(WMT_DEV_STP, F_OK) == 0)
		printf("wmt-loader: %s появился, WMT-ядро поднялось\n",
		       WMT_DEV_STP);
	else
		printf("wmt-loader: %s пока нет -- смотри dmesg (wmt/consys)\n",
		       WMT_DEV_STP);

	ret = 0;
out:
	close(fd);
	return ret;
}

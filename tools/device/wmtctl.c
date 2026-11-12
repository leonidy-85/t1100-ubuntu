/* wmtctl - minimal userspace replacement for the vendor `wmt_loader`.
 *
 * The vendor connectivity stack leaves the chip type INVALID until userspace
 * tells it what it is: /dev/wmtdetect + COMBO_IOCTL_SET_CHIP_ID (0x6771 -> SOC,
 * see wmt_detect_set_chip_type()) and then COMBO_IOCTL_DO_MODULE_INIT, which
 * runs mtk_wcn_common_drv_init(): power-on of the CONSYS block and the
 * firmware download.
 *
 * Usage:
 *   wmtctl detect          # COMBO_IOCTL_GET_SOC_CHIP_ID  (expects 0x6771)
 *   wmtctl setid [ID]      # COMBO_IOCTL_SET_CHIP_ID     (default 0x6771)
 *   wmtctl init            # COMBO_IOCTL_DO_MODULE_INIT  (power on + fw)
 *   wmtctl cleanup         # COMBO_IOCTL_MODULE_CLEANUP  (sdio detect exit)
 *   wmtctl poweron|poweroff # COMBO_IOCTL_EXT_CHIP_PWR_ON / _OFF
 *
 * All ioctls are ioctl(2) numbers from wmt_detect.h (magic 'w').
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define WMT_DETECT_IOC_MAGIC 'w'
#define COMBO_IOCTL_GET_CHIP_ID _IOR(WMT_DETECT_IOC_MAGIC, 0, int)
#define COMBO_IOCTL_SET_CHIP_ID _IOW(WMT_DETECT_IOC_MAGIC, 1, int)
#define COMBO_IOCTL_EXT_CHIP_DETECT _IOR(WMT_DETECT_IOC_MAGIC, 2, int)
#define COMBO_IOCTL_GET_SOC_CHIP_ID _IOR(WMT_DETECT_IOC_MAGIC, 3, int)
#define COMBO_IOCTL_DO_MODULE_INIT _IOR(WMT_DETECT_IOC_MAGIC, 4, int)
#define COMBO_IOCTL_MODULE_CLEANUP _IOR(WMT_DETECT_IOC_MAGIC, 5, int)
#define COMBO_IOCTL_EXT_CHIP_PWR_ON _IOR(WMT_DETECT_IOC_MAGIC, 6, int)
#define COMBO_IOCTL_EXT_CHIP_PWR_OFF _IOR(WMT_DETECT_IOC_MAGIC, 7, int)

#define DEV "/dev/wmtdetect"

static int open_dev(void)
{
	int fd = open(DEV, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "%s: %s (модуль wmt_drv загружен?)\n", DEV,
			strerror(errno));
	}
	return fd;
}

int main(int argc, char **argv)
{
	const char *cmd = argc > 1 ? argv[1] : "help";
	int fd = open_dev();
	int rc = 0;

	if (fd < 0)
		return 1;

	if (!strcmp(cmd, "detect")) {
		long id = ioctl(fd, COMBO_IOCTL_GET_SOC_CHIP_ID, 0);
		if (id < 0) {
			fprintf(stderr, "GET_SOC_CHIP_ID: %s\n", strerror(errno));
			rc = 1;
		} else {
			printf("soc chip id: 0x%lx\n", id);
		}
	} else if (!strcmp(cmd, "setid")) {
		long id = argc > 2 ? strtol(argv[2], NULL, 0) : 0x6771;
		if (ioctl(fd, COMBO_IOCTL_SET_CHIP_ID, id) < 0) {
			fprintf(stderr, "SET_CHIP_ID(0x%lx): %s\n", id, strerror(errno));
			rc = 1;
		} else {
			printf("chip id set to 0x%lx (SOC)\n", id);
		}
	} else if (!strcmp(cmd, "init")) {
		if (ioctl(fd, COMBO_IOCTL_DO_MODULE_INIT, 0) < 0) {
			fprintf(stderr, "DO_MODULE_INIT: %s\n", strerror(errno));
			rc = 1;
		} else {
			printf("module init ok (power on + firmware)\n");
		}
	} else if (!strcmp(cmd, "cleanup")) {
		if (ioctl(fd, COMBO_IOCTL_MODULE_CLEANUP, 0) < 0) {
			fprintf(stderr, "MODULE_CLEANUP: %s\n", strerror(errno));
			rc = 1;
		}
	} else if (!strcmp(cmd, "poweron")) {
		rc = ioctl(fd, COMBO_IOCTL_EXT_CHIP_PWR_ON, 0) < 0;
	} else if (!strcmp(cmd, "poweroff")) {
		rc = ioctl(fd, COMBO_IOCTL_EXT_CHIP_PWR_OFF, 0) < 0;
	} else if (!strcmp(cmd, "extdetect")) {
		rc = ioctl(fd, COMBO_IOCTL_EXT_CHIP_DETECT, 0) < 0;
	} else {
		printf("usage: %s detect|setid [ID]|init|cleanup|poweron|poweroff|extdetect\n", argv[0]);
		rc = 2;
	}
	close(fd);
	return rc;
}

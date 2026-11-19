// SPDX-License-Identifier: GPL-2.0
/* Exercise the vendor HW-lock + power ioctl path with hw_power=0. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define MFV_IOC_MAGIC 'M'
#define VCODEC_LOCKHW			_IOW(MFV_IOC_MAGIC, 0x0d, unsigned int)
#define VCODEC_UNLOCKHW			_IOW(MFV_IOC_MAGIC, 0x33, unsigned int)
#define VCODEC_INC_PWR_USER		_IOW(MFV_IOC_MAGIC, 0x27, unsigned int)
#define VCODEC_DEC_PWR_USER		_IOW(MFV_IOC_MAGIC, 0x28, unsigned int)

struct val_hw_lock {
	void *pvHandle;
	unsigned int u4HandleSize;
	void *pvLock;
	unsigned int u4TimeoutMs;
	void *pvReserved;
	unsigned int u4ReservedSize;
	int eDriverType;     /* VAL_DRIVER_TYPE_H264_DEC = 6 */
	char bSecureInst;
	char pad[3];
};

struct val_power {
	void *pvHandle;
	unsigned int u4HandleSize;
	int eDriverType;
	char fgEnable;
	char pad[3];
	void *pvReserved;
	unsigned int u4ReservedSize;
};

static unsigned char handle_buf[4096];

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "/dev/Vcodec";
	struct val_hw_lock hl;
	struct val_power pw;
	int fd;
	long r;

	fd = open(path, O_RDWR);
	if (fd < 0) {
		perror("open");
		return 2;
	}

	memset(&hl, 0, sizeof(hl));
	hl.pvHandle = handle_buf;
	hl.u4HandleSize = sizeof(handle_buf);
	hl.u4TimeoutMs = 100;
	hl.eDriverType = 6; /* H264_DEC */
	hl.bSecureInst = 0;

	memset(&pw, 0, sizeof(pw));
	pw.pvHandle = handle_buf;
	pw.u4HandleSize = sizeof(handle_buf);
	pw.eDriverType = 6;

	r = ioctl(fd, VCODEC_INC_PWR_USER, &pw);
	printf("INC_PWR_USER  -> %ld errno=%d\n", r, r < 0 ? errno : 0);

	r = ioctl(fd, VCODEC_LOCKHW, &hl);
	printf("LOCKHW        -> %ld errno=%d\n", r, r < 0 ? errno : 0);
	if (r < 0) {
		close(fd);
		return 1;
	}

	r = ioctl(fd, VCODEC_UNLOCKHW, &hl);
	printf("UNLOCKHW      -> %ld errno=%d\n", r, r < 0 ? errno : 0);

	r = ioctl(fd, VCODEC_DEC_PWR_USER, &pw);
	printf("DEC_PWR_USER  -> %ld errno=%d\n", r, r < 0 ? errno : 0);

	close(fd);
	return 0;
}

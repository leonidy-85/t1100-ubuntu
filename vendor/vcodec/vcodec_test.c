// SPDX-License-Identifier: GPL-2.0
/* Minimal ABI smoke test for the ported vendor Vcodec char driver. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define MFV_IOC_MAGIC 'M'
#define MFV_TEST_CMD			_IO(MFV_IOC_MAGIC, 0x00)
#define MFV_INIT_CMD			_IO(MFV_IOC_MAGIC, 0x01)
#define MFV_DEINIT_CMD			_IO(MFV_IOC_MAGIC, 0x02)
#define MFV_SET_CMD_CMD			_IOW(MFV_IOC_MAGIC, 0x03, unsigned int)
#define MFV_SET_PWR_CMD			_IOW(MFV_IOC_MAGIC, 0x04, unsigned int)
#define MFV_SET_ISR_CMD			_IOW(MFV_IOC_MAGIC, 0x05, unsigned int)
#define VCODEC_LOCKHW			_IOW(MFV_IOC_MAGIC, 0x0d, unsigned int)
#define VCODEC_INC_PWR_USER		_IOW(MFV_IOC_MAGIC, 0x27, unsigned int)
#define VCODEC_DEC_PWR_USER		_IOW(MFV_IOC_MAGIC, 0x28, unsigned int)
#define VCODEC_INITHWLOCK		_IOW(MFV_IOC_MAGIC, 0x20, unsigned int)
#define VCODEC_DEINITHWLOCK		_IOW(MFV_IOC_MAGIC, 0x21, unsigned int)
#define VCODEC_GET_CORE_NUMBER		_IOW(MFV_IOC_MAGIC, 0x31, unsigned int)
#define VCODEC_MB			_IOW(MFV_IOC_MAGIC, 0x34, unsigned int)

static int failures;

static void check(const char *name, long ret)
{
	int err = errno;

	printf("%-24s -> %ld (errno=%d %s)\n", name, ret,
	       ret < 0 ? err : 0, ret < 0 ? strerror(err) : "ok");
	if (ret < 0)
		failures++;
}

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "/dev/Vcodec";
	unsigned int pwr = 1, zero = 0, n = 0;
	int fd;
	long r;

	fd = open(path, O_RDWR);
	if (fd < 0) {
		printf("open(%s) failed: %s\n", path, strerror(errno));
		return 2;
	}
	printf("opened %s\n", path);

	r = ioctl(fd, MFV_TEST_CMD);                 check("MFV_TEST_CMD", r);
	r = ioctl(fd, MFV_INIT_CMD);                 check("MFV_INIT_CMD", r);
	r = ioctl(fd, MFV_SET_CMD_CMD, &zero);       check("MFV_SET_CMD_CMD", r);
	r = ioctl(fd, MFV_SET_PWR_CMD, &pwr);        check("MFV_SET_PWR_CMD(1)", r);
	r = ioctl(fd, MFV_SET_PWR_CMD, &zero);       check("MFV_SET_PWR_CMD(0)", r);
	r = ioctl(fd, MFV_SET_ISR_CMD, &zero);       check("MFV_SET_ISR_CMD", r);
	r = ioctl(fd, VCODEC_INITHWLOCK, &zero);     check("VCODEC_INITHWLOCK", r);
	r = ioctl(fd, VCODEC_DEINITHWLOCK, &zero);   check("VCODEC_DEINITHWLOCK", r);
	r = ioctl(fd, VCODEC_GET_CORE_NUMBER, &n);   check("VCODEC_GET_CORE_NUMBER", r);
	printf("  core_number=%u\n", n);
	r = ioctl(fd, VCODEC_MB, &zero);             check("VCODEC_MB", r);
	r = ioctl(fd, MFV_DEINIT_CMD);               check("MFV_DEINIT_CMD", r);

	/* Unknown command must not crash. */
	r = ioctl(fd, _IO(MFV_IOC_MAGIC, 0x7e));     check("unknown ioctl", r);

	close(fd);
	printf("%s: %d failure(s)\n", failures ? "FAIL" : "PASS", failures);
	return failures ? 1 : 0;
}

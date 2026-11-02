/* i2cpeek — read/write IT6112 bridge registers from the T1100 rootfs.
 *
 * i2c-tools are not installed there and there is no network to install them,
 * so this tiny static helper does register reads/writes with I2C_RDWR.
 *
 * Build: aarch64-linux-gnu-gcc -O2 -static -o i2cpeek i2cpeek.c
 * Usage:
 *   ./i2cpeek 3 0x56 0x02          # read one byte
 *   ./i2cpeek 3 0x56 0x02 4        # read 4 bytes from reg 0x02
 *   ./i2cpeek -w 3 0x56 0x73 0x11  # write one byte
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int xfer(int fd, uint8_t reg, uint8_t *buf, int len, int write)
{
	struct i2c_msg msgs[2];
	uint8_t r = reg;
	msgs[0].addr = 0; msgs[0].flags = 0; msgs[0].len = 1; msgs[0].buf = &r;
	msgs[1].addr = 0;
	msgs[1].flags = write ? 0 : I2C_M_RD;
	msgs[1].len = len;
	msgs[1].buf = buf;
	struct i2c_rdwr_ioctl_data d = { .msgs = msgs, .nmsgs = write ? 2 : 2 };
	return ioctl(fd, I2C_RDWR, &d) < 0 ? -errno : 0;
}

int main(int argc, char **argv)
{
	int w = 0, ai = 1;
	if (argc > 1 && !strcmp(argv[1], "-w")) { w = 1; ai = 2; }
	if (argc < ai + 3) {
		fprintf(stderr, "usage: %s [-w] <bus> <addr> <reg> [len|value]\n", argv[0]);
		return 2;
	}
	int bus = strtol(argv[ai], NULL, 0);
	unsigned addr = strtol(argv[ai + 1], NULL, 0);
	unsigned reg = strtol(argv[ai + 2], NULL, 0);
	char path[32];
	snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
	int fd = open(path, O_RDWR);
	if (fd < 0) { perror(path); return 1; }

	if (w) {
		uint8_t v = (uint8_t)strtol(argv[ai + 3], NULL, 0);
		struct i2c_msg m[2];
		uint8_t b[2] = { (uint8_t)reg, v };
		m[0].addr = addr; m[0].flags = 0; m[0].len = 2; m[0].buf = b;
		struct i2c_rdwr_ioctl_data d = { .msgs = m, .nmsgs = 1 };
		if (ioctl(fd, I2C_RDWR, &d) < 0) { perror("I2C_RDWR"); return 1; }
		printf("wrote %02x=%02x\n", reg, v);
		return 0;
	}

	int len = argc > ai + 3 ? (int)strtol(argv[ai + 3], NULL, 0) : 1;
	uint8_t buf[256];
	if (len < 1 || len > (int)sizeof(buf)) return 2;

	/* one transaction: reg pointer + read */
	struct i2c_msg m[2];
	uint8_t r = (uint8_t)reg;
	m[0].addr = addr; m[0].flags = 0; m[0].len = 1; m[0].buf = &r;
	m[1].addr = addr; m[1].flags = I2C_M_RD; m[1].len = len; m[1].buf = buf;
	struct i2c_rdwr_ioctl_data d = { .msgs = m, .nmsgs = 2 };
	if (ioctl(fd, I2C_RDWR, &d) < 0) { perror("I2C_RDWR"); return 1; }
	for (int i = 0; i < len; i++)
		printf("%02x:%02x%s", reg + i, buf[i], (i + 1) % 8 ? " " : "\n");
	printf("\n");
	return 0;
}

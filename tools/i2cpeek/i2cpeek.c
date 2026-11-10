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
 *   ./i2cpeek -W 3 0x56 0x00 0x900000d0 4   # write 4-byte LE value to reg
 *   ./i2cpeek -ahb 0 0x48 0x900000d0 4      # Himax AHB indirect read (4 bytes)
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

/* Write reg byte + len bytes of value, little-endian (regmap val_bits=32). */
static int write_reg32(int fd, unsigned addr, unsigned reg, unsigned val, int n)
{
	uint8_t b[5];
	struct i2c_msg m;
	struct i2c_rdwr_ioctl_data d = { .msgs = &m, .nmsgs = 1 };

	if (n < 1 || n > 4) return -1;
	b[0] = (uint8_t)reg;
	for (int i = 0; i < n; i++)
		b[1 + i] = (uint8_t)(val >> (8 * i));
	m.addr = addr; m.flags = 0; m.len = 1 + n; m.buf = b;
	return ioctl(fd, I2C_RDWR, &d) < 0 ? -errno : 0;
}

static int read_reg(int fd, unsigned addr, unsigned reg, uint8_t *buf, int len)
{
	struct i2c_msg m[2];
	uint8_t r = (uint8_t)reg;
	m[0].addr = addr; m[0].flags = 0; m[0].len = 1; m[0].buf = &r;
	m[1].addr = addr; m[1].flags = I2C_M_RD; m[1].len = len; m[1].buf = buf;
	struct i2c_rdwr_ioctl_data d = { .msgs = m, .nmsgs = 2 };
	return ioctl(fd, I2C_RDWR, &d) < 0 ? -errno : 0;
}

/*
 * Same sequence as drivers/input/touchscreen/himax_hx83112b.c:
 *   reg 0x13 = 0x31 / reg 0x0d = 0x10   (burst mode, only when len > 4)
 *   reg 0x00 = AHB address (32-bit LE)
 *   reg 0x0c = 0x00                     (access direction = read)
 *   read len bytes starting at reg 0x08
 */
static int himax_ahb_read(int fd, unsigned addr, unsigned ahb,
			  uint8_t *buf, int len)
{
	int err;

	if (len > 4) {
		if ((err = write_reg32(fd, addr, 0x13, 0x31, 4))) return err;
		if ((err = write_reg32(fd, addr, 0x0d, 0x10, 4))) return err;
	}
	if ((err = write_reg32(fd, addr, 0x00, ahb, 4))) return err;
	if ((err = write_reg32(fd, addr, 0x0c, 0x00, 4))) return err;
	return read_reg(fd, addr, 0x08, buf, len);
}

int main(int argc, char **argv)
{
	int w = 0, W = 0, ahbm = 0, ai = 1;
	if (argc > 1 && !strcmp(argv[1], "-w")) { w = 1; ai = 2; }
	else if (argc > 1 && !strcmp(argv[1], "-W")) { W = 1; ai = 2; }
	else if (argc > 1 && !strcmp(argv[1], "-ahb")) { ahbm = 1; ai = 2; }
	if (argc < ai + 3) {
		fprintf(stderr, "usage: %s [-w|-W|-ahb] <bus> <addr> <reg> [len|value]\n",
			argv[0]);
		return 2;
	}
	int bus = strtol(argv[ai], NULL, 0);
	unsigned addr = strtol(argv[ai + 1], NULL, 0);
	unsigned reg = strtol(argv[ai + 2], NULL, 0);
	char path[32];
	snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
	int fd = open(path, O_RDWR);
	if (fd < 0) { perror(path); return 1; }

	if (ahbm) {
		uint8_t buf[256];
		int len = argc > ai + 3 ? (int)strtol(argv[ai + 3], NULL, 0) : 4;
		if (len < 1 || len > (int)sizeof(buf)) return 2;
		int err = himax_ahb_read(fd, addr, reg, buf, len);
		if (err) { fprintf(stderr, "ahb read: %s\n", strerror(-err)); return 1; }
		printf("ahb %08x:", reg);
		for (int i = 0; i < len; i++)
			printf(" %02x", buf[i]);
		if (len == 4)
			printf("   (le32=0x%08x)", buf[0] | buf[1] << 8 | buf[2] << 16 |
			       (unsigned)buf[3] << 24);
		printf("\n");
		return 0;
	}

	if (W) {
		int len = argc > ai + 4 ? (int)strtol(argv[ai + 4], NULL, 0) : 4;
		unsigned v = (unsigned)strtoul(argv[ai + 3], NULL, 0);
		int err = write_reg32(fd, addr, reg, v, len);
		if (err) { fprintf(stderr, "write: %s\n", strerror(-err)); return 1; }
		printf("wrote %02x = 0x%0*x (%d bytes)\n", reg, 2 * len, v, len);
		return 0;
	}

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

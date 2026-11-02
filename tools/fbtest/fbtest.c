/* fbtest — paint colour bars on /dev/fb0 (used as the KMS smoke test on the
 * T1100 when modetest/kmscube are not in the rootfs).
 *
 * Build (host, static aarch64):
 *   aarch64-linux-gnu-gcc -O2 -static -o fbtest fbtest.c
 * Run on the device: ./fbtest [/dev/fb0]
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	const char *node = argc > 1 ? argv[1] : "/dev/fb0";
	int fd = open(node, O_RDWR);
	if (fd < 0) { perror(node); return 1; }

	struct fb_var_screeninfo v;
	struct fb_fix_screeninfo f;
	if (ioctl(fd, FBIOGET_VSCREENINFO, &v) || ioctl(fd, FBIOGET_FSCREENINFO, &f)) {
		perror("ioctl");
		return 1;
	}
	printf("%s: %ux%u %ubpp, line %u, smem %u\n",
	       node, v.xres, v.yres, v.bits_per_pixel, f.line_length, f.smem_len);

	uint8_t *fb = mmap(NULL, f.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (fb == MAP_FAILED) { perror("mmap"); return 1; }

	unsigned bpp = v.bits_per_pixel / 8;
	/* 8 vertical bars: white, yellow, cyan, green, magenta, red, blue, black */
	static const uint32_t bars[8] = {0xffffff, 0xffff00, 0x00ffff, 0x00ff00,
					 0xff00ff, 0xff0000, 0x0000ff, 0x000000};
	for (unsigned y = 0; y < v.yres; y++) {
		uint8_t *row = fb + (unsigned long)(y + v.yoffset) * f.line_length;
		for (unsigned x = 0; x < v.xres; x++) {
			uint32_t c = bars[(x * 8) / v.xres];
			if (y < 8 || y >= v.yres - 8)   /* white frame */
				c = 0xffffff;
			uint8_t *p = row + (unsigned long)(x + v.xoffset) * bpp;
			switch (bpp) {
			case 4: memcpy(p, &c, 4); break;
			case 3: p[0] = c & 0xff; p[1] = (c >> 8) & 0xff; p[2] = (c >> 16) & 0xff; break;
			case 2: { uint16_t s = ((c >> 19 & 0x1f) << 11) | ((c >> 10 & 0x3f) << 5) | (c >> 3 & 0x1f);
				  memcpy(p, &s, 2); break; }
			default: memset(p, 0xff, bpp);
			}
		}
	}
	msync(fb, f.smem_len, MS_SYNC);
	munmap(fb, f.smem_len);
	close(fd);
	puts("colour bars painted");
	return 0;
}

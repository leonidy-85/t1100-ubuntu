/* mempeek — read SoC registers through /dev/mem from the T1100 rootfs.
 *
 * Usage: ./mempeek 0x14014000 [count]     (count = number of 32-bit words)
 * Prints "addr=value" pairs; on failure prints the errno.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc < 2) { fprintf(stderr, "usage: %s <addr> [count]\n", argv[0]); return 2; }
	unsigned long addr = strtoul(argv[1], NULL, 0);
	int n = argc > 2 ? atoi(argv[2]) : 1;
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }

	for (int i = 0; i < n; i++) {
		uint32_t v = 0;
		off_t off = addr + (off_t)i * 4;
		ssize_t r = pread(fd, &v, sizeof(v), off);
		if (r != sizeof(v)) {
			printf("%#lx=ERR(%s)\n", (unsigned long)off, strerror(errno));
			return 1;
		}
		printf("%#lx=%#010x\n", (unsigned long)off, v);
	}
	close(fd);
	return 0;
}

/* mempeek — read/write SoC registers through /dev/mem from the T1100 rootfs.
 *
 * Usage:
 *   ./mempeek [--mmap] <addr> [count]      read `count' 32-bit words
 *   ./mempeek --write <addr> <value>       write one 32-bit word
 *   ./mempeek --poke <addr> <or-mask> <and-mask>
 *                                          read-modify-write: v = (v | or) & and
 *
 * Access paths:
 *   pread()  — only for addresses the kernel lets read()/pread() see (RAM);
 *              MMIO normally fails with EFAULT.
 *   mmap()   — the usable path for MMIO windows (0x1000_0000, 0x1807_0000, …).
 *              Selected with --mmap, and tried as a fallback so the old
 *              invocation style keeps working.
 *
 * Output is always "addr=0x%08x" so shell callers can parse it.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define PAGE 0x1000UL

static int map_and(int fd, unsigned long addr, int write, int rw,
		   uint32_t or_mask, uint32_t and_mask)
{
	unsigned long base = addr & ~(PAGE - 1);
	unsigned long off = addr - base;
	volatile uint32_t *p;
	void *m;

	m = mmap(NULL, PAGE, PROT_READ | (write ? PROT_WRITE : 0), MAP_SHARED,
		 fd, (off_t)base);
	if (m == MAP_FAILED) {
		printf("0x%08lx=MMAP-ERR(%s)\n", addr, strerror(errno));
		return 1;
	}
	p = (volatile uint32_t *)((volatile uint8_t *)m + off);
	if (write) {
		uint32_t v = *(volatile uint32_t *)p;

		if (rw) {
			v = (v | or_mask) & and_mask;
		} else {
			v = or_mask;
		}
		*(volatile uint32_t *)p = v;
		__sync_synchronize();
	}
	printf("0x%08lx=0x%08x\n", addr, *(volatile uint32_t *)p);
	munmap(m, PAGE);
	return 0;
}

static int peek_pread(int fd, unsigned long addr, int n)
{
	for (int i = 0; i < n; i++) {
		uint32_t v = 0;
		off_t off = (off_t)addr + (off_t)i * 4;
		ssize_t r = pread(fd, &v, sizeof(v), off);

		if (r != sizeof(v)) {
			printf("0x%08lx=ERR(%s)\n", (unsigned long)off, strerror(errno));
			return 1;
		}
		printf("0x%08lx=0x%08x\n", (unsigned long)off, v);
	}
	return 0;
}

static int peek_all(int fd, unsigned long addr, int n)
{
	unsigned long base = addr & ~(PAGE - 1);
	unsigned long off = addr - base;
	size_t len = off + (size_t)n * 4;
	size_t map_len = (len + PAGE - 1) & ~(PAGE - 1);
	volatile uint8_t *m;

	m = mmap(NULL, map_len, PROT_READ, MAP_SHARED, fd, (off_t)base);
	if (m == MAP_FAILED) {
		printf("0x%08lx=MMAP-ERR(%s)\n", addr, strerror(errno));
		return 1;
	}
	for (int i = 0; i < n; i++)
		printf("0x%08lx=0x%08x\n",
		       addr + (unsigned long)i * 4,
		       *(volatile uint32_t *)(m + off + (unsigned long)i * 4));
	munmap((void *)m, map_len);
	return 0;
}

static void usage(const char *p)
{
	fprintf(stderr,
		"usage: %s [--mmap] <addr> [count]\n"
		"       %s --write <addr> <value>\n"
		"       %s --poke <addr> <or-mask> <and-mask>\n", p, p, p);
}

int main(int argc, char **argv)
{
	int mmap_only = 0, argi = 1, rc, writable = 0;
	unsigned long addr;
	uint32_t or_mask = 0, and_mask = ~0u;
	int n, fd;

	if (argc > 1 && !strcmp(argv[1], "--mmap")) {
		mmap_only = 1;
		argi++;
	} else if (argc > 1 && !strcmp(argv[1], "--write")) {
		if (argc < 4) { usage(argv[0]); return 2; }
		writable = 1;
		addr = strtoul(argv[2], NULL, 0);
		or_mask = (uint32_t)strtoul(argv[3], NULL, 0);
		goto open_dev;
	} else if (argc > 1 && !strcmp(argv[1], "--poke")) {
		if (argc < 5) { usage(argv[0]); return 2; }
		writable = 2;
		addr = strtoul(argv[2], NULL, 0);
		or_mask = (uint32_t)strtoul(argv[3], NULL, 0);
		and_mask = (uint32_t)strtoul(argv[4], NULL, 0);
		goto open_dev;
	}
	if (argc <= argi) { usage(argv[0]); return 2; }
	addr = strtoul(argv[argi], NULL, 0);
	n = argc > argi + 1 ? atoi(argv[argi + 1]) : 1;

open_dev:
	fd = open("/dev/mem", (writable ? O_RDWR : O_RDONLY) | O_SYNC);
	if (fd < 0) {
		perror("/dev/mem");
		return 1;
	}
	if (writable)
		rc = map_and(fd, addr, 1, writable == 2, or_mask, and_mask);
	else if (mmap_only)
		rc = peek_all(fd, addr, n);
	else {
		rc = peek_pread(fd, addr, n);
		if (rc) {
			/* pread cannot reach MMIO: retry through mmap. */
			printf("# pread failed, retrying via mmap\n");
			rc = peek_all(fd, addr, n);
		}
	}
	close(fd);
	return rc;
}

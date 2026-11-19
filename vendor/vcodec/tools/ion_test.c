/* 32-bit bionic ION probe: drives libion_mtk/libion exactly like the decoder HAL.
 * Build (on T1100):
 *   arm-linux-gnueabihf-gcc -marm -O2 -nostdlib -nostartfiles -fno-stack-protector \
 *     -Wl,-e,_start -Wl,--dynamic-linker=/system/bin/linker -Wl,--allow-shlib-undefined \
 *     -Wl,-rpath-link,<chroot>/vendor/lib -o <chroot>/vendor/bin/ion_test32 ion_test.c \
 *     -L<chroot>/vendor/lib -L<chroot>/system/lib -l:libion_mtk.so -l:libion.so -l:libc.so -l:libdl.so
 * Run:
 *   chroot <chroot> /system/bin/sh -c "LD_PRELOAD=/vendor/lib/libionshim.so /vendor/bin/ion_test32"
 */
typedef unsigned long usize;
extern long write(int, const void *, usize);
extern void _exit(int);
extern int mt_ion_open(const char *);
extern int mt_ion_close(int);
extern int ion_alloc_mm(int, usize, usize, unsigned, int *);
extern int ion_alloc_camera(int, usize, usize, unsigned, int *);
extern int ion_alloc_syscontig(int, usize, usize, unsigned, int *);
extern int ion_share(int, int, int *);
extern void *ion_mmap(int, void *, usize, int, int, int, long);
extern int ion_munmap(int, void *, usize);
extern int close(int);

static void ps(const char *s)
{
	usize n = 0;
	while (s[n])
		n++;
	write(1, s, n);
}
static void pn(long v)
{
	char b[24];
	int i = 22;
	b[23] = 10;
	if (v < 0) {
		ps("-");
		v = -v;
	}
	if (!v)
		b[i--] = 48;
	while (v) {
		b[i--] = 48 + (v % 10);
		v /= 10;
	}
	write(1, b + i + 1, 23 - i);
}
#define P 3   /* PROT_READ|PROT_WRITE */
#define MS 1  /* MAP_SHARED */

static int one(const char *tag, int fd, int which)
{
	int h = -1, sfd = -1, r;
	usize len = 65536;

	if (which == 0)
		r = ion_alloc_mm(fd, len, 4096, 0, &h);
	else if (which == 1)
		r = ion_alloc_camera(fd, len, 4096, 0, &h);
	else
		r = ion_alloc_syscontig(fd, len, 4096, 0, &h);
	ps(tag);
	ps(" alloc ret=");
	pn(r);
	ps("handle=");
	pn(h);
	if (r != 0 || h < 0)
		return -1;
	r = ion_share(fd, h, &sfd);
	ps(" share ret=");
	pn(r);
	ps("fds=");
	pn(sfd);
	if (r != 0 || sfd < 0)
		return -1;
	unsigned char *p = (unsigned char *)ion_mmap(fd, 0, len, P, MS, sfd, 0);
	ps(" mmap=");
	pn((long)p);
	if ((long)p == -1 || !p)
		return -1;
	for (usize i = 0; i < len; i += 4096)
		p[i] = (unsigned char)(i / 4096 + 1);
	int ok = 1;
	for (usize i = 0; i < len; i += 4096)
		if (p[i] != (unsigned char)(i / 4096 + 1))
			ok = 0;
	ps(" rw=");
	ps(ok ? "OK" : "FAIL");
	unsigned char *q = (unsigned char *)ion_mmap(fd, 0, len, P, MS, sfd, 0);
	int ok2 = (long)q != -1 && q[8192] == 3;
	ps(" shmem=");
	ps(ok2 ? "OK" : "FAIL");
	ion_munmap(fd, p, len);
	if ((long)q != -1)
		ion_munmap(fd, q, len);
	close(sfd);
	ps("\n");
	return (ok && ok2) ? 0 : -1;
}

void _start(void)
{
	int fd = mt_ion_open("vdectest");

	ps("ION_OPEN fd=");
	pn(fd);
	ps("\n");
	if (fd < 0)
		_exit(2);
	int rc = one("MM       ", fd, 0);
	if (one("CAMERA   ", fd, 1) < 0)
		rc = -1;
	if (one("SYSCONTIG", fd, 2) < 0)
		rc = -1;
	ps("MT_ION_CLOSE=");
	pn(mt_ion_close(fd));
	ps("\n");
	_exit(rc == 0 ? 0 : 1);
}

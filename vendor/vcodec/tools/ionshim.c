/* 32-bit bionic LD_PRELOAD shim: /dev/ion emulation.
 *
 * Backend order:
 *   1) /dev/dma_heap/cma     - physically contiguous (CMA), real dma-buf
 *   2) /dev/dma_heap/system  - dma-buf, usually non-contiguous
 *   3) memfd                 - legacy CPU-only fallback (old behaviour)
 *
 * ION API implemented (what libion.so + libion_mtk.so use):
 *   open("/dev/ion")            -> device fd (dma-heap fd or memfd)
 *   ION_IOC_ALLOC  0xc0144900   -> DMA_HEAP_IOCTL_ALLOC 0xc0184800
 *   ION_IOC_FREE   0xc0044901   (handle 0 = legacy-heap probe -> 0)
 *   ION_IOC_MAP    0xc0084902   -> dup(dmabuf fd)
 *   ION_IOC_SHARE  0xc0084904   -> dup(dmabuf fd)
 *   ION_IOC_CUSTOM 0xc0084906   cmd=0 (system): sys_cmd=4 set client name,
 *                               sys_cmd=1 GET_PHYS -> PA from pagemap
 *                               cmd=1 (multimedia): buffer config, no-op
 *
 * Physical address: mmap the dma-buf, walk /proc/self/pagemap (needs
 * CAP_SYS_ADMIN), verify the pages are sequential, return first_pfn<<12.
 * If the pages are not contiguous (system heap / memfd) PA is reported as 0
 * rather than a misleading first-page address.
 *
 * Limitation: alignment above 4 KiB is not honoured (logged); the observed
 * HAL requests 0x1000.
 */
typedef unsigned long usize;
extern long syscall(long, ...);
extern int strcmp(const char *, const char *);

#define SYS_write 4
#define SYS_close 6
#define SYS_dup 41
#define SYS_ioctl 54
#define SYS_munmap 91
#define SYS_ftruncate 93
#define SYS_pread64 180
#define SYS_mmap2 192
#define SYS_openat 322
#define SYS_memfd_create 385

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_RDWR 2
#define O_CLOEXEC 0x80000
#define PROT_READ 1
#define MAP_SHARED 1
#define PAGE 4096

#define ION_IOC_ALLOC 0xc0144900UL
#define ION_IOC_FREE 0xc0044901UL
#define ION_IOC_MAP 0xc0084902UL
#define ION_IOC_SHARE 0xc0084904UL
#define ION_IOC_CUSTOM 0xc0084906UL
#define DMA_HEAP_IOCTL_ALLOC 0xc0184800UL

#define MAXH 256
#define MAXD 16

struct ion_alloc_data {
	unsigned int len;
	unsigned int align;
	unsigned int mask;
	unsigned int flags;
	unsigned int handle;
};

struct dma_heap_alloc {
	unsigned long long len;
	unsigned int fd;
	unsigned int fd_flags;
	unsigned long long heap_flags;
};

/* ABI guards: a broken struct size silently corrupts the ioctl */
typedef char _chk_alloc20[(sizeof(struct ion_alloc_data) == 20) ? 1 : -1];
typedef char _chk_heap24[(sizeof(struct dma_heap_alloc) == 24) ? 1 : -1];

static int g_hfd[MAXH];
static unsigned int g_hlen[MAXH];
static int g_huse[MAXH];
static int g_dev[MAXD];
static int g_devn;
static int g_sysfd = -1;
static int g_logged;

/* ---------- tiny stderr logger (no libc) ---------- */
static void lstr(const char *s)
{
	usize n = 0;
	while (s[n])
		n++;
	syscall(SYS_write, 2, s, n);
}
static void lhex(unsigned long long v)
{
	char b[20];
	b[0] = '0';
	b[1] = 'x';
	for (int i = 2; i < 18; i++)
		b[i] = "0123456789abcdef"[(v >> ((17 - i) * 4)) & 0xf];
	b[18] = 0;
	syscall(SYS_write, 2, b, 18);
}
static void lnum(unsigned long v)
{
	char b[24];
	int i = 22;
	b[23] = 0;
	if (!v)
		b[i--] = '0';
	while (v) {
		b[i--] = '0' + (v % 10);
		v /= 10;
	}
	syscall(SYS_write, 2, b + i + 1, 22 - i);
}

/* ---------- state helpers ---------- */
static int is_dev(int fd)
{
	for (int i = 0; i < g_devn; i++)
		if (g_dev[i] == fd)
			return 1;
	return 0;
}
static int new_slot(int fd, unsigned int len)
{
	for (int i = 0; i < MAXH; i++) {
		if (!g_huse[i]) {
			g_huse[i] = 1;
			g_hfd[i] = fd;
			g_hlen[i] = len;
			return i;
		}
	}
	return -1;
}
static int mk_memfd(usize len)
{
	long fd = syscall(SYS_memfd_create, "ion-shim", 0);
	if (fd < 0)
		return -1;
	if (syscall(SYS_ftruncate, (int)fd, (long)len) < 0) {
		syscall(SYS_close, (int)fd);
		return -1;
	}
	return (int)fd;
}
static int path_open(const char *path)
{
	return (int)syscall(SYS_openat, AT_FDCWD, path, O_RDWR | O_CLOEXEC);
}

/* ---------- dma-buf physical address ---------- */
/* status: 1 = contiguous PA found, 0 = non-contiguous, -1 = unavailable */
static unsigned long long buf_pa(int fd, unsigned int len, int *contig)
{
	void *p;
	int pf;
	unsigned long long first = 0, prev = 0, ret = 0;
	int ok = 1;

	if (len == 0)
		len = PAGE;
	*contig = -1;
	p = (void *)syscall(SYS_mmap2, 0, (unsigned long)len, PROT_READ, MAP_SHARED, fd, 0);
	if ((long)p < 0 || !p)
		return 0;
	pf = (int)syscall(SYS_openat, AT_FDCWD, "/proc/self/pagemap", O_RDONLY);
	if (pf < 0)
		ok = 0;
	for (unsigned int off = 0; ok && off < len; off += PAGE) {
		unsigned long long e = 0;
		unsigned long long idx = ((unsigned long long)(unsigned long)p + off) >> 12;
		long r = syscall(SYS_pread64, pf, &e, 8, (unsigned)idx, (unsigned)(idx >> 32));
		unsigned long long pfn;

		if (r != 8 || !(e >> 63)) { /* not present */
			ok = 0;
			break;
		}
		pfn = e & ((1ULL << 55) - 1);
		if (!pfn) { /* PFN hidden: need CAP_SYS_ADMIN */
			ok = 0;
			break;
		}
		if (!first)
			first = pfn;
		else if (pfn != prev + 1)
			*contig = 0;
		prev = pfn;
	}
	if (pf >= 0)
		syscall(SYS_close, pf);
	syscall(SYS_munmap, p, (unsigned long)len);
	if (ok && first) {
		ret = (first << 12) | ((unsigned long)p & (PAGE - 1));
		if (*contig == 0)
			ret = 0;   /* non-contiguous: never hand out a bogus PA */
		else
			*contig = 1;
	}
	return ret;
}

/* ---------- ION_IOC_CUSTOM ---------- */
static int do_custom(void *arg)
{
	unsigned int *c = (unsigned int *)arg;
	int cmd;
	unsigned int *p;

	if (!c)
		return 0;
	cmd = (int)c[0];
	p = (unsigned int *)c[1];
	if (cmd != 0 || !p)
		return 0; /* multimedia buffer config / cache ops: accept */
	if ((int)p[0] == 1) { /* ION_CMD_SYSTEM / (sys_cmd=1) GET_PHYS */
		for (int i = 1; i <= 3; i++) {
			int h = (int)p[i];
			if (h > 0 && h <= MAXH && g_huse[h - 1]) {
				int st = -1;
				unsigned long long pa = buf_pa(g_hfd[h - 1], g_hlen[h - 1], &st);
				p[i + 1] = (unsigned int)pa;
				lstr("ion-shim: GET_PHYS h=");
				lnum((unsigned long)h);
				lstr(" pa=");
				lhex(pa);
				lstr(st == 1 ? " contig\n" : st == 0 ? " NONCONTIG\n" :
				     " pagemap-unavailable\n");
				return 0;
			}
		}
	}
	/* sys_cmd=4 set_client_name, cache sync, unknown: success */
	return 0;
}

/* ---------- ioctl interposer ---------- */
int ioctl(int fd, unsigned long req, void *arg)
{
	if (is_dev(fd)) {
		switch (req) {
		case ION_IOC_ALLOC: {
			struct ion_alloc_data *a = (struct ion_alloc_data *)arg;
			unsigned int len = a->len;
			int nf = -1, s;
			struct dma_heap_alloc ha;

			if (len < PAGE)
				len = PAGE;
			ha.len = len;
			ha.fd = 0;
			ha.fd_flags = O_RDWR | O_CLOEXEC;
			ha.heap_flags = 0;
			if (syscall(SYS_ioctl, fd, DMA_HEAP_IOCTL_ALLOC, &ha) < 0) {
				/* e.g. CMA exhausted -> system heap */
				if (g_sysfd < 0)
					g_sysfd = path_open("/dev/dma_heap/system");
				if (g_sysfd < 0 || syscall(SYS_ioctl, g_sysfd,
							   DMA_HEAP_IOCTL_ALLOC, &ha) < 0) {
					/* memfd last resort */
					nf = mk_memfd(len);
					if (nf < 0)
						return -1;
				}
			}
			if (nf < 0)
				nf = (int)ha.fd;
			s = new_slot(nf, len);
			if (s < 0) {
				syscall(SYS_close, nf);
				return -1;
			}
			a->handle = (unsigned int)(s + 1);
			if (a->align > PAGE) {
				lstr("ion-shim: warn align=");
				lhex(a->align);
				lstr(" > 4K, using page alignment\n");
			}
			return 0;
		}
		case ION_IOC_MAP:
		case ION_IOC_SHARE: {
			int *d = (int *)arg;
			int h = d[0];
			long n;
			if (h <= 0 || h > MAXH || !g_huse[h - 1])
				return -1;
			n = syscall(SYS_dup, g_hfd[h - 1]);
			if (n < 0)
				return -1;
			d[1] = (int)n;
			return 0;
		}
		case ION_IOC_FREE: {
			int *d = (int *)arg;
			int h = d[0];
			if (h == 0)
				return 0; /* legacy/moder heaps probe */
			if (h > 0 && h <= MAXH && g_huse[h - 1]) {
				syscall(SYS_close, g_hfd[h - 1]);
				g_huse[h - 1] = 0;
			}
			return 0;
		}
		case ION_IOC_CUSTOM:
			return do_custom(arg);
		default:
			return (int)syscall(SYS_ioctl, fd, req, arg);
		}
	}
	/* not our device (dma-buf fd, DRM fd, ...): pass through */
	return (int)syscall(SYS_ioctl, fd, req, arg);
}

/* ---------- open/close ---------- */
static int shim_open(const char *path)
{
	if (path && !strcmp(path, "/dev/ion")) {
		const char *be = "cma";
		int fd = path_open("/dev/dma_heap/cma");

		if (fd < 0) {
			be = "system";
			fd = path_open("/dev/dma_heap/system");
		}
		if (fd < 0) {
			be = "memfd";
			fd = mk_memfd(0);
		}
		if (fd >= 0 && g_devn < MAXD)
			g_dev[g_devn++] = fd;
		if (!g_logged) {
			g_logged = 1;
			lstr("ion-shim: /dev/ion -> ");
			if (fd < 0) {
				lstr("FAILED\n");
			} else {
				lstr(be);
				lstr(" fd=");
				lnum((unsigned long)fd);
				lstr("\n");
			}
		}
		return fd;
	}
	return -2;
}
int __open_2(const char *path, int flags)
{
	int f = shim_open(path);
	if (f != -2)
		return f;
	return (int)syscall(SYS_openat, AT_FDCWD, path, flags);
}
int open(const char *path, int flags, ...)
{
	int f = shim_open(path);
	if (f != -2)
		return f;
	return (int)syscall(SYS_openat, AT_FDCWD, path, flags, 0);
}
int close(int fd)
{
	for (int i = 0; i < g_devn; i++) {
		if (g_dev[i] == fd) {
			g_dev[i] = g_dev[--g_devn];
			break;
		}
	}
	for (int i = 0; i < MAXH; i++) {
		if (g_huse[i] && g_hfd[i] == fd) {
			g_huse[i] = 0;
			break;
		}
	}
	return (int)syscall(SYS_close, fd);
}

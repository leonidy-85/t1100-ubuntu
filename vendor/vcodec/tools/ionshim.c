/* 32-bit bionic LD_PRELOAD shim: fake /dev/ion over memfd.
 * No libc calls except strcmp (no dlsym -> no re-entrancy). */
typedef unsigned long usize;
extern long syscall(long, ...);
extern int strcmp(const char *, const char *);

#define SYS_close 6
#define SYS_ioctl 54
#define SYS_dup 41
#define SYS_ftruncate 93
#define SYS_openat 322
#define SYS_memfd_create 385
#define AT_FDCWD -100

#define MAXH 256
#define MAXD 16

static int g_hfd[MAXH];
static int g_huse[MAXH];
static int g_dev[MAXD];
static int g_devn;

static int is_ours(int fd)
{
	for (int i = 0; i < g_devn; i++)
		if (g_dev[i] == fd)
			return 1;
	for (int i = 0; i < MAXH; i++)
		if (g_huse[i] && g_hfd[i] == fd)
			return 2;
	return 0;
}

static int mkfd(usize len)
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

static int new_slot(int fd)
{
	for (int i = 0; i < MAXH; i++) {
		if (!g_huse[i]) {
			g_huse[i] = 1;
			g_hfd[i] = fd;
			return i;
		}
	}
	return -1;
}

int ioctl(int fd, unsigned long req, void *arg)
{
	if (is_ours(fd)) {
		switch (req) {
		case 0xc0144900UL: { /* ION_IOC_ALLOC: len, align, heap_mask, flags, handle */
			unsigned *a = (unsigned *)arg;
			int f = mkfd(a[0]);
			if (f < 0)
				return -1;
			int s = new_slot(f);
			if (s < 0)
				return -1;
			a[4] = (unsigned)(s + 1);
			return 0;
		}
		case 0xc0084902UL: /* ION_IOC_MAP */
		case 0xc0084904UL: { /* ION_IOC_SHARE: handle, fd */
			int *d = (int *)arg;
			int h = d[0];
			if (h <= 0 || h > MAXH || !g_huse[h - 1])
				return -1;
			long n = syscall(SYS_dup, g_hfd[h - 1]);
			if (n < 0)
				return -1;
			d[1] = (int)n;
			return 0;
		}
		case 0xc0044901UL: { /* ION_IOC_FREE (handle 0 = legacy probe) */
			int *d = (int *)arg;
			int h = d[0];
			if (h == 0)
				return 0;
			if (h > 0 && h <= MAXH && g_huse[h - 1]) {
				syscall(SYS_close, g_hfd[h - 1]);
				g_huse[h - 1] = 0;
			}
			return 0;
		}
		case 0xc0084906UL: /* ION_IOC_CUSTOM: client name / cache sync / dma map */
			return 0;
		default:
			return 0;
		}
	}
	return (int)syscall(SYS_ioctl, fd, req, arg);
}

static int shim_open(const char *path)
{
	if (path && !strcmp(path, "/dev/ion")) {
		int f = mkfd(0);
		if (f >= 0 && g_devn < MAXD)
			g_dev[g_devn++] = f;
		return f;
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

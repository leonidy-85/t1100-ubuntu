/*
 * gps-trace-android — LD_PRELOAD tracer for the vendor mnld on Android.
 *
 * The Ubuntu port has no working GNSS, so we capture the reference T1100
 * (Android 11, GPS alive) and compare the two directions of the MNL stream.
 *
 * Intercepts the calls mnld actually makes:
 *   open/open64/openat   -> remember the /dev/stpgps descriptor
 *   read/__read_chk      -> log chip -> mnld
 *   write/__write_chk    -> log mnld -> chip
 *   close                -> forget the descriptor
 *
 * Built without libc headers (-nostdlib) for the bionic linker; syscalls go
 * through syscall(2), so our wrappers cannot recurse into themselves.
 *
 *   arm-linux-gnueabihf-gcc -shared -fPIC -nostdlib -O2 \
 *       -o libgpstrace.so gps-trace-android.c
 *
 * Log: /data/local/tmp/gpstrace.log, one line per transfer:
 *   W 1406 aaf0...
 *   R 20 aaf0...
 */

typedef unsigned long size_t;
typedef long ssize_t;
typedef int mode_t;

extern long syscall(long number, ...);
extern int strcmp(const char *a, const char *b);
extern void *memcpy(void *dst, const void *src, size_t n);

#define SYS_read	3
#define SYS_write	4
#define SYS_open	5
#define SYS_close	6
#define SYS_openat	322

#define AT_FDCWD	(-100)
#define O_WRONLY	1
#define O_CREAT		0100
#define O_APPEND	02000

#define LOG_PATH	"/data/local/tmp/gpstrace.log"
#define GPS_PATH	"/dev/stpgps"

static int gps_fd = -1;
static int log_fd = -1;

static size_t slen(const char *s)
{
	size_t n = 0;

	while (s[n])
		n++;
	return n;
}

static int is_gps_path(const char *p)
{
	if (!p)
		return 0;

	/* Accept both /dev/stpgps and a chroot path such as /opt/bionic/dev/stpgps. */
	if (!strcmp(p, GPS_PATH))
		return 1;
	if (slen(p) > slen(GPS_PATH) &&
	    !strcmp(p + slen(p) - slen(GPS_PATH), GPS_PATH))
		return 1;
	return 0;
}

static void open_log(void)
{
	if (log_fd < 0)
		log_fd = (int)syscall(SYS_openat, AT_FDCWD, LOG_PATH,
				      O_WRONLY | O_CREAT | O_APPEND, 0644);
}

static void put(int fd, const char *buf, size_t n)
{
	long r;

	do {
		r = syscall(SYS_write, fd, buf, n);
	} while (r < 0);
}

static void dump(char dir, const void *buf, size_t n)
{
	static const char hex[] = "0123456789abcdef";
	const unsigned char *p = buf;
	char line[32 + 4096 * 2 + 4];
	size_t i, off = 0;

	if (n > 4096)
		n = 4096;

	open_log();
	if (log_fd < 0)
		return;

	line[off++] = dir;
	line[off++] = ' ';

	/* decimal length */
	{
		char tmp[24];
		int t = 0;
		size_t v = n;

		if (!v)
			tmp[t++] = '0';
		while (v) {
			tmp[t++] = (char)('0' + v % 10);
			v /= 10;
		}
		while (t)
			line[off++] = tmp[--t];
	}
	line[off++] = ' ';

	for (i = 0; i < n; i++) {
		line[off++] = hex[p[i] >> 4];
		line[off++] = hex[p[i] & 0xf];
	}
	line[off++] = '\n';

	put(log_fd, line, off);
}

static void note_open(int fd, const char *path)
{
	char line[128];
	size_t off = 0;
	const char *p = "OPEN ";

	if (fd < 0)
		return;
	open_log();
	if (log_fd < 0)
		return;
	while (*p)
		line[off++] = *p++;
	/* decimal fd */
	{
		char tmp[24];
		int t = 0;
		int v = fd;

		while (v) {
			tmp[t++] = (char)('0' + v % 10);
			v /= 10;
		}
		while (t)
			line[off++] = tmp[--t];
	}
	line[off++] = ' ';
	while (*path && off < sizeof(line) - 2)
		line[off++] = *path++;
	line[off++] = '\n';
	put(log_fd, line, off);
}

int open(const char *path, int flags, mode_t mode)
{
	int fd = (int)syscall(SYS_openat, AT_FDCWD, path, flags, mode);

	if (is_gps_path(path)) {
		gps_fd = fd;
		note_open(fd, path);
	}
	return fd;
}

int open64(const char *path, int flags, mode_t mode)
{
	return open(path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, mode_t mode)
{
	int fd = (int)syscall(SYS_openat, dirfd, path, flags, mode);

	if (is_gps_path(path)) {
		gps_fd = fd;
		note_open(fd, path);
	}
	return fd;
}

ssize_t read(int fd, void *buf, size_t count)
{
	ssize_t r = (ssize_t)syscall(SYS_read, fd, buf, count);

	if (r > 0 && fd == gps_fd)
		dump('R', buf, (size_t)r);
	return r;
}

ssize_t __read_chk(int fd, void *buf, size_t count, size_t buflen)
{
	(void)buflen;
	return read(fd, buf, count);
}

ssize_t write(int fd, const void *buf, size_t count)
{
	if (fd == gps_fd && count)
		dump('W', buf, count);
	return (ssize_t)syscall(SYS_write, fd, buf, count);
}

ssize_t __write_chk(int fd, const void *buf, size_t count, size_t buflen)
{
	(void)buflen;
	return write(fd, buf, count);
}

int close(int fd)
{
	if (fd == gps_fd)
		gps_fd = -1;
	return (int)syscall(SYS_close, fd);
}

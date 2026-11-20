/* LD_PRELOAD ioctl tracer for the Vcodec ABI (magic 'M' = 0x4d).
 * Logs: fd, cmd, ret, arg[0..1] to stderr.
 */
typedef unsigned long usize;
extern long syscall(long, ...);
extern long write(int, const void *, usize);

static void w(const char *s, usize n) { write(2, s, n); }
static void ws(const char *s) { usize n = 0; while (s[n]) n++; w(s, n); }
static void pn(long v)
{
	char b[24]; int i = 22; b[23] = 0;
	if (v < 0) { w("-", 1); v = -v; }
	if (!v) b[i--] = '0';
	while (v) { b[i--] = '0' + (v % 10); v /= 10; }
	w(b + i + 1, 22 - i);
}
static void ph(unsigned long v)
{
	ws("0x");
	for (int i = 28; i >= 0; i -= 4)
		write(2, &"0123456789abcdef"[(v >> i) & 0xf], 1);
}

int ioctl(int fd, unsigned long req, void *arg)
{
	long r = syscall(54, fd, req, arg);
	int magic = (int)((req >> 8) & 0xff);

	if (magic == 0x4d) { /* 'M' = MFV/VCODEC */
		ws("ioctltrace: fd="); pn(fd);
		ws(" cmd="); ph(req);
		ws(" arg="); ph((unsigned long)arg);
		if (arg) { ws(" a0="); ph(((unsigned int *)arg)[0]); }
		ws(" ret="); pn((int)r);
		ws("\n");
	}
	return (int)r;
}

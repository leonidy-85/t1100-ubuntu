/* 32-bit bionic: exercise VCODEC_ALLOC_NON_CACHE_BUFFER end to end.
 *
 *  1. ioctl(/dev/Vcodec, 0x40044d22, VAL_MEMORY_T) -> PA
 *  2. mmap(/dev/Vcodec, size, RW, SHARED, offset=PA) -> user VA
 *  3. write/read through VA
 *  4. ioctl(/dev/Vcodec, 0x40044d23, VAL_MEMORY_T) -> free
 */
typedef unsigned long usize;
extern int open(const char *, int, ...);
extern int ioctl(int, unsigned long, ...);
extern long write(int, const void *, usize);
extern void _exit(int);
extern void *memset(void *, int, usize);
extern void *mmap64(void *, usize, int, int, int, long long);
extern int *__errno(void);

struct memrec {
	unsigned int sign;
	unsigned int type;
	unsigned long long size;
	unsigned long long va;
	unsigned long long pa;
	unsigned int align;
	unsigned int pad0;
	unsigned long long align_va;
	unsigned long long align_pa;
	unsigned int codec;
	int share_fd;
	unsigned long long ion_handle;
	unsigned long long reserved;
	unsigned long long ressize;
	unsigned int pad1;
	unsigned int pad2;
};

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
static void ph(unsigned long v)
{
	ps("0x");
	for (int i = 28; i >= 0; i -= 4)
		write(1, &"0123456789abcdef"[(v >> i) & 0xf], 1);
}

void _start(void)
{
	struct memrec m;
	volatile unsigned char *p;
	int fd, r, ok = 0;

	ps("== nc_test32: ALLOC_NON_CACHE_BUFFER + mmap\n");
	fd = open("/dev/Vcodec", 2);
	if (fd < 0) {
		ps("open failed\n");
		_exit(2);
	}
	memset(&m, 0, sizeof(m));
	m.type = 3;
	m.size = 65536;
	m.align = 0x1000;
	r = ioctl(fd, 0x40044d22UL, &m);
	ps("alloc ret=");
	pn(r);
	ps(" PA=");
	ph(m.pa);
	ps(" size=");
	pn(m.size);
	ps(" share_fd=");
	pn(m.share_fd);
	ps("\n");
	if (r != 0 || !m.pa)
		_exit(3);

	p = mmap64(0, m.size, 3, 1, fd, m.pa);
	ps("mmap=");
	ph((unsigned long)p);
	ps(" errno=");
	pn((long)*__errno());
	ps("\n");
	if ((unsigned long)p >= 0xfffff000UL)
		_exit(4);
	p[0] = 0x5a;
	p[m.size - 1] = 0xa5;
	ok = (p[0] == 0x5a && p[m.size - 1] == 0xa5);
	ps("rw=");
	ps(ok ? "OK" : "FAIL");
	ps("\n");

	r = ioctl(fd, 0x40044d23UL, &m);
	ps("free ret=");
	pn(r);
	ps("\n");
	ps(ok ? "VERDICT: PASS\n" : "VERDICT: FAIL\n");
	_exit(ok ? 0 : 5);
}

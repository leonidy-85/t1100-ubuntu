/* LD_PRELOAD hook: parseSliceHeaderHW (libvcodecdrv).
 * Plain C wrapper with the observed arity (6 args; 5th/6th arrive on the
 * stack), so the compiler forwards them correctly. Logs args, dumps 512 bytes
 * of a0 and 256 bytes at the 64-bit pointers a0+0x38/+0x40/+0x48, then calls
 * the original via dlsym(RTLD_NEXT) and logs the return value.
 */
typedef unsigned long usize;
extern void *dlsym(void *, const char *);
extern long write(int, const void *, usize);
extern int open(const char *, int, ...);
extern long read(int, void *, unsigned long);
extern int close(int);

void *g_real;

static int g_out = -1;
static void ensure_out(void)
{
	if (g_out < 0)
		g_out = open("/tmp/parsehook.log", 0x41 /*O_WRONLY|O_CREAT|O_TRUNC*/, 0644);
	if (g_out < 0) g_out = 2;
}
static void w(const char *s, usize n) { ensure_out(); write(g_out, s, n); }
static void ws(const char *s) { usize n = 0; while (s[n]) n++; w(s, n); }
static void pc(char c) { w(&c, 1); }
static void pn(long v)
{
	char b[24]; int i = 22; b[23] = 0;
	if (v < 0) { pc('-'); v = -v; }
	if (!v) b[i--] = '0';
	while (v) { b[i--] = '0' + (v % 10); v /= 10; }
	w(b + i + 1, 22 - i);
}
static void ph(unsigned long v)
{
	ws("0x");
	for (int i = 28; i >= 0; i -= 4)
		pc("0123456789abcdef"[(v >> i) & 0xf]);
}

#define MAXR 512
static unsigned long r_start[MAXR], r_end[MAXR];
static unsigned long vcdrv_base;
static int r_n, r_loaded;

static void load_maps(void)
{
	static char buf[262144];
	long n = 0, got; int fd;
	char *p;

	if (r_loaded) return;
	r_loaded = 1;
	fd = open("/proc/self/maps", 0);
	if (fd < 0) return;
	while (n < (long)sizeof(buf) - 1) {
		got = read(fd, buf + n, sizeof(buf) - 1 - n);
		if (got <= 0) break;
		n += got;
	}
	close(fd);
	if (n <= 0) return;
	buf[n] = 0;
	p = buf;
	while (*p) {
		unsigned long a = 0, b = 0;
		char *q = p;
		while (*q && *q != '-') { a = a * 16 + (*q <= '9' ? *q - '0' : (*q | 32) - 'a' + 10); q++; }
		if (*q == '-') q++;
		while (*q && *q != ' ') { b = b * 16 + (*q <= '9' ? *q - '0' : (*q | 32) - 'a' + 10); q++; }
		if (b > a && r_n < MAXR) { r_start[r_n] = a; r_end[r_n] = b; r_n++; }
		{
			const char *needle = "libvcodecdrv.so";
			char *n = q;
			while (*n && *n != '\n') {
				const char *nd = needle;
				char *t = n;
				while (*nd && *t == *nd) { t++; nd++; }
				if (!*nd) { if (!vcdrv_base) vcdrv_base = a; break; }
				n++;
			}
		}
		while (*q && *q != '\n') q++;
		if (*q) q++;
		p = q;
	}
}

static int is_map(unsigned long p, unsigned long len)
{
	if (p < 0x1000) return 0;
	for (int i = 0; i < r_n; i++)
		if (p >= r_start[i] && p + len <= r_end[i]) return 1;
	return 0;
}

static void dumpn(const char *tag, unsigned long p, int n)
{
	ws(tag); ws("="); ph(p); ws(":");
	if (!is_map(p, (unsigned long)n)) { ws("unmapped\n"); return; }
	for (int i = 0; i < n; i++) {
		unsigned char c = ((unsigned char *)p)[i];
		pc(' ');
		pc("0123456789abcdef"[c >> 4]);
		pc("0123456789abcdef"[c & 0xf]);
	}
	ws("\n");
}

static unsigned long rd32(unsigned long p)
{
	if (!is_map(p, 4)) return 0;
	return *(volatile unsigned int *)p;
}

static int calls;

typedef int (*hw_fn)(unsigned, unsigned, unsigned, unsigned, unsigned, unsigned);

int parseSliceHeaderHW(unsigned a0, unsigned a1, unsigned a2, unsigned a3,
		       unsigned a4, unsigned a5)
{
	int r;

	load_maps();
	if (!g_real) {
		/* dlsym(RTLD_NEXT) resolves back to us (preload), so use the known
		 * file offset 0x4c829 from the library base (files identical on both). */
		load_maps();
		if (vcdrv_base)
			g_real = (void *)(vcdrv_base + 0x4c829UL);
	}
	calls++;
	ws("=== PARSEHOOK #"); pn(calls);
	ws(" a0="); ph(a0); ws(" a1="); ph(a1);
	ws(" a2="); ph(a2); ws(" a3="); ph(a3);
	ws(" a4="); ph(a4); ws(" a5="); ph(a5);
	ws(" real="); ph((unsigned long)g_real); ws("\n");
	dumpn("HWD_A0", a0, 4096);
	ws("HWD_FIELDS");
	for (int off = 0x16c; off <= 0x16c; off += 4) { ws(" +"); pn(off); ws("="); ph(rd32((unsigned long)a0 + off)); }
	ws(" +2532="); ph(rd32((unsigned long)a0 + 2532));
	ws(" +2584="); ph(rd32((unsigned long)a0 + 2584));
	ws(" +2588="); ph(rd32((unsigned long)a0 + 2588));
	ws(" +5188="); ph(rd32((unsigned long)a0 + 5188));
	ws("\n");
	for (int off = 0x38; off <= 0x48; off += 8) {
		unsigned long lo = rd32((unsigned long)a0 + off);
		unsigned long hi = rd32((unsigned long)a0 + off + 4);
		if (!lo || hi > 1) { ws("HWD_PTR"); pn(off); ws("=skip\n"); continue; }
		dumpn(off == 0x38 ? "HWD_P38" : off == 0x40 ? "HWD_P40" : "HWD_P48", lo, 256);
	}
	if (!g_real) { ws("PARSEHOOK no real\n"); return -10; }
	r = ((hw_fn)g_real)(a0, a1, a2, a3, a4, a5);
	ws("PARSEHOOK ret="); pn(r); ws("\n");
	return r;
}

__attribute__((constructor)) static void hook_ctor(void)
{
	ws("HOOK loaded\n");
}

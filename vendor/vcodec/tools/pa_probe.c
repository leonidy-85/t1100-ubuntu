/* 32-bit bionic: prove that the vendor HAL gets a real physical address.
 *
 * Calls libvcodec_utility's eVideoMemAlloc (the allocator libvcodecdrv uses)
 * with a VAL_MEMORY_T (96 bytes, 64-bit unions => VA at +16, PA at +24),
 * writes the buffer through the returned VA and checks pvMemPa.
 *
 * Expected with /dev/dma_heap/cma present (kernel with CONFIG_DMABUF_HEAPS):
 *   VA != 0, PA != 0, pages contiguous -> VERDICT: PASS
 * Without dma_heap (memfd fallback) PA stays 0 -> VERDICT: FAIL, which is the
 * documented pre-dma-heap behaviour.
 *
 * Build (on T1100, C=/tmp/android32-chroot):
 *  arm-linux-gnueabihf-gcc -marm -O2 -nostdlib -nostartfiles -fno-stack-protector \
 *    -Wl,-e,_start -Wl,--dynamic-linker=/system/bin/linker -Wl,--allow-shlib-undefined \
 *    -Wl,-rpath-link,$C/vendor/lib -o $C/vendor/bin/pa_probe32 pa_probe.c \
 *    -L$C/system/lib -l:libc.so -l:libdl.so
 * Run:
 *  chroot $C /system/bin/sh -c "LD_PRELOAD=/vendor/lib/libionshim.so /vendor/bin/pa_probe32"
 */
typedef unsigned long usize;
extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *dlerror(void);
extern long write(int, const void *, usize);
extern void _exit(int);
extern void *memset(void *, int, usize);

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

/* VAL_MEMORY_T, 32-bit ABI (96 bytes) */
struct memrec {
	unsigned int sign;             /* +0  */
	unsigned int type;             /* +4  VAL_MEM_TYPE_T */
	unsigned long long size;       /* +8  */
	unsigned long long va;         /* +16 pvMemVa */
	unsigned long long pa;         /* +24 pvMemPa */
	unsigned int align;            /* +32 */
	unsigned int pad0;             /* +36 */
	unsigned long long align_va;   /* +40 */
	unsigned long long align_pa;   /* +48 */
	unsigned int codec;            /* +56 */
	int share_fd;                  /* +60 */
	unsigned long long ion_handle; /* +64 */
	unsigned long long reserved;   /* +72 */
	unsigned long long ressize;    /* +80 */
	unsigned int pad1;             /* +88 */
	unsigned int pad2;             /* +92 */
};

static int g_fail;

static void one(int (*fn)(struct memrec *, unsigned), unsigned type)
{
	struct memrec m;
	int r, wr_ok = 0;

	memset(&m, 0, sizeof(m));
	m.type = type;
	m.size = 65536;
	m.align = 0x2000; /* 8K requested; shim honours 4K */
	m.codec = 0;
	r = fn(&m, 96);
	ps("type=");
	pn(type);
	ps(" ret=");
	pn(r);
	ps(" VA=");
	ph((unsigned long)m.va);
	ps(" PA=");
	ph((unsigned long)m.pa);
	if (m.va && (long)m.va != -1) {
		volatile unsigned char *p = (volatile unsigned char *)(unsigned long)m.va;
		p[0] = 0x5a;
		p[65535] = 0xa5;
		wr_ok = (p[0] == 0x5a && p[65535] == 0xa5);
	}
	ps(" writable=");
	ps(wr_ok ? "yes" : "NO");
	ps(" sharefd=");
	pn(m.share_fd);
	ps("\n");
	if (r != 0 || !m.va || !wr_ok || !m.pa)
		g_fail = 1;
}

void _start(void)
{
	void *H = dlopen("/vendor/lib/libvcodec_utility.so", 1);
	int (*fn)(struct memrec *, unsigned);

	ps("== pa_probe32: vendor HAL allocation, VA/PA check\n");
	if (!H) {
		ps("DLOPEN_FAIL: ");
		ps(dlerror());
		ps("\nFAIL\n");
		_exit(1);
	}
	fn = dlsym(H, "eVideoMemAlloc");
	if (!fn) {
		ps("no eVideoMemAlloc\nFAIL\n");
		_exit(2);
	}
	one(fn, 0); /* VAL_MEM_TYPE_FOR_SW */
	one(fn, 1); /* VAL_MEM_TYPE_FOR_HW_CACHEABLE */
	one(fn, 2); /* VAL_MEM_TYPE_FOR_HW_CACHEABLE_MCI */
	if (g_fail) {
		ps("VERDICT: FAIL (PA==0 or not writable; memfd/non-contiguous backend)\n");
		_exit(1);
	}
	ps("VERDICT: PASS (VA writable, PA != 0)\n");
	_exit(0);
}

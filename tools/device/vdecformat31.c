/*
 * 32-bit bionic LD_PRELOAD shim for the vendor VDEC HAL (MT6771/T1100).
 *
 * It works around two vendor-library issues:
 *   - eVDecDrvCreate() leaves the handle pointer uninitialised for format
 *     0x100 (patch cmp 0x10000000 -> 0x100 at +0x2ba2a);
 *   - the VLD AVC configuration is incomplete on this path (inject
 *     0x84/0x24/0x28c from H264_HAL_InitH264BarrelShift).
 *
 * Build on the build host (bionic sysroot in ./system):
 *   arm-linux-gnueabihf-gcc -marm -O2 -fPIC -shared -nostdlib -nostartfiles \
 *     -Wl,-rpath,/system/lib -Wl,-rpath-link,./system/lib -L./system/lib \
 *     -o libvdecformat31.so vdecformat31.c -lc -ldl -lgcc
 *
 * Run inside the /opt/bionic chroot.  Do NOT add VLD register reads to this
 * shim: reading VLD from userspace hung the tablet twice (see
 * docs/vdec-vld-poll-2026-11-23.md).
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <signal.h>
#include <ucontext.h>

typedef int (*create_fn)(void **h, unsigned int fmt);
typedef int (*init_fn)(void *h, void *a, void *b);
typedef int (*parse_fn)(void *ctx, void *a, const unsigned char *bs, unsigned int len, void *e);
typedef int (*sps_fn)(void *a, void *b, void *c, void *d, void *e);
typedef int (*vld_rd_fn)(void *hal, unsigned int off, void *out, void *file);
typedef int (*vld_wr_fn)(void *hal, unsigned int off, unsigned int val, void *file);
typedef int (*init_hw_fn)(void *ctx, void *file);
typedef int (*wait_fn)(void *ctx, void *file);
typedef int (*decode_fn)(void *h, void *a, void *b, void *c);
typedef int (*picset_fn)(void *a, void *b, void *c, void *d);
typedef int (*ue_fn)(void *ctx, void *file);
typedef int (*sc_fn)(void *a, void *b, void *c, void *d, void *e);
typedef int (*bs_fn)(void *a, void *b, void *c, void *d);
typedef void *(*memalign_fn)(size_t, size_t);
typedef void (*free_fn)(void *);

static void segv_handler(int sig, siginfo_t *si, void *uc);

static void logmsg(const char *fmt, ...)
{
	char b[256];
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = vsnprintf(b, sizeof(b), fmt, ap);
	va_end(ap);
	if (n > 0)
		write(2, b, n);
}

static create_fn real_create;
static init_fn real_init;
static parse_fn real_parse;
static sps_fn real_sps, real_pps;
static vld_rd_fn real_vld_rd;
static vld_wr_fn real_vld_wr;
static init_hw_fn real_init_hw;
static wait_fn real_wait;
static decode_fn real_decode;
static picset_fn real_picset;
static ue_fn real_ue;
static sc_fn real_sc;
static bs_fn real_bs;
static memalign_fn real_memalign;
static free_fn real_free;
static void *stable_pages[16];
static int nstable;

static void *my_memalign(size_t align, size_t size);
static void my_free(void *p);
static void patch_got(void *base, unsigned int off, void *fn);
static void patch_code(void *base, unsigned int off, const unsigned char *insn, int len);
static unsigned char saved[0x400];
static void *saved_h;
static void *watch_page;

__attribute__((constructor)) static void shim_init(void)
{
	void *lib = dlopen("/vendor/lib/libvcodecdrv.so", RTLD_NOW | RTLD_LOCAL);
	if (!lib) {
		logmsg("SHIM dlopen: %s\n", dlerror());
		return;
	}
	real_create = (create_fn)dlsym(lib, "eVDecDrvCreate");
	real_init = (init_fn)dlsym(lib, "eVDecDrvInit");
	real_parse = (parse_fn)dlsym(lib, "parseSliceHeaderHW");
	real_sps = (sps_fn)dlsym(lib, "H264_HAL_SetSPSAVLD");
	real_pps = (sps_fn)dlsym(lib, "H264_HAL_SetPPSAVLD");
	real_vld_rd = (vld_rd_fn)dlsym(lib, "H264_HAL_ReadAVCVLD");
	real_vld_wr = (vld_wr_fn)dlsym(lib, "H264_HAL_WriteVLD");
	real_init_hw = (init_hw_fn)dlsym(lib, "H264_HAL_InitVDecHW");
	real_wait = (wait_fn)dlsym(lib, "bVDecWaitVldFetchOk");
	real_decode = (decode_fn)dlsym(lib, "eVDecDrvDecodeEx");
	real_picset = (picset_fn)dlsym(lib, "Vdec_Drv_setDecPicInfo");
	real_ue = (ue_fn)dlsym(lib, "H264_HAL_UeCodeNum");
	real_sc = (sc_fn)dlsym(lib, "H264_HAL_GetStartCode_8530");
	real_bs = (bs_fn)dlsym(lib, "H264_HAL_InitH264BarrelShifter");
	real_memalign = (memalign_fn)dlsym(RTLD_NEXT, "memalign");
	real_free = (free_fn)dlsym(RTLD_NEXT, "free");

	{
		Dl_info di;

		if (dladdr((void *)real_create, &di)) {
			static const unsigned char cmp100[4] = {0xba, 0xf5, 0x80, 0x7f};
			static const unsigned char slice5[4] = {0x05, 0x21, 0x00, 0xbf};
			patch_got(di.dli_fbase, 0x97c48, (void *)my_memalign);
			patch_got(di.dli_fbase, 0x97cc0, (void *)my_free);
			patch_code(di.dli_fbase, 0x2ba2a, cmp100, 4);
		}
	}

	logmsg("SHIM ready create=%p init=%p parse=%p decode=%p picset=%p ue=%p sc=%p bs=%p memalign=%p free=%p\n", real_create, real_init, real_parse, real_decode, real_picset, real_ue, real_sc, real_bs, real_memalign, real_free);
}

static void dump_h(const char *tag, void *h, void *ra)
{
	unsigned int *p = h;
	Dl_info di;

	if (dladdr(ra, &di))
		logmsg("SHIM %s lr=%p lib=%s off=0x%lx\n", tag, ra, di.dli_fname,
			(unsigned long)ra - (unsigned long)di.dli_fbase);
	if (!p) {
		logmsg("SHIM %s h=NULL\n", tag);
		return;
	}
	logmsg("SHIM %s h=%p words=%08x %08x %08x %08x %08x %08x %08x %08x\n",
		tag, h, p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]);
}

static void install_watch(void *h)
{
	(void)h;
	logmsg("SHIM watch disabled\n");
}

static void segv_handler(int sig, siginfo_t *si, void *uc)
{
	unsigned long *sc = (unsigned long *)((char *)uc + 20);

	{
		Dl_info d1, d2;
		void *pc = (void *)sc[18], *lr = (void *)sc[17];

		if (dladdr(pc, &d1))
			logmsg("SHIM WATCH pc=%p lib=%s off=0x%lx\n", pc, d1.dli_fname,
				(unsigned long)pc - (unsigned long)d1.dli_fbase);
		else
			logmsg("SHIM WATCH pc=%p\n", pc);
		if (dladdr(lr, &d2))
			logmsg("SHIM WATCH lr=%p lib=%s off=0x%lx\n", lr, d2.dli_fname,
				(unsigned long)lr - (unsigned long)d2.dli_fbase);
		else
			logmsg("SHIM WATCH lr=%p\n", lr);
	}
	logmsg("SHIM WATCH sig=%d addr=%p r0=%p\n",
		sig, si ? si->si_addr : 0, (void *)sc[3]);
	(void)watch_page;
	syscall(SYS_exit_group, 99);
}

static void *my_memalign(size_t align, size_t size)
{
	if (align == 1 && size == 0x378) {
		void *p = (void *)syscall(SYS_mmap2, 0, 0x1000,
					  PROT_READ | PROT_WRITE,
					  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (p != (void *)-1) {
			if (nstable < 16)
				stable_pages[nstable++] = p;
			logmsg("SHIM stable handle page %p\n", p);
			return p;
		}
	}
	return real_memalign ? real_memalign(align, size) : NULL;
}

static void my_free(void *p)
{
	int i;

	for (i = 0; i < nstable; i++)
		if (p == stable_pages[i])
			return;
	if (real_free)
		real_free(p);
}

static void patch_got(void *base, unsigned int off, void *fn)
{
	void **slot = (void **)((char *)base + off);
	unsigned long page = (unsigned long)slot & ~0xfffUL;

	if (mprotect((void *)page, 0x1000, PROT_READ | PROT_WRITE) != 0) {
		logmsg("SHIM mprotect got 0x%x failed\n", off);
		return;
	}
	*slot = fn;
	mprotect((void *)page, 0x1000, PROT_READ);
	logmsg("SHIM patched got 0x%x -> %p\n", off, fn);
}

static void patch_code(void *base, unsigned int off, const unsigned char *insn, int len)
{
	void *addr = (char *)base + off;
	unsigned long page = (unsigned long)addr & ~0xfffUL;

	if (mprotect((void *)page, 0x1000, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
		logmsg("SHIM mprotect code 0x%x failed\n", off);
		return;
	}
	memcpy(addr, insn, len);
	__builtin___clear_cache((char *)addr, (char *)addr + len);
	mprotect((void *)page, 0x1000, PROT_READ | PROT_EXEC);
	logmsg("SHIM patched code 0x%x\n", off);
}

int eVDecDrvCreate(void **h, unsigned int fmt)
{
	int r = real_create(h, fmt);

	if (*h) {
		memcpy(saved, *h, 0x378);
		saved_h = *h;
	}
	dump_h("create-after", *h, __builtin_return_address(0));
	logmsg("SHIM create fmt=0x%x h=%p *h=%p r=%d\n", fmt, h, *h, r);
	return r;
}

int eVDecDrvInit(void *h, void *a, void *b)
{
	void *ra = __builtin_return_address(0);
	unsigned int fmt = h ? *(unsigned int *)h : 0;
	Dl_info di;

	dump_h("init-before", h, __builtin_return_address(0));
	if (dladdr(ra, &di))
		logmsg("SHIM init h=%p fmt@h=0x%x a=%p b=%p lr=%p lib=%s off=0x%lx\n",
			h, fmt, a, b, ra, di.dli_fname,
			(unsigned long)ra - (unsigned long)di.dli_fbase);
	else
		logmsg("SHIM init h=%p fmt@h=0x%x a=%p b=%p lr=%p\n",
			h, fmt, a, b, ra);
	/* diagnosis: no restore */
	return real_init(h, a, b);
}

int H264_HAL_SetSPSAVLD(void *a, void *b, void *c, void *d, void *e)
{
	static int n;
	int r;

	if (n++ < 8)
		logmsg("SHIM SPS a=%p b=%p c=%p d=%p e=%p\n", a, b, c, d, e);
	r = real_sps ? real_sps(a, b, c, d, e) : -999;
	if (n <= 8)
		logmsg("SHIM SPS ret=%d\n", r);
	return r;
}

int H264_HAL_SetPPSAVLD(void *a, void *b, void *c, void *d, void *e)
{
	static int n;
	int r;

	if (n++ < 8)
		logmsg("SHIM PPS a=%p b=%p c=%p d=%p e=%p\n", a, b, c, d, e);
	r = real_pps ? real_pps(a, b, c, d, e) : -999;
	if (n <= 8)
		logmsg("SHIM PPS ret=%d\n", r);
	return r;
}

int H264_HAL_ReadAVCVLD(void *hal, unsigned int off, void *out, void *file)
{
	static int n;
	int r;

	r = real_vld_rd ? real_vld_rd(hal, off, out, file) : -999;
	if (n++ < 24)
		logmsg("SHIM VLD rd hal=%p off=0x%x out=%08x ret=%d\n",
		       hal, off, out ? *(unsigned int *)out : 0, r);
	return r;
}

int H264_HAL_WriteVLD(void *hal, unsigned int off, unsigned int val, void *file)
{
	static int n;
	int r;

	if (n++ < 32)
		logmsg("SHIM VLD wr hal=%p off=0x%x val=0x%x\n", hal, off, val);
	r = real_vld_wr ? real_vld_wr(hal, off, val, file) : -999;
	if (real_vld_wr && off == 0xc0 && val == 0x40000) {
		logmsg("SHIM inject VLD cfg 0x84/0x24/0x28c\n");
		real_vld_wr(hal, 0x84, 0xAE00E007, file);
		real_vld_wr(hal, 0x24, 6, file);
		real_vld_wr(hal, 0x28c, 1, file);
	}
	if (real_vld_wr && off == 0xb8)
		real_vld_wr(hal, 0x28c, 0, file);
	return r;
}

int H264_HAL_InitVDecHW(void *ctx, void *file)
{
	static int n;
	int r;

	if (n++ < 8) {
		unsigned int *hp = (unsigned int *)((char *)ctx + 0x7d4);
		logmsg("SHIM InitVDecHW ctx=%p file=%p hal=%p words=%08x %08x %08x %08x %08x %08x %08x %08x\n",
		       ctx, file, hp, hp[0], hp[1], hp[2], hp[3], hp[4], hp[5], hp[6], hp[7]);
	}
	r = real_init_hw ? real_init_hw(ctx, file) : -999;
	if (n <= 8)
		logmsg("SHIM InitVDecHW ret=%d\n", r);
	return r;
}

int H264_HAL_UeCodeNum(void *ctx, void *file)
{
	static int n;
	int r;

	r = real_ue ? real_ue(ctx, file) : -999;
	if (n++ < 32)
		logmsg("SHIM ue ctx=%p ret=%d\n", ctx, r);
	return r;
}

int H264_HAL_GetStartCode_8530(void *a, void *b, void *c, void *d, void *e)
{
	static int n;
	int r;

	r = real_sc ? real_sc(a, b, c, d, e) : -999;
	if (n++ < 16)
		logmsg("SHIM sc a=%p b=%p c=%p d=%p e=%p ret=%d\n", a, b, c, d, e, r);
	return r;
}

int H264_HAL_InitH264BarrelShifter(void *a, void *b, void *c, void *d)
{
	static int n;
	int r;

	r = real_bs ? real_bs(a, b, c, d) : -999;
	if (n++ < 16)
		logmsg("SHIM barrel a=%p b=%p c=%p d=%p ret=%d\n", a, b, c, d, r);
	return r;
}

int parseSliceHeaderHW(void *ctx, void *a, const unsigned char *bs, unsigned int len, void *e)
{
	unsigned int i, n;
	char line[256];
	int off, r;

	off = snprintf(line, sizeof(line), "SHIM parse ctx=%p a=%p bs=%p len=%u e=%p\n",
		ctx, a, bs, len, e);
	if (off > 0) write(2, line, off);

	if (bs) {
		unsigned char vec;
		unsigned long page = (unsigned long)bs & ~0xfffUL;
		int mapped = (mincore((void *)page, 0x1000, &vec) == 0);
		off = snprintf(line, sizeof(line), "SHIM mapped=%d first:", mapped);
		if (mapped) {
			n = len < 40 ? len : 40;
			for (i = 0; i < n && off < (int)sizeof(line) - 4; i++)
				off += snprintf(line + off, sizeof(line) - off, " %02x", bs[i]);
		}
		off += snprintf(line + off, sizeof(line) - off, "\n");
		write(2, line, off);
	}

	{
		unsigned int *w = ctx;
		off = snprintf(line, sizeof(line), "SHIM ctxw %08x %08x %08x %08x %08x %08x %08x %08x a18=%08x vld=%08x\n",
			w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7],
			w[0xa18 / 4], w[0x7d4 / 4]);
		write(2, line, off);
	}

	r = real_parse(ctx, a, bs, len, e);
	off = snprintf(line, sizeof(line), "SHIM parse ret=%d\n", r);
	write(2, line, off);
	return r;
}



int bVDecWaitVldFetchOk(void *ctx, void *file)
{
	static int n;
	int r;

	if (n++ < 32)
		logmsg("SHIM Wait begin ctx=%p\n", ctx);
	r = real_wait ? real_wait(ctx, file) : -999;
	if (n <= 32)
		logmsg("SHIM Wait ret=%d\n", r);
	return r;
}

int eVDecDrvDecodeEx(void *h, void *a, void *b, void *c)
{
	static int n;
	int r;

	if (n++ < 16)
		logmsg("SHIM DecodeEx h=%p a=%p b=%p c=%p\n", h, a, b, c);
	r = real_decode ? real_decode(h, a, b, c) : -999;
	if (n <= 16)
		logmsg("SHIM DecodeEx ret=%d\n", r);
	return r;
}

int Vdec_Drv_setDecPicInfo(void *a, void *b, void *c, void *d)
{
	static int n;
	int r;

	if (n++ < 16)
		logmsg("SHIM setDecPicInfo a=%p b=%p c=%p d=%p\n", a, b, c, d);
	r = real_picset ? real_picset(a, b, c, d) : -999;
	if (n <= 16)
		logmsg("SHIM setDecPicInfo ret=%d\n", r);
	return r;
}

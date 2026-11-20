/* 32-bit bionic OMX bring-up probe: core init, component enum, GetHandle,
 * port definitions. No libc init: output via write(), only headers for types.
 * Build (T1100, C=/tmp/android32-chroot):
 *  arm-linux-gnueabihf-gcc -marm -O2 -nostdlib -nostartfiles -fno-stack-protector \
 *    -I/tmp/omx-headers -Wl,-e,_start -Wl,--dynamic-linker=/system/bin/linker \
 *    -Wl,--allow-shlib-undefined -Wl,-rpath-link,$C/vendor/lib \
 *    -o $C/vendor/bin/omx_probe32 omx_probe.c -L$C/system/lib -l:libc.so -l:libdl.so
 * Run:
 *  chroot $C /system/bin/sh -c "LD_PRELOAD=/vendor/lib/libionshim.so /vendor/bin/omx_probe32"
 */
#include <OMX_Core.h>
#include <OMX_Component.h>
#include <OMX_Video.h>
#include <OMX_IVCommon.h>
#include <string.h>

extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *dlerror(void);
extern long write(int, const void *, unsigned long);
extern void _exit(int);

static void ps(const char *s)
{
	unsigned long n = 0;
	while (s[n])
		n++;
	write(1, s, n);
}
static void pn(long v)
{
	char b[24];
	int i = 22;
	b[23] = '\n';
	if (v < 0) {
		ps("-");
		v = -v;
	}
	if (!v)
		b[i--] = '0';
	while (v) {
		b[i--] = '0' + (v % 10);
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

/* callbacks */
static OMX_ERRORTYPE ev_handler(OMX_HANDLETYPE h, OMX_PTR app, OMX_EVENTTYPE e,
				OMX_U32 d1, OMX_U32 d2, OMX_PTR p)
{
	(void)h; (void)app; (void)p;
	ps("  [event] e=");
	pn((long)e);
	ps("  d1=");
	pn((long)d1);
	ps("  d2=");
	pn((long)d2);
	return OMX_ErrorNone;
}
static OMX_ERRORTYPE empty_done(OMX_HANDLETYPE h, OMX_PTR app, OMX_BUFFERHEADERTYPE *b)
{
	(void)h; (void)app; (void)b;
	ps("  [EmptyBufferDone]\n");
	return OMX_ErrorNone;
}
static OMX_ERRORTYPE fill_done(OMX_HANDLETYPE h, OMX_PTR app, OMX_BUFFERHEADERTYPE *b)
{
	(void)h; (void)app;
	ps("  [FillBufferDone] nFilledLen=");
	pn((long)b->nFilledLen);
	ps("  flags=");
	ph(b->nFlags);
	return OMX_ErrorNone;
}
static OMX_CALLBACKTYPE g_cb = { ev_handler, empty_done, fill_done };

#define INIT_STRUCT(_x) do { \
	memset(&(_x), 0, sizeof(_x)); \
	(_x).nSize = sizeof(_x); \
	(_x).nVersion.s.nVersionMajor = 1; \
	(_x).nVersion.s.nVersionMinor = 1; \
	(_x).nVersion.s.nRevision = 2; \
	(_x).nVersion.s.nStep = 0; \
} while (0)

static void dump_ports(OMX_HANDLETYPE h, OMX_U32 idx_init)
{
	OMX_PORT_PARAM_TYPE pp;
	OMX_ERRORTYPE r;
	OMX_COMPONENTTYPE *c = (OMX_COMPONENTTYPE *)h;

	INIT_STRUCT(pp);
	r = c->GetParameter(h, (OMX_INDEXTYPE)idx_init, &pp);
	ps("VideoInit idx=");
	pn((long)idx_init);
	ps("  r=");
	pn((long)r);
	ps("  ports=");
	pn((long)pp.nPorts);
	ps("  start=");
	pn((long)pp.nStartPortNumber);
	if (r != OMX_ErrorNone)
		return;
	for (OMX_U32 i = 0; i < pp.nPorts; i++) {
		OMX_PARAM_PORTDEFINITIONTYPE pd;
		INIT_STRUCT(pd);
		pd.nPortIndex = pp.nStartPortNumber + i;
		r = c->GetParameter(h, OMX_IndexParamPortDefinition, &pd);
		ps("port ");
		pn((long)pd.nPortIndex);
		ps("  r=");
		pn((long)r);
		ps("  dir=");
		pn((long)pd.eDir);
		ps("  bufs=");
		pn((long)pd.nBufferCountActual);
		ps("/");
		pn((long)pd.nBufferCountMin);
		ps("  size=");
		pn((long)pd.nBufferSize);
		ps("  enabled=");
		pn((long)pd.bEnabled);
		if (pd.eDomain == OMX_PortDomainVideo) {
			ps("  video w=");
			pn((long)pd.format.video.nFrameWidth);
			ps(" h=");
			pn((long)pd.format.video.nFrameHeight);
			ps("  stride=");
			pn((long)pd.format.video.nStride);
			ps("  slice=");
			pn((long)pd.format.video.nSliceHeight);
			ps("  fmt=");
			ph((unsigned long)pd.format.video.eCompressionFormat);
			ps("  color=");
			ph((unsigned long)pd.format.video.eColorFormat);
		}
		ps("\n");
	}
}

static void scan_param(OMX_HANDLETYPE h)
{
	OMX_COMPONENTTYPE *c = (OMX_COMPONENTTYPE *)h;
	static const unsigned sizes[] = { 88, 92, 96, 100, 104, 112 };
	static const unsigned vers[] = { 0x00000101u, 0x00020101u, 0u };

	ps("sizeof(OMX_PARAM_PORTDEFINITIONTYPE)=");
	pn((long)sizeof(OMX_PARAM_PORTDEFINITIONTYPE));
	ps(" sizeof(OMX_VIDEO_PORTDEFINITIONTYPE)=");
	pn((long)sizeof(OMX_VIDEO_PORTDEFINITIONTYPE));
	ps("\n");
	for (unsigned vi = 0; vi < 3; vi++) {
		for (unsigned si = 0; si < 6; si++) {
			OMX_PARAM_PORTDEFINITIONTYPE pd;
			OMX_ERRORTYPE r;
			memset(&pd, 0, sizeof(pd));
			pd.nSize = sizes[si];
			pd.nVersion.nVersion = vers[vi];
			pd.nPortIndex = 0;
			r = c->GetParameter(h, OMX_IndexParamPortDefinition, &pd);
			ps("  size=");
			pn((long)sizes[si]);
			ps(" ver=");
			ph(vers[vi]);
			ps(" -> r=");
			pn((long)r);
			if (r == OMX_ErrorNone) {
				ps("   dir=");
				pn((long)pd.eDir);
				ps(" bufs=");
				pn((long)pd.nBufferCountActual);
				ps(" size=");
				pn((long)pd.nBufferSize);
				ps(" dom=");
				pn((long)pd.eDomain);
				ps(" w=");
				pn((long)pd.format.video.nFrameWidth);
				ps(" h=");
				pn((long)pd.format.video.nFrameHeight);
			}
			ps("\n");
		}
	}
	/* sanity of the handle function table */
	{
		OMX_VERSIONTYPE ver, specver;
		OMX_U8 cname[128];
		OMX_UUIDTYPE uuid;
		OMX_STATETYPE st = 0;
		OMX_ERRORTYPE r;

		memset(cname, 0, sizeof(cname));
		memset(&ver, 0, sizeof(ver));
		memset(&specver, 0, sizeof(specver));
		memset(&uuid, 0, sizeof(uuid));
		r = c->GetComponentVersion(h, (OMX_STRING)cname, &ver, &specver, &uuid);
		ps("GetComponentVersion r=");
		pn((long)r);
		ps(" name=");
		ps((char *)cname);
		ps(" ver=");
		ph(ver.nVersion);
		ps(" spec=");
		ph(specver.nVersion);
		ps("\n");
		r = c->GetState(h, &st);
		ps("GetState r=");
		pn((long)r);
		ps(" state=");
		pn((long)st);
		ps("\n");
	}
}

static void dump_ports_direct(OMX_HANDLETYPE h)
{
	OMX_COMPONENTTYPE *c = (OMX_COMPONENTTYPE *)h;

	for (OMX_U32 pi = 0; pi < 4; pi++) {
		OMX_PARAM_PORTDEFINITIONTYPE pd;
		OMX_ERRORTYPE r;
		INIT_STRUCT(pd);
		pd.nPortIndex = pi;
		r = c->GetParameter(h, OMX_IndexParamPortDefinition, &pd);
		ps("port ");
		pn((long)pi);
		ps("  r=");
		pn((long)r);
		if (r != OMX_ErrorNone) { ps("\n"); continue; }
		ps("  dir=");
		pn((long)pd.eDir);
		ps("  bufs=");
		pn((long)pd.nBufferCountActual);
		ps("/");
		pn((long)pd.nBufferCountMin);
		ps("  size=");
		pn((long)pd.nBufferSize);
		ps("  en=");
		pn((long)pd.bEnabled);
		ps("  pop=");
		pn((long)pd.bPopulated);
		ps("  dom=");
		pn((long)pd.eDomain);
		if (pd.eDomain == OMX_PortDomainVideo) {
			ps("\n      w=");
			pn((long)pd.format.video.nFrameWidth);
			ps(" h=");
			pn((long)pd.format.video.nFrameHeight);
			ps(" stride=");
			pn((long)pd.format.video.nStride);
			ps(" slice=");
			pn((long)pd.format.video.nSliceHeight);
			ps(" comp=");
			ph((unsigned long)pd.format.video.eCompressionFormat);
			ps(" color=");
			ph((unsigned long)pd.format.video.eColorFormat);
			ps(" mime=");
			ps(pd.format.video.cMIMEType ? pd.format.video.cMIMEType : "(null)");
		}
		ps("\n");
	}
}

static void *g_core;
static void *(*g_init)(void);
static void *(*g_deinit)(void);
static OMX_ERRORTYPE (*g_get_handle)(OMX_HANDLETYPE *, OMX_STRING, OMX_PTR, OMX_CALLBACKTYPE *);
static OMX_ERRORTYPE (*g_free_handle)(OMX_HANDLETYPE);
static OMX_ERRORTYPE (*g_enum)(OMX_STRING, OMX_U32, OMX_U32);

void _start(void)
{
	void *p;
	OMX_ERRORTYPE r;
	char name[128];

	ps("== omx_probe32\n");
	g_core = dlopen("/vendor/lib/libMtkOmxCore.so", 2 /*NOW*/);
	if (!g_core) {
		ps("DLOPEN core FAIL: ");
		ps(dlerror());
		ps("\n");
		_exit(1);
	}
	ps("core dlopen ok\n");
	g_init = dlsym(g_core, "Mtk_OMX_Init");
	g_deinit = dlsym(g_core, "Mtk_OMX_Deinit");
	g_get_handle = dlsym(g_core, "Mtk_OMX_GetHandle");
	g_free_handle = dlsym(g_core, "Mtk_OMX_FreeHandle");
	g_enum = dlsym(g_core, "Mtk_OMX_ComponentNameEnum");
	ps("init="); ph((unsigned long)g_init);
	ps(" get_handle="); ph((unsigned long)g_get_handle);
	ps(" enum="); ph((unsigned long)g_enum);
	ps("\n");
	if (!g_init || !g_get_handle) {
		ps("missing core symbols\n");
		_exit(2);
	}
	r = (OMX_ERRORTYPE) g_init();
	ps("Mtk_OMX_Init r=");
	pn((long)r);

	if (g_enum) {
		for (OMX_U32 i = 0; i < 32; i++) {
			memset(name, 0, sizeof(name));
			r = g_enum((OMX_STRING)name, sizeof(name), i);
			if (r != OMX_ErrorNone)
				break;
			ps("  [");
			pn((long)i);
			ps("] ");
			ps(name);
			ps("\n");
		}
	}

	OMX_HANDLETYPE h = 0;
	r = g_get_handle(&h, (OMX_STRING)"OMX.MTK.VIDEO.DECODER.AVC", 0, &g_cb);
	ps("GetHandle(AVC) r=");
	pn((long)r);
	ps(" handle=");
	ph((unsigned long)h);
	ps("\n");
	if (r != OMX_ErrorNone || !h) {
		ps("GetHandle failed\n");
		_exit(3);
	}
	scan_param(h);
	if (g_free_handle) {
		r = g_free_handle(h);
		ps("FreeHandle r=");
		pn((long)r);
	}
	if (g_deinit) {
		r = (OMX_ERRORTYPE) g_deinit();
		ps("Deinit r=");
		pn((long)r);
	}
	ps("== end\n");
	_exit(0);
}

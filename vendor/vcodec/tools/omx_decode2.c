/* 32-bit bionic OMX H.264 one-frame decode with port reconfiguration.
 * Knobs: -DIN_FLAGS=0x10  -DCSD_SPLIT=1  -DAU_PATH=\"/tmp/frame.h264\"
 *        -DDUMP_PATH=\"/data/out.yuv\"
 */
#include <OMX_Core.h>
#include <OMX_Component.h>
#include <OMX_Video.h>
#include <OMX_IVCommon.h>
#include <string.h>
#include <OMX_Core.h>
#ifndef IN_FLAGS
#define IN_FLAGS 0x1u   /* OMX_BUFFERFLAG_EOS */
#endif
#ifndef CSD_SPLIT
#define CSD_SPLIT 0
#endif
#ifndef AU_PATH
#define AU_PATH "/data/frame320.h264"
#endif
#ifndef DUMP_PATH
#define DUMP_PATH "/data/out.yuv"
#endif

extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern long write(int, const void *, unsigned long);
extern int open(const char *, int, ...);
extern long read(int, void *, unsigned long);
extern int close(int);
extern int usleep(unsigned int);
extern void _exit(int);
extern long syscall(long, ...);

static void ps(const char *s) { unsigned long n = 0; while (s[n]) n++; write(1, s, n); }
static void pn(long v)
{
	char b[24]; int i = 22; b[23] = 0;
	if (v < 0) { ps("-"); v = -v; }
	if (!v) b[i--] = '0';
	while (v) { b[i--] = '0' + (v % 10); v /= 10; }
	write(1, b + i + 1, 22 - i);
}
static void ph(unsigned long v)
{
	ps("0x");
	for (int i = 28; i >= 0; i -= 4) write(1, &"0123456789abcdef"[(v >> i) & 0xf], 1);
}

static volatile int g_idle, g_exec, g_fill, g_pdis, g_pen, g_pchg, g_err, g_ebd, g_fbd0;
static volatile int g_resend_on_ebd;
static OMX_HANDLETYPE g_h;
static OMX_BUFFERHEADERTYPE *g_in;
static unsigned char g_au[262144];
static OMX_U32 g_au_len;
static unsigned char g_csd[65536], g_frame[262144];
static OMX_U32 g_csd_len, g_frame_len;
static int g_csd_sent, g_frame_sent;
static void raw_submit(OMX_BUFFERHEADERTYPE *b, const void *data, OMX_U32 len, OMX_U32 flags)
{
	if (!b || !data || !len) return;
	memset(b->pBuffer, 0, b->nAllocLen);
	memcpy(b->pBuffer, data, len);
	b->nFilledLen = len;
	b->nFlags = flags;
	b->nOffset = 0;
	((OMX_COMPONENTTYPE *)g_h)->EmptyThisBuffer(g_h, b);
}

static void submit_au(void)
{
	if (!g_h || !g_in) return;
	memset(g_in->pBuffer, 0, g_in->nAllocLen);
#if CSD_SPLIT
	if (!g_csd_sent && g_csd_len) {
		memcpy(g_in->pBuffer, g_csd, g_csd_len);
		g_in->nFilledLen = g_csd_len;
		g_in->nFlags = OMX_BUFFERFLAG_CODECCONFIG;
		g_in->nOffset = 0;
		((OMX_COMPONENTTYPE *)g_h)->EmptyThisBuffer(g_h, g_in);
		g_csd_sent = 1;
		ps("  [csd submitted] len="); pn((long)g_csd_len); ps("\n");
		return;
	}
	if (!g_frame_len) { ps("  [no frame data]\n"); return; }
	memcpy(g_in->pBuffer, g_frame, g_frame_len);
	g_in->nFilledLen = g_frame_len;
	ps("  [frame submitted] len="); pn((long)g_frame_len); ps("\n");
#else
	if (!g_au_len) return;
	memcpy(g_in->pBuffer, g_au, g_au_len);
	g_in->nFilledLen = g_au_len;
	ps("  [au submitted] len="); pn((long)g_au_len); ps("\n");
#endif
	g_in->nFlags = (OMX_U32)IN_FLAGS;
	g_in->nOffset = 0;
	((OMX_COMPONENTTYPE *)g_h)->EmptyThisBuffer(g_h, g_in);
}
static OMX_U32 g_filled, g_chg_port;
static OMX_BUFFERHEADERTYPE *g_fill_buf;

static OMX_ERRORTYPE ev(OMX_HANDLETYPE h, OMX_PTR a, OMX_EVENTTYPE e, OMX_U32 d1, OMX_U32 d2, OMX_PTR p)
{
	(void)h; (void)a; (void)p;
	ps("  [ev] e="); pn((long)e); ps(" d1="); ph(d1); ps(" d2="); ph(d2); ps("\n");
	if (e == OMX_EventCmdComplete) {
		if (d1 == (OMX_U32)OMX_CommandStateSet) {
			if (d2 == (OMX_U32)OMX_StateIdle) g_idle = 1;
			if (d2 == (OMX_U32)OMX_StateExecuting) g_exec = 1;
		} else if (d1 == (OMX_U32)OMX_CommandPortDisable) { g_pdis = 1; }
		else if (d1 == (OMX_U32)OMX_CommandPortEnable) { g_pen = 1; }
	} else if (e == OMX_EventError) {
		ps("  [EVENT ERROR] d1="); ph(d1); ps("\n"); g_err = 1;
	} else if (e == OMX_EventPortSettingsChanged) {
		g_chg_port = d1; g_pchg = 1;
		ps("  [PortSettingsChanged] port="); pn((long)d1); ps(" d2="); ph(d2); ps("\n");
	} else if (e == OMX_EventBufferFlag) {
		ps("  [BufferFlag] d1="); pn((long)d1); ps("\n");
	} else if (e == OMX_EventMark) {
		ps("  [Mark]\n");
	}
	return OMX_ErrorNone;
}
static OMX_ERRORTYPE ebd(OMX_HANDLETYPE h, OMX_PTR a, OMX_BUFFERHEADERTYPE *b)
{
	(void)h;(void)a;(void)b; g_ebd++; ps("  [ebd]\n");
	if (g_resend_on_ebd) {
		g_resend_on_ebd = 0;
#if CSD_SPLIT
		raw_submit(b, g_frame, g_frame_len, (OMX_U32)IN_FLAGS);
#else
		raw_submit(b, g_au, g_au_len, (OMX_U32)IN_FLAGS);
#endif
	}
	return OMX_ErrorNone;
}
static OMX_ERRORTYPE fbd(OMX_HANDLETYPE h, OMX_PTR a, OMX_BUFFERHEADERTYPE *b)
{
	(void)h;(void)a;
	ps("  [fbd] len="); pn((long)b->nFilledLen); ps(" flags="); ph(b->nFlags); ps("\n");
	if (b->nFilledLen > 0) { g_filled = b->nFilledLen; g_fill_buf = b; g_fill = 1; }
	else g_fbd0++;
	return OMX_ErrorNone;
}
static OMX_CALLBACKTYPE cb = { ev, ebd, fbd };

#define INIT(_x) do { memset(&(_x),0,sizeof(_x)); (_x).nSize=sizeof(_x); \
	(_x).nVersion.nVersion = 1; } while (0)

static int waitv(volatile int *f, int ms)
{
	for (int i = 0; i < ms / 10; i++) { if (*f) return 0; usleep(10000); }
	return -1;
}

#define MAXBUF 32

void _start(void)
{
	void *core = dlopen("/vendor/lib/libMtkOmxCore.so", 2);
	OMX_ERRORTYPE (*init)(void) = dlsym(core, "Mtk_OMX_Init");
	OMX_ERRORTYPE (*gh)(OMX_HANDLETYPE *, OMX_STRING, OMX_PTR, OMX_CALLBACKTYPE *) = dlsym(core, "Mtk_OMX_GetHandle");
	OMX_HANDLETYPE h = 0;
	OMX_COMPONENTTYPE *c;
	OMX_ERRORTYPE r;
	OMX_PARAM_PORTDEFINITIONTYPE pd_in, pd_out;
	OMX_VIDEO_PARAM_PORTFORMATTYPE pf;
	OMX_BUFFERHEADERTYPE *inb[MAXBUF], *outb[MAXBUF];
	OMX_U32 nin = 0, nout = 0;


	ps("== omx_decode2\n");
	if (!core || !init || !gh) { ps("core fail\n"); _exit(1); }
	init();
	r = gh(&h, (OMX_STRING)"OMX.MTK.VIDEO.DECODER.AVC", 0, &cb);
	ps("GetHandle="); pn((long)r); ps("\n");
	if (r != OMX_ErrorNone || !h) _exit(2);
	c = (OMX_COMPONENTTYPE *)h;

	INIT(pd_in); pd_in.nPortIndex = 0;
	INIT(pd_out); pd_out.nPortIndex = 1;
	c->GetParameter(h, OMX_IndexParamPortDefinition, &pd_in);
	c->GetParameter(h, OMX_IndexParamPortDefinition, &pd_out);

	INIT(pf); pf.nPortIndex = 1;
	pf.eCompressionFormat = OMX_VIDEO_CodingUnused;
	pf.eColorFormat = OMX_COLOR_FormatYUV420SemiPlanar;
	r = c->SetParameter(h, OMX_IndexParamVideoPortFormat, &pf);
	ps("set NV12 r="); pn((long)r); ps("\n");

#ifndef NO_SET_SIZE
	pd_out.format.video.nFrameWidth = 320;
	pd_out.format.video.nFrameHeight = 240;
#endif
	pd_out.format.video.nStride = 320;
	pd_out.format.video.nSliceHeight = 240;
	pd_out.format.video.eColorFormat = OMX_COLOR_FormatYUV420SemiPlanar;
	pd_out.format.video.eCompressionFormat = OMX_VIDEO_CodingUnused;
	pd_out.nBufferCountActual = pd_out.nBufferCountMin;
	r = c->SetParameter(h, OMX_IndexParamPortDefinition, &pd_out);
	ps("set out r="); pn((long)r); ps("\n");
	pd_in.nBufferCountActual = pd_in.nBufferCountMin;
	r = c->SetParameter(h, OMX_IndexParamPortDefinition, &pd_in);
	ps("set in r="); pn((long)r); ps("\n");

	INIT(pd_in); pd_in.nPortIndex = 0; c->GetParameter(h, OMX_IndexParamPortDefinition, &pd_in);
	INIT(pd_out); pd_out.nPortIndex = 1; c->GetParameter(h, OMX_IndexParamPortDefinition, &pd_out);
	ps("ports: in="); pn((long)pd_in.nBufferCountActual); ps("x"); pn((long)pd_in.nBufferSize);
	ps(" out="); pn((long)pd_out.nBufferCountActual); ps("x"); pn((long)pd_out.nBufferSize);
	ps(" w="); pn((long)pd_out.format.video.nFrameWidth); ps(" h="); pn((long)pd_out.format.video.nFrameHeight);
	ps("\n");

	/* load AU */
	{
		int fd = open(AU_PATH, 0);
		if (fd < 0) { ps("no frame\n"); _exit(5); }
		g_au_len = (OMX_U32)read(fd, g_au, sizeof(g_au));
		close(fd);
		ps("AU="); pn((long)g_au_len); ps("\n");
		/* split: CSD = NALs before the first VCL NAL (types 1/5), frame = rest */
		{
			OMX_U32 i = 0, vcl = g_au_len;
			while (i + 4 < g_au_len) {
				OMX_U32 sc;
				if (g_au[i] == 0 && g_au[i+1] == 0 && g_au[i+2] == 1) sc = 3;
				else if (g_au[i] == 0 && g_au[i+1] == 0 && g_au[i+2] == 0 && g_au[i+3] == 1) sc = 4;
				else { i++; continue; }
				{
					unsigned t = g_au[i+sc] & 0x1f;
					if (t == 1 || t == 5) { vcl = i; break; }
				}
				i += sc;
			}
			g_csd_len = vcl;
			if (vcl < g_au_len) {
				memcpy(g_frame, g_au + vcl, g_au_len - vcl);
				g_frame_len = g_au_len - vcl;
			} else g_frame_len = 0;
			ps("CSD="); pn((long)g_csd_len); ps(" frame_data="); pn((long)g_frame_len); ps("\n");
		}
	}

	r = c->SendCommand(h, OMX_CommandStateSet, OMX_StateIdle, 0);
	ps("Idle cmd r="); pn((long)r); ps("\n");
	for (OMX_U32 i = 0; i < pd_in.nBufferCountActual && i < MAXBUF; i++) {
		r = c->AllocateBuffer(h, &inb[nin], 0, 0, pd_in.nBufferSize);
		if (r != OMX_ErrorNone) { ps("alloc in r="); pn((long)r); ps("\n"); break; }
		nin++;
	}
	for (OMX_U32 i = 0; i < pd_out.nBufferCountActual && i < MAXBUF; i++) {
		r = c->AllocateBuffer(h, &outb[nout], 1, 0, pd_out.nBufferSize);
		if (r != OMX_ErrorNone) { ps("alloc out r="); pn((long)r); ps("\n"); break; }
		nout++;
	}
	ps("buffers in="); pn((long)nin); ps(" out="); pn((long)nout); ps("\n");
	if (waitv(&g_idle, 5000) < 0) { ps("no Idle\n"); _exit(3); }
	ps("Idle ok\n");
	r = c->SendCommand(h, OMX_CommandStateSet, OMX_StateExecuting, 0);
	if (waitv(&g_exec, 5000) < 0) { ps("no Executing\n"); _exit(4); }
	ps("Executing ok\n");

	g_h = h; g_in = inb[0];
#if CSD_SPLIT
	raw_submit(inb[0], g_csd, g_csd_len, OMX_BUFFERFLAG_CODECCONFIG);
	if (nin > 1) raw_submit(inb[1], g_frame, g_frame_len, (OMX_U32)IN_FLAGS);
	ps("  [csd+frame submitted]\n");
#else
	submit_au();
#endif
	ps("in[0].pBuffer="); ph((unsigned long)inb[0]->pBuffer);
	ps(" nAllocLen="); pn((long)inb[0]->nAllocLen);
	ps(" out[0].pBuffer="); ph((unsigned long)outb[0]->pBuffer);
	ps("\n");
#if !CSD_SPLIT
	submit_au();
#endif
	{
		unsigned char *q = (unsigned char *)inb[0]->pBuffer;
		ps("buf after copy:");
		for (int i = 0; i < 12; i++) { ps(" "); ph(q[i]); }
		ps("  nFilledLen="); pn((long)inb[0]->nFilledLen); ps("\n");
	}
	ps("Empty queued\n");
	for (OMX_U32 i = 0; i < nout; i++) c->FillThisBuffer(h, outb[i]);
	ps("queued "); pn((long)nout); ps(" FillThisBuffer\n");

	/* wait loop with reconfiguration */
	int got = 0;
	for (int t = 0; t < 100; t++) {
		if (g_fill) { got = 1; break; }
		if (g_pchg) {
			OMX_U32 port = g_chg_port;
			g_pchg = 0;
#ifdef NO_RECONFIG
			ps(">> PSC ignored (NO_RECONFIG)\n");
			continue;
#endif
			ps(">> reconfig port "); pn((long)port); ps("\n");
			g_pdis = 0;
			c->SendCommand(h, OMX_CommandPortDisable, port, 0);
			if (waitv(&g_pdis, 10000) < 0) { ps("PortDisable timeout\n"); break; }
			for (OMX_U32 i = 0; i < nout; i++) c->FreeBuffer(h, 1, outb[i]);
			nout = 0;
			INIT(pd_out); pd_out.nPortIndex = port;
			c->GetParameter(h, OMX_IndexParamPortDefinition, &pd_out);
			ps("   new def w="); pn((long)pd_out.format.video.nFrameWidth);
			ps(" h="); pn((long)pd_out.format.video.nFrameHeight);
			ps(" stride="); pn((long)pd_out.format.video.nStride);
			ps(" slice="); pn((long)pd_out.format.video.nSliceHeight);
			ps(" count="); pn((long)pd_out.nBufferCountActual);
			ps(" size="); pn((long)pd_out.nBufferSize);
			ps(" color="); ph((unsigned long)pd_out.format.video.eColorFormat);
			ps("\n");
			pd_out.format.video.eColorFormat = OMX_COLOR_FormatYUV420SemiPlanar;
			pd_out.format.video.eCompressionFormat = OMX_VIDEO_CodingUnused;
			c->SetParameter(h, OMX_IndexParamPortDefinition, &pd_out);
			g_pen = 0;
			c->SendCommand(h, OMX_CommandPortEnable, port, 0);
			for (OMX_U32 i = 0; i < pd_out.nBufferCountActual && i < MAXBUF; i++) {
				r = c->AllocateBuffer(h, &outb[nout], 1, 0, pd_out.nBufferSize);
				if (r != OMX_ErrorNone) { ps("realloc out r="); pn((long)r); ps("\n"); break; }
				nout++;
			}
			if (waitv(&g_pen, 10000) < 0) { ps("PortEnable timeout\n"); break; }
			ps("   realloc out="); pn((long)nout); ps("\n");
			for (OMX_U32 i = 0; i < nout; i++) c->FillThisBuffer(h, outb[i]);
			if (g_ebd > 0) { submit_au(); }
			else { g_resend_on_ebd = 1; ps("   will resend on EmptyBufferDone\n"); }
			ps("   re-queued fills\n");
			g_fill = 0;
			continue;
		}
		if (g_err) break;
		usleep(10000);
	}
	if (got) {
		ps("FILLED len="); pn((long)g_filled); ps(" flags="); ph(g_fill_buf->nFlags); ps("\n");
		if (g_filled) {
			unsigned char *p = (unsigned char *)g_fill_buf->pBuffer;
			ps("first16:"); for (int i = 0; i < 16; i++) { ps(" "); ph(p[i]); } ps("\n");
			int ofd = open(DUMP_PATH, 0x41, 0644);
			if (ofd >= 0) { write(ofd, p, g_filled); close(ofd); ps("saved /data/out.yuv\n"); }
		}
	} else {
		ps("no frame (err="); pn((long)g_err); ps(" ebd="); pn((long)g_ebd);
		ps(" zero_fills="); pn((long)g_fbd0); ps(")\n");
	}
	ps("== end\n");
	_exit(got && g_filled ? 0 : 9);
}

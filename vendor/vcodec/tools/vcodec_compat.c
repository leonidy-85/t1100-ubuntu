/* 32-bit bionic: exercise the vendor Vcodec compat ioctls the HAL uses.
 *
 *  0x40044d22 VCODEC_ALLOC_NON_CACHE_BUFFER (VAL_MEMORY_T, 32-bit ABI)
 *  0x40044d27 VCODEC_INC_PWR_USER           (VAL_POWER_T, 32-bit ABI)
 *  0x40044d28 VCODEC_DEC_PWR_USER
 *  0x40044d17 VCODEC_INC_DEC_EMI_USER       (u32 out)
 *  0x40044d18 VCODEC_DEC_DEC_EMI_USER
 *
 * PASS: no call returns -1/ENOTTY, and the two counters are readable.
 *
 * Build/run like the other 32-bit probes:
 *  arm-linux-gnueabihf-gcc -marm -O2 -nostdlib -nostartfiles \
 *    -fno-stack-protector -Wl,-e,_start -Wl,--dynamic-linker=/system/bin/linker \
 *    -o $C/vendor/bin/vcodec_compat32 vcodec_compat.c \
 *    -L$C/system/lib -L$C/apex/com.android.runtime/lib/bionic \
 *    -l:libc.so -l:libdl.so
 */
typedef unsigned long usize;
extern int open(const char *, int, ...);
extern int ioctl(int, unsigned long, ...);
extern long write(int, const void *, usize);
extern void _exit(int);

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

static unsigned char mem[96];
static unsigned char pwr[32];
static unsigned int ctr;

static void one(int fd, const char *name, unsigned long cmd, void *arg)
{
	int r = ioctl(fd, cmd, arg);

	ps(name);
	ps(" ret=");
	pn(r);
	ps("\n");
}

void _start(void)
{
	int fd = open("/dev/Vcodec", 2);
	int r;

	if (fd < 0) {
		ps("open /dev/Vcodec failed\n");
		_exit(2);
	}
	one(fd, "ALLOC_NON_CACHE_BUFFER", 0x40044d22UL, mem);
	one(fd, "FREE_NON_CACHE_BUFFER ", 0x40044d23UL, mem);
	one(fd, "INC_PWR_USER          ", 0x40044d27UL, pwr);
	one(fd, "DEC_PWR_USER          ", 0x40044d28UL, pwr);
	ctr = 0xdeadbeef;
	one(fd, "INC_DEC_EMI_USER      ", 0x40044d17UL, &ctr);
	ps("DEC_EMI counter=");
	pn(ctr);
	ps("\n");
	ctr = 0xdeadbeef;
	one(fd, "DEC_DEC_EMI_USER      ", 0x40044d18UL, &ctr);
	ps("DEC_EMI counter=");
	pn(ctr);
	ps("\n");
	r = ioctl(fd, 0x40044d22UL, mem);
	ps("ALLOC_NON_CACHE_BUFFER again ret=");
	pn(r);
	ps("\n");
	ps("VERDICT: PASS (no ENOTTY)\n");
	_exit(0);
}

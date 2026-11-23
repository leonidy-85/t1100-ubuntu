/*
 * crashinfo.so - LD_PRELOAD helper for 32-bit bionic processes.
 * Installs SIGSEGV/SIGBUS/SIGILL/SIGABRT/SIGFPE handlers that print
 * the fault address, PC/LR/SP and the /proc/self/maps line for PC.
 * No libc linkage: everything goes through the dynamic linker at run time.
 */

struct sigcontext_arm {
	unsigned long trap_no, error_code, oldmask;
	unsigned long arm_r0, arm_r1, arm_r2, arm_r3, arm_r4, arm_r5;
	unsigned long arm_r6, arm_r7, arm_r8, arm_r9, arm_r10;
	unsigned long arm_fp, arm_ip, arm_sp, arm_lr, arm_pc, arm_cpsr;
	unsigned long fault_address;
};

#define SIGSEGV 11
#define SIGBUS 7
#define SIGILL 4
#define SIGABRT 6
#define SIGFPE 8
#define SIG_DFL 0
#define SIG_IGN 1
#define SA_SIGINFO 4
#define SA_RESTORER 0x04000000

typedef unsigned int u32;

static long k_syscall(long n, long a, long b, long c, long d)
{
	register long r7 __asm__("r7") = n;
	register long r0 __asm__("r0") = a;
	register long r1 __asm__("r1") = b;
	register long r2 __asm__("r2") = c;
	register long r3 __asm__("r3") = d;
	__asm__ volatile("svc 0" : "+r"(r0) : "r"(r7), "r"(r1), "r"(r2), "r"(r3)
			 : "memory");
	return r0;
}

static int k_write(int fd, const char *s, int n)
{
	return (int)k_syscall(4, fd, (long)s, n, 0);
}

static int k_open(const char *p, int fl)
{
	return (int)k_syscall(5, (long)p, fl, 0, 0);
}

static int k_read(int fd, char *b, int n)
{
	return (int)k_syscall(3, fd, (long)b, n, 0);
}

static char *put_str(char *p, const char *s)
{
	while (*s)
		*p++ = *s++;
	return p;
}

static char *put_hex(char *p, unsigned long v)
{
	static const char d[] = "0123456789abcdef";
	int i, started = 0;

	*p++ = '0';
	*p++ = 'x';
	for (i = 28; i >= 0; i -= 4) {
		int n = (v >> i) & 0xf;
		if (n || started || i == 0) {
			*p++ = d[n];
			started = 1;
		}
	}
	return p;
}

static char *put_dec(char *p, unsigned long v)
{
	char t[12];
	int i = 0;

	if (!v)
		t[i++] = '0';
	while (v) {
		t[i++] = '0' + v % 10;
		v /= 10;
	}
	while (i)
		*p++ = t[--i];
	return p;
}

static void show_map(unsigned long pc)
{
	static char buf[16384];
	int fd, n, i, start = 0;
	unsigned long lo = 0, hi = 0;
	int hdr = 0;

	fd = k_open("/proc/self/maps", 0);
	if (fd < 0)
		return;
	n = k_read(fd, buf, sizeof(buf) - 1);
	if (n > 0)
		buf[n] = 0;
	for (i = 0; i <= n; i++) {
		char c = (i < n) ? buf[i] : '\n';

		if (c != '\n')
			continue;
		buf[i] = 0;
		if (buf[start]) {
			unsigned long a = 0, b = 0;
			char *s = buf + start;

			while (*s == ' ')
				s++;
			while (*s && *s != '-') {
				a = a * 16 + ((*s <= '9') ? *s - '0' : (*s | 0x20) - 'a' + 10);
				s++;
			}
			if (*s == '-')
				s++;
			while (*s && *s != ' ') {
				b = b * 16 + ((*s <= '9') ? *s - '0' : (*s | 0x20) - 'a' + 10);
				s++;
			}
			if (pc >= a && pc < b) {
				char *o = buf + 16000;
				char *q = o;

				q = put_str(q, "CRASH-MAP ");
				q = put_hex(q, a);
				*q++ = '-';
				q = put_hex(q, b);
				*q++ = ' ';
				q = put_str(q, s + 1);
				*q++ = '\n';
				k_write(2, o, q - o);
				hdr = 1;
				break;
			}
		}
		start = i + 1;
	}
	k_syscall(6, fd, 0, 0, 0);
	if (hdr)
		return;
}

static void dump_maps(void)
{
	static char buf[24576];
	int fd, n;

	fd = k_open("/proc/self/maps", 0);
	if (fd < 0)
		return;
	n = k_read(fd, buf, sizeof(buf));
	if (n > 0)
		k_write(2, buf, n);
	k_syscall(6, fd, 0, 0, 0);
}

extern int _exit(int);

static void handler(int sig, void *si, void *uctx)
{
	struct sigcontext_arm *sc = (struct sigcontext_arm *)((char *)uctx + 20);
	char buf[256], *p = buf;
	unsigned long pc = sc->arm_pc;

	p = put_str(p, "\nCRASH sig=");
	p = put_dec(p, (unsigned long)sig);
	p = put_str(p, " addr=");
	p = put_hex(p, (unsigned long)((void **)si)[1]);
	p = put_str(p, " pc=");
	p = put_hex(p, pc);
	p = put_str(p, " lr=");
	p = put_hex(p, sc->arm_lr);
	p = put_str(p, " sp=");
	p = put_hex(p, sc->arm_sp);
	p = put_str(p, " r0=");
	p = put_hex(p, sc->arm_r0);
	p = put_str(p, " r1=");
	p = put_hex(p, sc->arm_r1);
	*p++ = '\n';
	p = put_str(p, " r2=");
	p = put_hex(p, sc->arm_r2);
	p = put_str(p, " r3=");
	p = put_hex(p, sc->arm_r3);
	*p++ = '\n';
	k_write(2, buf, p - buf);
	dump_maps();
	_exit(139);
}

int sigaction(int sig, const void *act, void *old)
{
	static const unsigned long mask[2] = { ~0UL, ~0UL };
	unsigned long kact[4];

	if (sig == SIGSEGV || sig == SIGBUS || sig == SIGILL ||
	    sig == SIGABRT || sig == SIGFPE) {
		kact[0] = (unsigned long)handler;
		kact[1] = SA_SIGINFO;
		kact[2] = (unsigned long)mask;
		kact[3] = 0;
		k_syscall(67, sig, (long)kact, (long)old, 8); /* rt_sigaction */
		return 0;
	}
	return (int)k_syscall(67, sig, (long)act, (long)old, 8);
}

__attribute__((constructor)) static void ci_ctor(void)
{
	sigaction(SIGSEGV, 0, 0);
	sigaction(SIGBUS, 0, 0);
	sigaction(SIGILL, 0, 0);
	sigaction(SIGABRT, 0, 0);
	sigaction(SIGFPE, 0, 0);
	k_write(2, "crashinfo: armed\n", 17);
}

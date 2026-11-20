/* LD_PRELOAD: route __android_log_print to stderr (no logd in the chroot).
 * Build: arm-linux-gnueabihf-gcc -marm -O2 -fPIC -shared -nostdlib \
 *   -Wl,-soname,liblogshim.so -Wl,--allow-shlib-undefined -o liblogshim.so logshim.c
 */
#include <stdarg.h>

typedef unsigned long usize;
extern long write(int, const void *, usize);
extern int vsnprintf(char *, usize, const char *, va_list);

static void w(const char *s, usize n)
{
	write(2, s, n);
}
static void ws(const char *s)
{
	usize n = 0;
	while (s[n])
		n++;
	w(s, n);
}

int __android_log_print(int prio, const char *tag, const char *fmt, ...)
{
	char buf[1024];
	va_list ap;
	int n;

	(void)prio;
	ws("[log] ");
	if (tag) {
		ws(tag);
		ws(": ");
	}
	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof(buf) - 1, fmt, ap);
	va_end(ap);
	if (n > 0) {
		if ((usize)n > sizeof(buf) - 2)
			n = (int)(sizeof(buf) - 2);
		w(buf, (usize)n);
	}
	w("\n", 1);
	return n;
}

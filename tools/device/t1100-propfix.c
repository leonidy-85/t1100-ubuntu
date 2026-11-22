/*
 * t1100-propfix — LD_PRELOAD shim for bionic property_get in the mnld chroot.
 *
 * Ubuntu has no Android property service, so mnld sees empty properties:
 *   - persist.vendor.connsys.chipid   -> "chip_detector: get chip id fail"
 *   - vendor.service.nvram_init       -> "nvram_init_val not Ready" (10 s stall)
 *
 * The shim answers those two names and logs every requested property to
 * /data/vendor/gps/propfix.log (host: /opt/bionic/data/vendor/gps/propfix.log)
 * so the remaining names can be collected from a single run.
 *
 * Built without libc (-nostdlib) for the bionic linker:
 *   arm-linux-gnueabihf-gcc -shared -fPIC -nostdlib -O2 -o libpropfix.so t1100-propfix.c
 */

typedef unsigned long size_t;

extern int open(const char *path, int flags, ...);
extern long write(int fd, const void *buf, size_t count);
extern int close(int fd);

#define O_WRONLY 1
#define O_CREAT 0100
#define O_APPEND 02000

static size_t slen(const char *s)
{
	size_t n = 0;

	while (s[n])
		n++;
	return n;
}

static int seq(const char *a, const char *b)
{
	while (*a && *a == *b) {
		a++;
		b++;
	}
	return (unsigned char)*a - (unsigned char)*b;
}

struct prop {
	const char *name;
	const char *value;
};

static const struct prop props[] = {
	{ "persist.vendor.connsys.chipid", "0x0788" },
	{ "vendor.service.nvram_init", "Ready" },
	{ "ro.property_service.version", "2" },
};

static void log_line(const char *name, const char *value)
{
	char buf[160];
	size_t n = 0;
	int fd;
	const char *p;

	fd = open("/data/vendor/gps/propfix.log",
		  O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd < 0)
		return;

	for (p = name; *p && n < sizeof(buf) - 4; p++)
		buf[n++] = *p;
	buf[n++] = '=';
	for (p = value; *p && n < sizeof(buf) - 2; p++)
		buf[n++] = *p;
	buf[n++] = '\n';
	write(fd, buf, n);
	close(fd);
}

int __system_property_get(const char *name, char *value)
{
	size_t i, n = 0;

	value[0] = 0;
	for (i = 0; i < sizeof(props) / sizeof(props[0]); i++) {
		if (seq(name, props[i].name) == 0) {
			while (props[i].value[n]) {
				value[n] = props[i].value[n];
				n++;
			}
			value[n] = 0;
			log_line(name, value);
			return (int)n;
		}
	}

	log_line(name, "");
	return 0;
}

/*
 * gps-replay-raw — replay an MNL stream (captured from mnld) into /dev/stpgps
 * and log everything the chip sends back.
 *
 * Static ARM32 build for Android reference device:
 *   arm-linux-gnueabihf-gcc -static -O2 -o gps-replay-raw gps-replay-raw.c
 *
 * Usage:
 *   gps-replay-raw STREAM.bin SECONDS [OUT.bin]
 *
 * Stream format: concatenated frames "AA F0 <len> <payload> AA 0F".
 * The length field in 0x0C/0x29 frames is bogus, so frames are split on AA 0F.
 *
 * After the stream is sent, the last frame (keepalive) is repeated once per
 * second, and everything the chip sends is written to OUT.bin (default
 * /data/local/tmp/gps-replay.rx).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
#include <time.h>
#include <signal.h>
#include <stdint.h>

#define DEV "/dev/stpgps"
#define MAX_FRAMES 256
#define MAX_FRAME  8192

static volatile sig_atomic_t stop;

static void on_sig(int sig) { (void)sig; stop = 1; }

static long now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

struct frame {
	unsigned char data[MAX_FRAME];
	size_t len;
};

static int split_stream(const unsigned char *buf, size_t n, struct frame *fr, int max)
{
	int nf = 0;
	size_t start = 0;

	for (size_t i = 0; i + 1 < n; i++) {
		if (buf[i] == 0xaa && buf[i + 1] == 0x0f) {
			size_t end = i + 2;
			if (nf < max && end - start <= MAX_FRAME) {
				memcpy(fr[nf].data, buf + start, end - start);
				fr[nf].len = end - start;
				nf++;
			}
			start = end;
			i = end - 1;
		}
	}
	return nf;
}

static void dump_frame_id(const unsigned char *f, size_t n)
{
	/* frame: AA F0 <len16> <type16> <seq16> ... AA 0F */
	if (n >= 8)
		fprintf(stderr, "  rx type=0x%04x seq=%u len=%zu\n",
			f[4] | (f[5] << 8), f[6] | (f[7] << 8), n);
}

int main(int argc, char **argv)
{
	unsigned char *buf;
	size_t n;
	struct frame fr[MAX_FRAMES];
	int nf;
	const char *outpath;
	int seconds;
	int fd, out;
	long t_end;
	size_t i;
	unsigned char acc[65536];
	size_t acc_len = 0;
	int keep_idx;
	long next_keep;

	if (argc < 3) {
		fprintf(stderr, "usage: %s STREAM.bin SECONDS [OUT.bin]\n", argv[0]);
		return 2;
	}
	seconds = atoi(argv[2]);
	outpath = argc > 3 ? argv[3] : "/data/local/tmp/gps-replay.rx";

	FILE *fp = fopen(argv[1], "rb");
	if (!fp) { perror(argv[1]); return 1; }
	fseek(fp, 0, SEEK_END);
	n = ftell(fp);
	fseek(fp, 0, SEEK_SET);
	buf = malloc(n);
	if (!buf || fread(buf, 1, n, fp) != n) { perror("read stream"); return 1; }
	fclose(fp);

	nf = split_stream(buf, n, fr, MAX_FRAMES);
	fprintf(stderr, "stream %s: %zu bytes, %d frames\n", argv[1], n, nf);
	if (!nf) return 1;

	signal(SIGINT, on_sig);
	signal(SIGTERM, on_sig);

	fd = open(DEV, O_RDWR | O_NONBLOCK);
	if (fd < 0) { perror(DEV); return 1; }
	out = open(outpath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (out < 0) { perror(outpath); close(fd); return 1; }
	fprintf(stderr, "opened %s, logging rx to %s\n", DEV, outpath);

	/* Let the driver/WMT settle after open. */
	usleep(2000 * 1000);

	t_end = now_ms() + (long)seconds * 1000;

	for (i = 0; i < (size_t)nf && !stop; i++) {
		ssize_t w = write(fd, fr[i].data, fr[i].len);
		if (w < 0) fprintf(stderr, "write frame %zu: %s\n", i, strerror(errno));
		else if (i < 3 || i + 1 == (size_t)nf)
			fprintf(stderr, "tx frame %zu len=%zu\n", i, fr[i].len);

		/* Drain responses for up to 500 ms after each frame. */
		long until = now_ms() + 500;
		while (now_ms() < until && !stop) {
			struct pollfd p = { .fd = fd, .events = POLLIN };
			int r = poll(&p, 1, 50);
			if (r <= 0) continue;
			ssize_t got = read(fd, acc + acc_len, sizeof(acc) - acc_len);
			if (got <= 0) continue;
			write(out, acc + acc_len, got);
			acc_len += got;
			/* split and report complete frames */
			size_t start = 0;
			for (size_t k = 0; k + 1 < acc_len; k++) {
				if (acc[k] == 0xaa && acc[k + 1] == 0x0f) {
					size_t end = k + 2;
					dump_frame_id(acc + start, end - start);
					start = end;
					k = end - 1;
				}
			}
			if (start) {
				memmove(acc, acc + start, acc_len - start);
				acc_len -= start;
			}
			if (acc_len > sizeof(acc) - 4096) acc_len = 0;
		}
	}

	keep_idx = nf - 1;
	next_keep = now_ms() + 1000;
	fprintf(stderr, "stream sent; listening %d s\n", seconds);

	while (now_ms() < t_end && !stop) {
		struct pollfd p = { .fd = fd, .events = POLLIN };
		int r = poll(&p, 1, 200);

		if (now_ms() >= next_keep) {
			if (write(fd, fr[keep_idx].data, fr[keep_idx].len) < 0)
				fprintf(stderr, "keepalive: %s\n", strerror(errno));
			next_keep = now_ms() + 1000;
		}
		if (r <= 0) continue;
		ssize_t got = read(fd, acc + acc_len, sizeof(acc) - acc_len);
		if (got <= 0) continue;
		write(out, acc + acc_len, got);
		fprintf(stderr, "  rx %zd bytes\n", got);
		acc_len += got;
		size_t start = 0;
		for (size_t k = 0; k + 1 < acc_len; k++) {
			if (acc[k] == 0xaa && acc[k + 1] == 0x0f) {
				size_t end = k + 2;
				dump_frame_id(acc + start, end - start);
				start = end;
				k = end - 1;
			}
		}
		if (start) {
			memmove(acc, acc + start, acc_len - start);
			acc_len -= start;
		}
	}

	close(out);
	close(fd);
	free(buf);
	fprintf(stderr, "done\n");
	return 0;
}

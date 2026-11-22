/*
 * gps-relay-pty — прозрачный pty-релей для /dev/stpgps.
 *
 * Зачем: FIFO на месте /dev/stpgps — общая очередь, при O_RDWR с двух
 * сторон обе стороны «воруют» байты, захват получается неполным. pty-пара
 * даёт два независимых направления: mnld пишет в slave, релей читает
 * master; ответы чипа релей пишет в master, mnld читает из slave.
 *
 * Схема:
 *   /dev/stpgps      -> symlink на /dev/pts/N  (его открывает mnld)
 *   /dev/stpgps.real -> настоящий chardev gps_drv (его держит релей)
 *
 * Пишет два файла: <log>.mnld.bin (mnld -> чип) и <log>.chip.bin
 * (чип -> mnld). На SIGTERM/SIGINT восстанавливает /dev/stpgps.
 *
 * Сборка (ARM32, статически — на Android нет glibc):
 *   arm-linux-gnueabihf-gcc -static -O2 -o gps-relay-pty gps-relay-pty.c
 *
 * Запуск на устройстве (root):
 *   ./gps-relay-pty /data/local/tmp/ref 300 &
 *   setprop ctl.start mnld
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>

#define DEV_PATH "/dev/stpgps"
#define REAL_PATH "/dev/stpgps.real"

static volatile sig_atomic_t stop_flag;

static void on_signal(int sig)
{
	(void)sig;
	stop_flag = 1;
}

static void restore_dev(void)
{
	struct stat st;

	if (lstat(DEV_PATH, &st) == 0 && S_ISLNK(st.st_mode))
		unlink(DEV_PATH);
	if (lstat(REAL_PATH, &st) == 0) {
		if (lstat(DEV_PATH, &st) != 0)
			rename(REAL_PATH, DEV_PATH);
	}
}

static void write_all(int fd, const char *buf, ssize_t n)
{
	ssize_t off = 0;

	while (off < n) {
		ssize_t w = write(fd, buf + off, n - off);

		if (w < 0) {
			if (errno == EINTR)
				continue;
			return;
		}
		off += w;
	}
}

static void set_raw(int fd)
{
	struct termios tio;

	if (tcgetattr(fd, &tio) != 0)
		return;
	cfmakeraw(&tio);
	tio.c_cflag |= CLOCAL;
	cfsetispeed(&tio, B115200);
	cfsetospeed(&tio, B115200);
	tcsetattr(fd, TCSANOW, &tio);
}

int main(int argc, char **argv)
{
	const char *base = argc > 1 ? argv[1] : "/data/local/tmp/ref";
	int seconds = argc > 2 ? atoi(argv[2]) : 120;
	char mnld_path[512], chip_path[512];
	char buf[16384];
	struct pollfd pfd[2];
	int master, slave, real;
	int fmnld, fchip;
	int i;

	snprintf(mnld_path, sizeof(mnld_path), "%s.mnld.bin", base);
	snprintf(chip_path, sizeof(chip_path), "%s.chip.bin", base);

	/* Лечим остатки прошлого запуска. */
	restore_dev();

	real = open(REAL_PATH, O_RDWR | O_NOCTTY);
	if (real < 0) {
		/* Ещё не переименован: забираем настоящий узел. */
		if (rename(DEV_PATH, REAL_PATH) != 0) {
			fprintf(stderr, "rename %s: %s\n", DEV_PATH, strerror(errno));
			return 1;
		}
		real = open(REAL_PATH, O_RDWR | O_NOCTTY);
	}
	if (real < 0) {
		fprintf(stderr, "open %s: %s\n", REAL_PATH, strerror(errno));
		restore_dev();
		return 1;
	}

	master = posix_openpt(O_RDWR | O_NOCTTY);
	if (master < 0 || grantpt(master) != 0 || unlockpt(master) != 0) {
		fprintf(stderr, "pty: %s\n", strerror(errno));
		restore_dev();
		return 1;
	}

	slave = open(ptsname(master), O_RDWR | O_NOCTTY);
	if (slave < 0) {
		fprintf(stderr, "open ptmx slave: %s\n", strerror(errno));
		restore_dev();
		return 1;
	}
	set_raw(slave);
	set_raw(master);

	unlink(DEV_PATH);
	if (symlink(ptsname(master), DEV_PATH) != 0) {
		fprintf(stderr, "symlink: %s\n", strerror(errno));
		restore_dev();
		return 1;
	}
	chmod(ptsname(master), 0666);

	fmnld = open(mnld_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	fchip = open(chip_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fmnld < 0 || fchip < 0) {
		fprintf(stderr, "log open: %s\n", strerror(errno));
		restore_dev();
		return 1;
	}

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	signal(SIGHUP, on_signal);

	printf("relay: %s -> %s, pty %s, %d s\n", REAL_PATH, DEV_PATH,
	       ptsname(master), seconds);
	fflush(stdout);

	for (i = 0; i < seconds * 10 && !stop_flag; i++) {
		int n;

		pfd[0].fd = master;
		pfd[0].events = POLLIN;
		pfd[1].fd = real;
		pfd[1].events = POLLIN;

		n = poll(pfd, 2, 100);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			break;
		}
		if (n == 0)
			continue;

		if (pfd[0].revents & POLLIN) {
			ssize_t r = read(master, buf, sizeof(buf));

			if (r > 0) {
				write_all(real, buf, r);
				write_all(fmnld, buf, r);
			}
		}
		if (pfd[1].revents & POLLIN) {
			ssize_t r = read(real, buf, sizeof(buf));

			if (r > 0) {
				write_all(master, buf, r);
				write_all(fchip, buf, r);
			}
		}
		if (pfd[1].revents & (POLLERR | POLLHUP))
			break;
	}

	close(fmnld);
	close(fchip);
	close(master);
	close(slave);
	close(real);
	restore_dev();
	printf("relay: done, restored %s\n", DEV_PATH);
	return 0;
}

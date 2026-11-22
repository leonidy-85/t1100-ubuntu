/*
 * gps-wtrace — attach to mnld and log every write(2) whose fd points to
 * /dev/stpgps.  Static ARM32 build, runs on the Android reference device.
 *
 *   arm-linux-gnueabihf-gcc -static -O2 -o gps-wtrace gps-wtrace.c
 *   gps-wtrace <pid> [seconds] > /data/local/tmp/wtrace.log
 *
 * Syscall number for write on ARM EABI is 4.  We stop on syscall entry only
 * (toggle), read r0/r1/r2, resolve the fd through /proc/<pid>/fd, and dump
 * up to 32 bytes of the buffer through /proc/<pid>/mem.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <time.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/types.h>

#define MAXDUMP 32

static volatile sig_atomic_t stop;

static void on_sig(int s) { (void)s; stop = 1; }

static long ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static int fd_is_stpgps(pid_t pid, int fd)
{
	char path[64], link[128];
	ssize_t n;

	snprintf(path, sizeof(path), "/proc/%d/fd/%d", pid, fd);
	n = readlink(path, link, sizeof(link) - 1);
	if (n < 0)
		return 0;
	link[n] = 0;
	return strstr(link, "stpgps") != NULL;
}

int main(int argc, char **argv)
{
	pid_t pid;
	int secs = 20;
	long t_end;
	int in_syscall = 0;
	FILE *mem;
	unsigned char buf[MAXDUMP];

	if (argc < 2) {
		fprintf(stderr, "usage: %s PID [SECONDS]\n", argv[0]);
		return 2;
	}
	pid = atoi(argv[1]);
	if (argc > 2)
		secs = atoi(argv[2]);

	signal(SIGINT, on_sig);
	signal(SIGTERM, on_sig);

	if (ptrace(PTRACE_ATTACH, pid, NULL, NULL) < 0) {
		perror("PTRACE_ATTACH");
		return 1;
	}
	waitpid(pid, NULL, 0);
	fprintf(stderr, "attached to %d\n", pid);

	{
		char p[64];
		snprintf(p, sizeof(p), "/proc/%d/mem", pid);
		mem = fopen(p, "rb");
	}
	if (!mem)
		perror("open mem");

	t_end = ms() + (long)secs * 1000;

	while (!stop && ms() < t_end) {
		struct user_regs regs;

		if (ptrace(PTRACE_SYSCALL, pid, NULL, NULL) < 0) {
			perror("PTRACE_SYSCALL");
			break;
		}
		if (waitpid(pid, NULL, 0) < 0)
			break;

		in_syscall = !in_syscall;
		if (!in_syscall)
			continue;

		if (ptrace(PTRACE_GETREGS, pid, NULL, &regs) < 0)
			continue;

		if (regs.uregs[7] != 4)	/* write */
			continue;
		if (!fd_is_stpgps(pid, (int)regs.uregs[0]))
			continue;

		size_t len = regs.uregs[2];
		size_t want = len < MAXDUMP ? len : MAXDUMP;
		memset(buf, 0, sizeof(buf));
		if (mem && want) {
			if (fseeko(mem, (off_t)regs.uregs[1], SEEK_SET) == 0)
				fread(buf, 1, want, mem);
		}
		printf("WRITE fd=%d len=%zu ", (int)regs.uregs[0], len);
		for (size_t i = 0; i < want; i++)
			printf("%02x", buf[i]);
		printf("\n");
		fflush(stdout);
	}

	ptrace(PTRACE_DETACH, pid, NULL, NULL);
	fprintf(stderr, "detached\n");
	return 0;
}

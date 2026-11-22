/*
 * gps-wtrace2 — attach to all threads of mnld and log every write(2) whose
 * fd points to /dev/stpgps.  Static ARM32 build for the Android reference.
 *
 *   arm-linux-gnueabihf-gcc -static -O2 -o gps-wtrace2 gps-wtrace2.c
 *   gps-wtrace2 <pid> [seconds] > /data/local/tmp/wtrace.log
 *
 * The process is traced per-thread: new threads are picked up as they appear,
 * so start the tracer right after `setprop ctl.start mnld`.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <signal.h>
#include <time.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/types.h>

#define MAXT 128
#define MAXDUMP 40

struct tr {
	pid_t tid;
	int in_syscall;
	int alive;
};

static struct tr trs[MAXT];
static int ntr;
static volatile sig_atomic_t stop;
static int memfd = -1;
static pid_t gpid;
static unsigned long n_writes;
static int verbose;

static void on_sig(int s) { (void)s; stop = 1; }

static long ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static struct tr *find(pid_t tid)
{
	for (int i = 0; i < ntr; i++)
		if (trs[i].tid == tid)
			return &trs[i];
	return NULL;
}

static int fd_is_stpgps(int fd)
{
	char path[64], link[128];
	ssize_t n;

	snprintf(path, sizeof(path), "/proc/%d/fd/%d", gpid, fd);
	n = readlink(path, link, sizeof(link) - 1);
	if (n < 0)
		return 0;
	link[n] = 0;
	return strstr(link, "stpgps") != NULL;
}

static void attach_new(void)
{
	char dir[64];
	DIR *d;

	snprintf(dir, sizeof(dir), "/proc/%d/task", gpid);
	d = opendir(dir);
	if (!d)
		return;
	struct dirent *e;
	while ((e = readdir(d))) {
		if (e->d_name[0] < '0' || e->d_name[0] > '9')
			continue;
		pid_t tid = atoi(e->d_name);
		if (find(tid) || ntr >= MAXT)
			continue;
		if (ptrace(PTRACE_ATTACH, tid, NULL, NULL) < 0)
			continue;
		waitpid(tid, NULL, __WALL);
		trs[ntr].tid = tid;
		trs[ntr].in_syscall = 0;
		trs[ntr].alive = 1;
		ntr++;
		{
			long rc = ptrace(PTRACE_SYSCALL, tid, NULL, NULL);
			fprintf(stderr, "attached tid %d resume rc=%ld errno=%d\n",
				tid, rc, errno);
		}
	}
	closedir(d);
}

int main(int argc, char **argv)
{
	int secs = 15;
	long t_end;

	if (argc < 2) {
		fprintf(stderr, "usage: %s PID [SECONDS]\n", argv[0]);
		return 2;
	}
	gpid = atoi(argv[1]);
	if (argc > 2)
		secs = atoi(argv[2]);

	signal(SIGINT, on_sig);
	signal(SIGTERM, on_sig);
	verbose = getenv("WT_ALL") != NULL;

	{
		char p[64];
		snprintf(p, sizeof(p), "/proc/%d/mem", gpid);
		memfd = open(p, O_RDONLY);
	}

	t_end = ms() + (long)secs * 1000;

	while (!stop && ms() < t_end) {
		attach_new();

		int st;
		pid_t r = waitpid(-1, &st, WNOHANG | __WALL);
		if (r <= 0) {
			usleep(3000);
			continue;
		}

		struct tr *t = find(r);
		if (!t)
			continue;
		if (verbose && n_writes < 40)
			fprintf(stderr, "stop tid=%d st=0x%x\n", r, st);

		if (WIFEXITED(st) || WIFSIGNALED(st)) {
			t->alive = 0;
			continue;
		}
		if (!WIFSTOPPED(st)) {
			ptrace(PTRACE_SYSCALL, r, NULL, NULL);
			continue;
		}

		int sig = WSTOPSIG(st);
		if (sig == (SIGTRAP | 0x80)) {	/* syscall stop */
			struct user_regs regs;
			if (ptrace(PTRACE_GETREGS, r, NULL, &regs) == 0) {
				if (!t->in_syscall) {
					t->in_syscall = 1;
					if (regs.uregs[7] == 4) {
						n_writes++;
						if (verbose && n_writes <= 40)
							fprintf(stderr, "w tid=%d fd=%d len=%u\n",
								r, (int)regs.uregs[0],
								(unsigned)regs.uregs[2]);
					}
					if (regs.uregs[7] == 4 &&
					    fd_is_stpgps((int)regs.uregs[0])) {
						size_t len = regs.uregs[2];
						size_t want = len < MAXDUMP ? len : MAXDUMP;
						unsigned char buf[MAXDUMP];
						memset(buf, 0, sizeof(buf));
						if (memfd >= 0 && want)
							pread(memfd, buf, want, (off_t)regs.uregs[1]);
						printf("WRITE tid=%d fd=%d len=%zu ", r,
						       (int)regs.uregs[0], len);
						for (size_t i = 0; i < want; i++)
							printf("%02x", buf[i]);
						printf("\n");
						fflush(stdout);
					}
				} else {
					t->in_syscall = 0;
				}
			}
			ptrace(PTRACE_SYSCALL, r, NULL, NULL);
		} else {
			if (verbose)
				fprintf(stderr, "nonsyscall stop tid=%d sig=%d\n", r, sig);
			/* drop SIGTRAP, deliver everything else */
			ptrace(PTRACE_SYSCALL, r, NULL,
			       sig == SIGTRAP ? NULL : (void *)(long)sig);
		}
	}

	for (int i = 0; i < ntr; i++)
		if (trs[i].alive)
			ptrace(PTRACE_DETACH, trs[i].tid, NULL, NULL);

	fprintf(stderr, "detached %d threads, write syscalls seen: %lu\n", ntr, n_writes);
	return 0;
}

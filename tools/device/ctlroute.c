/*
 * Tiny ALSA control helper (no libasound): lists controls and switches on the
 * DAPM mixers whose name matches one of the argv patterns.  Used to bring up
 * the DPCM route FE(DL1) -> BE(ADDA) before a UCM profile exists.
 *
 *   ctlroute C0 LIST
 *   ctlroute C0 SET DL1_CH
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/types.h>
#include <sound/asound.h>

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "C0";
	char path[64];
	int fd, i, ret;
	struct snd_ctl_elem_list list;
	struct snd_ctl_elem_id *ids;

	snprintf(path, sizeof(path), "/dev/snd/control%s", dev);
	fd = open(path, O_RDWR);
	if (fd < 0) {
		perror(path);
		return 1;
	}

	memset(&list, 0, sizeof(list));
	ret = ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list);
	if (ret < 0) {
		perror("ELEM_LIST(count)");
		return 1;
	}
	ids = calloc(list.count ? list.count : 1, sizeof(*ids));
	list.pids = ids;
	list.space = list.count;
	ret = ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list);
	if (ret < 0) {
		perror("ELEM_LIST(ids)");
		return 1;
	}

	for (i = 0; i < (int)list.used; i++) {
		struct snd_ctl_elem_info info;
		struct snd_ctl_elem_value val;
		int match = 0, j;

		memset(&info, 0, sizeof(info));
		info.id = ids[i];
		if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, &info) < 0)
			continue;

		if (argc <= 2 || !strcmp(argv[2], "LIST")) {
			printf("%3u %-40s type=%u count=%u\n", ids[i].numid,
			       ids[i].name, info.type, info.count);
			continue;
		}

		for (j = 3; j < argc; j++)
			if (strstr(ids[i].name, argv[j]))
				match = 1;
		if (!match || info.type != SNDRV_CTL_ELEM_TYPE_BOOLEAN)
			continue;

		memset(&val, 0, sizeof(val));
		val.id = ids[i];
		if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_READ, &val) < 0)
			continue;
		if (val.value.integer.value[0]) {
			printf("already on: %s\n", ids[i].name);
			continue;
		}
		val.value.integer.value[0] = 1;
		if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_WRITE, &val) < 0)
			printf("write failed: %s (%s)\n", ids[i].name,
			       strerror(errno));
		else
			printf("on: %s\n", ids[i].name);
	}

	close(fd);
	return 0;
}

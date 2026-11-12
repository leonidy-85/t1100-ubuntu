/* ctlenum - list ALSA controls and set enumerated ones (no libasound). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sound/asound.h>

static const char *type_name(unsigned t)
{
	switch (t) {
	case SNDRV_CTL_ELEM_TYPE_BOOLEAN: return "bool";
	case SNDRV_CTL_ELEM_TYPE_INTEGER: return "int";
	case SNDRV_CTL_ELEM_TYPE_ENUMERATED: return "enum";
	case SNDRV_CTL_ELEM_TYPE_BYTES: return "bytes";
	case SNDRV_CTL_ELEM_TYPE_IEC958: return "iec958";
	default: return "?";
	}
}

static int elem_info(int fd, struct snd_ctl_elem_id *id, struct snd_ctl_elem_info *info)
{
	memset(info, 0, sizeof(*info));
	info->id = *id;
	return ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, info);
}

static void print_enum(int fd, struct snd_ctl_elem_id *id)
{
	struct snd_ctl_elem_info info;
	unsigned int n, i;

	if (elem_info(fd, id, &info) < 0)
		return;
	n = info.value.enumerated.items;
	for (i = 0; i < n; i++) {
		memset(&info, 0, sizeof(info));
		info.id = *id;
		info.value.enumerated.item = i;
		if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, &info) < 0)
			break;
		printf(" [%u]=%s", i, info.value.enumerated.name);
	}
}

static int ctl_list(int fd, const char *filter)
{
	struct snd_ctl_elem_list list;
	struct snd_ctl_elem_id *ids;
	unsigned int i;

	memset(&list, 0, sizeof(list));
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list) < 0) {
		perror("ELEM_LIST");
		return 1;
	}
	if (!list.count)
		return 0;
	ids = calloc(list.count, sizeof(*ids));
	if (!ids)
		return 1;
	list.pids = ids;
	list.space = list.count;
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list) < 0) {
		perror("ELEM_LIST");
		free(ids);
		return 1;
	}
	for (i = 0; i < list.used; i++) {
		struct snd_ctl_elem_info info;

		if (filter && !strstr(ids[i].name, filter))
			continue;
		if (elem_info(fd, &ids[i], &info) < 0)
			continue;
		printf("%3u %-28s type=%-5s count=%u", ids[i].numid, ids[i].name,
		       type_name(info.type), info.count);
		if (info.type == SNDRV_CTL_ELEM_TYPE_ENUMERATED)
			print_enum(fd, &ids[i]);
		printf("\n");
	}
	free(ids);
	return 0;
}

static int ctl_set_enum(int fd, const char *name, const char *value)
{
	struct snd_ctl_elem_list list;
	struct snd_ctl_elem_id *ids;
	struct snd_ctl_elem_info info;
	struct snd_ctl_elem_value val;
	char *end;
	long idx;
	int found = -1;
	unsigned int i;

	memset(&list, 0, sizeof(list));
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list) < 0)
		return 1;
	ids = calloc(list.count ? list.count : 1, sizeof(*ids));
	if (!ids)
		return 1;
	list.pids = ids;
	list.space = list.count;
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list) < 0) {
		free(ids);
		return 1;
	}
	for (i = 0; i < list.used; i++) {
		if (!strcmp(ids[i].name, name)) {
			found = i;
			break;
		}
	}
	if (found < 0) {
		fprintf(stderr, "control '%s' not found\n", name);
		free(ids);
		return 1;
	}
	if (elem_info(fd, &ids[found], &info) < 0 ||
	    info.type != SNDRV_CTL_ELEM_TYPE_ENUMERATED) {
		fprintf(stderr, "'%s' is not an enumerated control\n", name);
		free(ids);
		return 1;
	}
	idx = strtol(value, &end, 0);
	if (*end) {
		unsigned int n = info.value.enumerated.items, k;

		idx = -1;
		for (k = 0; k < n; k++) {
			memset(&info, 0, sizeof(info));
			info.id = ids[found];
			info.value.enumerated.item = k;
			if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, &info) < 0)
				break;
			if (!strcmp(info.value.enumerated.name, value)) {
				idx = k;
				break;
			}
		}
		if (idx < 0) {
			fprintf(stderr, "no such item '%s' for '%s'\n", value, name);
			free(ids);
			return 1;
		}
	}
	memset(&val, 0, sizeof(val));
	val.id = ids[found];
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_READ, &val) < 0) {
		perror("ELEM_READ");
		free(ids);
		return 1;
	}
	val.value.enumerated.item[0] = idx;
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_WRITE, &val) < 0) {
		perror("ELEM_WRITE");
		free(ids);
		return 1;
	}
	printf("%s = [%ld]\n", name, idx);
	free(ids);
	return 0;
}

int main(int argc, char **argv)
{
	int fd;

	if (argc < 3) {
		fprintf(stderr, "usage: %s <dev> LIST [filter]\n"
				"       %s <dev> SET \"<enum name>\" <index|item>\n",
			argv[0], argv[0]);
		return 2;
	}
	fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		perror(argv[1]);
		return 1;
	}
	if (!strcmp(argv[2], "LIST"))
		return ctl_list(fd, argc > 3 ? argv[3] : NULL);
	if (!strcmp(argv[2], "SET") && argc > 4)
		return ctl_set_enum(fd, argv[3], argv[4]);
	fprintf(stderr, "bad arguments\n");
	return 2;
}

/*
 * Minimal ALSA raw playback tool for bring-up: no libasound, only the kernel
 * ABI.  Plays a sine tone on /dev/snd/pcmC0D0p (or a path given as argv[1]).
 *
 * Build (aarch64, static):
 *   aarch64-linux-gnu-gcc -O2 -static -I<kernel>/usr/include rawplay.c -o rawplay
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <sys/ioctl.h>
#include <linux/types.h>

/* Pull the kernel uapi ALSA definitions directly. */
#include <sound/asound.h>

static void mask_clear(struct snd_mask *m)
{
	memset(m, 0, sizeof(*m));
}

static void mask_set(struct snd_mask *m, unsigned int v)
{
	m->bits[v / 32] |= 1u << (v % 32);
}

static void interval_set(struct snd_interval *i, unsigned int min,
			 unsigned int max)
{
	i->min = min;
	i->max = max;
	i->openmin = 0;
	i->openmax = 0;
	i->integer = 1;
	i->empty = 0;
}

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "/dev/snd/pcmC0D0p";
	int seconds = argc > 2 ? atoi(argv[2]) : 3;
	unsigned int rate = 48000, ch = 2;
	struct snd_pcm_hw_params hw;
	struct snd_pcm_sw_params sw;
	struct snd_xferi xfer;
	snd_pcm_uframes_t frames = 1024;
	short *buf;
	unsigned int total, done;
	int fd, i, ret;
	double phase = 0.0;

	fd = open(dev, O_WRONLY);
	if (fd < 0) {
		perror("open");
		return 1;
	}

	memset(&hw, 0, sizeof(hw));
	hw.flags = 0;
	/* start from "everything allowed", then narrow the parameters we care
	 * about: a zeroed struct means 0..0 for every interval, which the
	 * kernel rejects with -EINVAL. */
	for (i = 0; i <= SNDRV_PCM_HW_PARAM_LAST_MASK - SNDRV_PCM_HW_PARAM_FIRST_MASK; i++)
		memset(&hw.masks[i], 0xff, sizeof(hw.masks[i]));
	for (i = 0; i <= SNDRV_PCM_HW_PARAM_LAST_INTERVAL - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL; i++) {
		hw.intervals[i].min = 0;
		hw.intervals[i].max = ~0U;
		hw.intervals[i].openmin = 0;
		hw.intervals[i].openmax = 0;
		hw.intervals[i].integer = 0;
		hw.intervals[i].empty = 0;
	}
	mask_clear(&hw.masks[SNDRV_PCM_HW_PARAM_ACCESS - SNDRV_PCM_HW_PARAM_FIRST_MASK]);
	mask_set(&hw.masks[SNDRV_PCM_HW_PARAM_ACCESS - SNDRV_PCM_HW_PARAM_FIRST_MASK],
		 SNDRV_PCM_ACCESS_RW_INTERLEAVED);
	mask_clear(&hw.masks[SNDRV_PCM_HW_PARAM_FORMAT - SNDRV_PCM_HW_PARAM_FIRST_MASK]);
	mask_set(&hw.masks[SNDRV_PCM_HW_PARAM_FORMAT - SNDRV_PCM_HW_PARAM_FIRST_MASK],
		 SNDRV_PCM_FORMAT_S16_LE);
	mask_clear(&hw.masks[SNDRV_PCM_HW_PARAM_SUBFORMAT - SNDRV_PCM_HW_PARAM_FIRST_MASK]);
	mask_set(&hw.masks[SNDRV_PCM_HW_PARAM_SUBFORMAT - SNDRV_PCM_HW_PARAM_FIRST_MASK],
		 SNDRV_PCM_SUBFORMAT_STD);
	interval_set(&hw.intervals[SNDRV_PCM_HW_PARAM_RATE - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], rate, rate);
	interval_set(&hw.intervals[SNDRV_PCM_HW_PARAM_CHANNELS - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], ch, ch);
	interval_set(&hw.intervals[SNDRV_PCM_HW_PARAM_PERIOD_SIZE - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], frames, frames);
	interval_set(&hw.intervals[SNDRV_PCM_HW_PARAM_PERIODS - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], 4, 4);
	interval_set(&hw.intervals[SNDRV_PCM_HW_PARAM_BUFFER_SIZE - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL], frames * 4, frames * 4);

	ret = ioctl(fd, SNDRV_PCM_IOCTL_HW_PARAMS, &hw);
	if (ret < 0) {
		perror("HW_PARAMS");
		return 1;
	}

	memset(&sw, 0, sizeof(sw));
	sw.tstamp_mode = SNDRV_PCM_TSTAMP_NONE;
	sw.period_step = 1;
	sw.avail_min = 1;
	sw.start_threshold = 1;
	sw.stop_threshold = ~0U;
	sw.silence_threshold = 0;
	ret = ioctl(fd, SNDRV_PCM_IOCTL_SW_PARAMS, &sw);
	if (ret < 0)
		perror("SW_PARAMS (continuing)");

	ret = ioctl(fd, SNDRV_PCM_IOCTL_PREPARE);
	if (ret < 0) {
		perror("PREPARE");
		return 1;
	}

	buf = malloc(frames * ch * sizeof(short));
	if (!buf)
		return 1;

	total = rate * seconds;
	done = 0;
	while (done < total) {
		unsigned int n = frames;

		if (total - done < n)
			n = total - done;
		for (i = 0; i < (int)n; i++) {
			short v = (short)(10000.0 * sin(phase));

			phase += 2.0 * M_PI * 440.0 / rate;
			buf[i * 2 + 0] = v;
			buf[i * 2 + 1] = v;
		}
		xfer.buf = buf;
		xfer.frames = n;
		ret = ioctl(fd, SNDRV_PCM_IOCTL_WRITEI_FRAMES, &xfer);
		if (ret < 0) {
			perror("WRITEI_FRAMES");
			return 1;
		}
		done += n;
	}

	ioctl(fd, SNDRV_PCM_IOCTL_DRAIN);
	close(fd);
	printf("played %u frames\n", done);
	return 0;
}

#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/videodev2.h>

static int try_type(int fd, enum v4l2_buf_type type, unsigned pixfmt, const char *tag)
{
	struct v4l2_format f;
	struct v4l2_requestbuffers rb;
	int i;

	memset(&f, 0, sizeof(f));
	f.type = type;
	f.fmt.pix_mp.width = 640;
	f.fmt.pix_mp.height = 480;
	f.fmt.pix_mp.pixelformat = pixfmt;
	f.fmt.pix_mp.num_planes = 1;
	f.fmt.pix_mp.plane_fmt[0].sizeimage = 65536;
	if (ioctl(fd, VIDIOC_S_FMT, &f) < 0) {
		printf("%s S_FMT: %s\n", tag, strerror(errno));
		return -1;
	}
	printf("%s S_FMT ok: %ux%u fmt=%c%c%c%c sizeimage=%u\n", tag,
	       f.fmt.pix_mp.width, f.fmt.pix_mp.height,
	       (pixfmt) & 0xff, (pixfmt >> 8) & 0xff, (pixfmt >> 16) & 0xff, (pixfmt >> 24) & 0xff,
	       f.fmt.pix_mp.plane_fmt[0].sizeimage);

	memset(&rb, 0, sizeof(rb));
	rb.count = 2;
	rb.type = type;
	rb.memory = V4L2_MEMORY_MMAP;
	if (ioctl(fd, VIDIOC_REQBUFS, &rb) < 0) {
		printf("%s REQBUFS: %s\n", tag, strerror(errno));
		return -1;
	}
	printf("%s REQBUFS ok count=%u\n", tag, rb.count);

	for (i = 0; i < (int)rb.count && i < 2; i++) {
		struct v4l2_buffer b;
		struct v4l2_plane planes[VIDEO_MAX_PLANES];
		struct v4l2_exportbuffer ex;
		int dfd;
		void *p;

		memset(&b, 0, sizeof(b));
		memset(planes, 0, sizeof(planes));
		b.type = type;
		b.memory = V4L2_MEMORY_MMAP;
		b.index = i;
		b.length = 1;
		b.m.planes = planes;
		if (ioctl(fd, VIDIOC_QUERYBUF, &b) < 0) {
			printf("%s QUERYBUF[%d]: %s\n", tag, i, strerror(errno));
			continue;
		}
		printf("%s QUERYBUF[%d] len=%u\n", tag, i, planes[0].length);

		memset(&ex, 0, sizeof(ex));
		ex.type = type;
		ex.index = i;
		ex.plane = 0;
		ex.flags = O_RDWR;
		if (ioctl(fd, VIDIOC_EXPBUF, &ex) < 0) {
			printf("%s EXPBUF[%d]: %s\n", tag, i, strerror(errno));
			continue;
		}
		dfd = ex.fd;
		printf("%s EXPBUF[%d] dmabuf_fd=%d\n", tag, i, dfd);
		p = mmap(NULL, planes[0].length, PROT_READ | PROT_WRITE, MAP_SHARED, dfd, 0);
		if (p == MAP_FAILED) {
			printf("%s   mmap: %s\n", tag, strerror(errno));
		} else {
			memset(p, 0x5a, planes[0].length);
			printf("%s   mmap ok, write 0x5a, readback=%02x\n", tag, *(unsigned char *)p);
			munmap(p, planes[0].length);
		}
		/* keep one fd open to inspect debugfs, close the other */
		if (i == 1)
			close(dfd);
	}
	return 0;
}

int main(void)
{
	struct v4l2_capability cap;
	int fd = open("/dev/video0", O_RDWR | O_NONBLOCK);

	if (fd < 0) {
		perror("open /dev/video0");
		return 1;
	}
	memset(&cap, 0, sizeof(cap));
	if (ioctl(fd, VIDIOC_QUERYCAP, &cap) == 0)
		printf("QUERYCAP driver=%s card=%s caps=0x%x caps2=0x%x\n", cap.driver, cap.card,
		       cap.capabilities, cap.device_caps);
	else
		printf("QUERYCAP: %s\n", strerror(errno));

	try_type(fd, V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE, V4L2_PIX_FMT_H264, "OUTPUT ");
	try_type(fd, V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE, V4L2_PIX_FMT_NV12M, "CAPTURE");
	printf("kept one dmabuf fd open; sleeping 30s for /sys/kernel/debug/dma_buf/bufinfo\n");
	fflush(stdout);
	sleep(30);
	return 0;
}

// egl-probe: доказывает, что Mesa/EGL/GBM/GLES2 действительно работают через GPU,
// не занимая KMS и не трогая дисплей.
//
//   egl-probe [drm-node]        по умолчанию /dev/dri/renderD128
//
// Что делает: открывает DRM-узел, создаёт GBM-устройство, EGL-дисплей на
// платформе GBM, контекст GLES2, рисует в FBO (текстура 64x64) известный цвет
// и читает пиксель назад. Печатает EGL/GL-строки, поэтому годится как
// «GL_RENDERER»-тест без kmscube и без экрана.
//
// Сборка — scripts/build-mesa-aarch64.sh (кросс, aarch64-linux-gnu-gcc).

#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <gbm.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

#ifndef EGL_PLATFORM_GBM_MESA
#define EGL_PLATFORM_GBM_MESA 0x31D7
#endif

static void die(const char *what)
{
	fprintf(stderr, "FAIL: %s\n", what);
}

int main(int argc, char **argv)
{
	const char *node = argc > 1 ? argv[1] : "/dev/dri/renderD128";
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
		EGL_NONE
	};
	static const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLConfig cfg;
	EGLint ncfg, major, minor;
	EGLDisplay dpy;
	EGLContext ctx;
	EGLSurface surf = EGL_NO_SURFACE;
	struct gbm_device *gbm;
	struct gbm_surface *gsurf = NULL;
	GLuint fbo, tex;
	GLubyte px[4] = { 0, 0, 0, 0 };
	int fd, rc = 1;

	fd = open(node, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror(node);
		return 1;
	}

	gbm = gbm_create_device(fd);
	if (!gbm) {
		die("gbm_create_device");
		return 1;
	}
	printf("node        : %s\n", node);
	printf("gbm backend : %s\n", gbm_device_get_backend_name(gbm));

	dpy = eglGetPlatformDisplay(EGL_PLATFORM_GBM_MESA, gbm, NULL);
	if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, &major, &minor)) {
		die("eglInitialize (EGL_PLATFORM_GBM_MESA)");
		goto out_gbm;
	}
	printf("EGL_VERSION : %s\n", eglQueryString(dpy, EGL_VERSION));
	printf("EGL_VENDOR  : %s\n", eglQueryString(dpy, EGL_VENDOR));

	if (!eglChooseConfig(dpy, cfg_attr, &cfg, 1, &ncfg) || ncfg < 1) {
		die("eglChooseConfig");
		goto out_term;
	}

	/* GBM-поверхность нужна только как носитель для окна EGL; в неё не
	 * сканируем, поэтому дисплей остаётся нетронутым. */
	gsurf = gbm_surface_create(gbm, 64, 64, GBM_FORMAT_XRGB8888,
				   GBM_BO_USE_RENDERING);
	if (gsurf)
		surf = eglCreateWindowSurface(dpy, cfg, (EGLNativeWindowType)gsurf, NULL);
	if (surf == EGL_NO_SURFACE) {
		printf("note        : no window surface, using surfaceless context\n");
		eglBindAPI(EGL_OPENGL_ES_API);
		ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
		if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, EGL_NO_SURFACE,
							    EGL_NO_SURFACE, ctx)) {
			die("eglMakeCurrent (surfaceless)");
			goto out_term;
		}
	} else {
		eglBindAPI(EGL_OPENGL_ES_API);
		ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
		if (ctx == EGL_NO_CONTEXT ||
		    !eglMakeCurrent(dpy, surf, surf, ctx)) {
			die("eglMakeCurrent");
			goto out_term;
		}
	}

	printf("GL_VENDOR   : %s\n", glGetString(GL_VENDOR));
	printf("GL_RENDERER : %s\n", glGetString(GL_RENDERER));
	printf("GL_VERSION  : %s\n", glGetString(GL_VERSION));
	printf("GL_SL_VERSION: %s\n", glGetString(GL_SHADING_LANGUAGE_VERSION));

	/* Пишем в FBO, чтобы чтение обратно не зависело от свойств окна. */
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA,
		     GL_UNSIGNED_BYTE, NULL);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			       GL_TEXTURE_2D, tex, 0);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		die("FBO incomplete");
		goto out_term;
	}

	glViewport(0, 0, 64, 64);
	glClearColor(0.25f, 0.50f, 0.75f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	printf("clear+read  : rgba(%u,%u,%u,%u) err=0x%x\n",
	       px[0], px[1], px[2], px[3], glGetError());

	/* 0.25*255=64, 0.50*255=127..128, 0.75*255=191 */
	if (px[0] > 60 && px[0] < 68 && px[1] > 124 && px[1] < 131 &&
	    px[2] > 187 && px[2] < 195) {
		printf("RESULT      : render OK\n");
		rc = 0;
	} else {
		printf("RESULT      : wrong pixel\n");
	}

out_term:
	eglTerminate(dpy);
out_gbm:
	gbm_device_destroy(gbm);
	return rc;
}

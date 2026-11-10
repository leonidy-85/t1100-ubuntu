# Mesa/panfrost под aarch64: кросс-сборка, раскладка, результаты (10.11.2026)

Фаза 3, userspace-часть. Ядро — `6.12.114-geed4580b9b` (`build/boot_ubuntu28.img`),
panfrost поднят (см. `docs/panfrost-plan.md`). Здесь — как собрана Mesa и что
получилось на железе.

## Итог

| Проверка | Результат |
|---|---|
| `egl-probe` на `/dev/dri/renderD128` (без KMS) | `GL_RENDERER: Mali-G72 (Panfrost)`, `GL_VERSION: OpenGL ES 3.1 Mesa 25.0.7`, `glClear`+`glReadPixels` = `rgba(64,128,191,255)`, `RESULT: render OK` |
| `kmscube -D /dev/dri/card1` (KMS mediatek-drm + kmsro → panfrost) | `Rendered 904 frames in 16.021118 sec (56.425525 fps)`, кадр 1600x2176 XR24, клиент `kmscube` — master на card1 |
| Владелец | куб **виден на панели**, после выхода вернулась консоль (`fb0` 3168 ненулевых байт, `card1-DSI-1` connected, dpms On) |
| dmesg | ни `MMU fault`, ни `job timeout`, ни `GPU fault`, ни `failed to commit` |

То есть GLES 3.1 идёт через GPU, а композиция/KMS — через mediatek-drm, как и
задумано с `kmsro`.

## Версии

| Что | Значение |
|---|---|
| Mesa | **25.0.7** (tarball `archive.mesa3d.org`, sha256 `592272df3cf01e85…`) |
| kmscube | `f60e50e` (gitlab.freedesktop.org/mesa/kmscube) |
| libdrm | 2.4.125 (noble-updates, из sysroot) |
| glibc | sysroot noble 24.04 — 2.39 (= планшет), glibc-dev 2.39-0ubuntu8.9 |
| ядро | 6.12.114-geed4580b9b |
| тулчейн | `aarch64-linux-gnu-gcc/g++` 15.2.0 (gcc-cross 15) |

Почему не новее: с 25.1 (и в 26.x) meson включает CLC для panfrost
(`with_driver_using_cl` содержит `with_gallium_panfrost`), а CLC требует LLVM —
кросс-сборка LLVM ради GLES не нужна. В 25.0.7 panfrost/kmsro те же.

## Конфигурация meson

```sh
meson setup build-mesa mesa-src --cross-file cross-aarch64-mesa.txt \
  --wrap-mode=nodownload -Dbuildtype=release -Dprefix=/usr \
  -Dplatforms= -Dgallium-drivers=panfrost -Dvulkan-drivers= \
  -Dglx=disabled -Degl=enabled -Dgles1=disabled -Dgles2=enabled \
  -Dgbm=enabled -Dglvnd=disabled -Dllvm=disabled -Dvideo-codecs=
```

- `kmsro` **не** передаётся в `-Dgallium-drivers`: в Mesa это не gallium-driver,
  а winsys (`with_gallium_kmsro = with_gallium_drm or …` включается сам при
  наличии libdrm и DRM-драйвера). Проверка в `src/gallium/winsys/kmsro/drm/`
  и fallback в `pipe_loader_drm.c` («kmsro supports lots of drivers, try as a
  fallback»), который на площадочных устройствах ищет render-узел с именем
  драйвера из списка (`panfrost` есть).
- `-Dplatforms=` пустой: нужны только surfaceless + drm/gbm, X11/Wayland не
  требуются (`libwayland` не нужен вообще).
- Итог конфигурации meson: `Gallium drivers: panfrost`, `Platforms:
  surfaceless drm`, `GBM: YES`, `EGL: YES`, `GLES2: YES`, `GLES1: NO`,
  `LLVM: NO`, `Vulkan: NO`.

### Архитектура Mesa 25.0.7 (важно для раскладки)

Отдельных `*_dri.so` больше нет: `libEGL.so` и `libgbm` линкуются напрямую с
`libgallium-25.0.7.so`, а `libgbm` подгружает backend `dri_gbm.so`
(`/usr/lib/gbm`, путь переопределяется `GBM_BACKENDS_PATH`). Поэтому
`LIBGL_DRIVERS_PATH` не нужен — его просто нет к чему применять.

## Sysroot: грабли (новые, в `docs/cross-build.md` их не было)

1. **`libc6-dev:arm64` в sysroot отсутствовал** — `debootstrap --variant=minbase`
   заголовков не ставит, там были только `libdrm`/`libudev`. Добавлено
   распаковкой: `libc6-dev:arm64` (2.39-0ubuntu8.9), `linux-libc-dev:arm64`,
   `zlib1g-dev:arm64` (Mesa 25.0.7 требует zlib жёстко, не optional).
2. **Одного `sys_root` в cross-file мало.** Meson передаёт его только
   pkg-config'у. Нужен `--sysroot` в `[built-in options]`, иначе компилятор
   берёт заголовки хостового кросс-glibc (26.04).
3. **`--sysroot` не вытесняет `/usr/aarch64-linux-gnu/include`.** У
   ubuntu'шного кросс-gcc этот каталог абсолютный и стоит в списке поиска
   *раньше* sysroot — получается смесь glibc 2.4x (заголовки) и 2.39
   (библиотеки). Симптом на Mesa 25.0.7: `conflicting types for 'once_flag'` в
   `src/c11/impl/threads_posix.c` (glibc ≥ 2.39 объявляет C11-threads в
   `stdlib.h`). Лечится `-isystem <sysroot>/usr/include/aarch64-linux-gnu` и
   `-isystem <sysroot>/usr/include` в `c_args`/`cpp_args` — см.
   `tools/cross-aarch64-mesa.txt`.
4. Нужен **кросс-g++** (`g++-aarch64-linux-gnu`): meson объявляет `cpp` как
   язык проекта и без него падает на setup.
5. Линковка приложений против Mesa 25: `libEGL.so` содержит ссылки на символы,
   версионированные как `@libgallium-25.0.7.so`, поэтому в `-l` нужен
   `-l:libgallium-25.0.7.so` (симлинка `libgallium.so` нет) и `-lstdc++`
   (libgallium собран на C++).

Всё это зашито в `scripts/build-mesa-aarch64.sh`; повторная сборка с нуля —
`scripts/build-mesa-aarch64.sh --clean` (~2 минуты на 12 ядрах).

## Что и куда положено на планшете

Системный rootfs не тронут, всё в `/usr/local`:

```
/usr/local/lib/aarch64-linux-gnu/
    libEGL.so.1 -> libEGL.so.1.0.0            (473 128 Б)
    libGLESv2.so.2 -> libGLESv2.so.2.0.0      ( 93 424 Б)
    libgbm.so.1 -> libgbm.so.1.0.0            ( 75 576 Б)
    libgallium-25.0.7.so                      (20 204 520 Б)
    libdrm.so.2 -> libdrm.so.2.125.0          (133 616 Б)  ← в rootfs libdrm нет
    gbm/dri_gbm.so                            (240 504 Б)
/usr/local/bin/
    kmscube (1 590 616 Б), egl-probe (72 008 Б), mesa-env.sh
```

sha256 (то, что реально залито):

```
1b522f1e…a478614  libEGL.so.1.0.0
a4197efb…ff2e0c   libGLESv2.so.2.0.0
afc1373c…951fcad  libgbm.so.1.0.0
b0aaa783…0110b83  libgallium-25.0.7.so
71f5b3cd…63380b8  gbm/dri_gbm.so
efa8992c…35cadf3  libdrm.so.2.125.0
5ac25df5…e4ac390  kmscube
3e15daa1…acceaaae egl-probe
```

Все sha256 залитых файлов совпадают с `build/mesa-aarch64/` (сборка
воспроизводима: `scripts/build-mesa-aarch64.sh` даёт те же байты).

Окружение (`/usr/local/bin/mesa-env.sh`, переменные задаются только для
запускаемых программ):

```sh
export LD_LIBRARY_PATH=/usr/local/lib/aarch64-linux-gnu
export GBM_BACKENDS_PATH=/usr/local/lib/aarch64-linux-gnu/gbm
# отладка: MESA_DEBUG=1 EGL_LOG_LEVEL=debug LIBGL_DEBUG=verbose
```

`EGL_PLATFORM` не нужен: kmscube/egl-probe запрашивают платформу явно
(`eglGetPlatformDisplayEXT(EGL_PLATFORM_GBM_KHR/MESA)`).
`MESA_LOADER_DRIVER_OVERRIDE` тоже не нужен и **вреден**: на card1 он сломал бы
kmsro, форсируя panfrost на fd mediatek.

## Запуск и результаты

```sh
# 1) рендер без KMS (renderD128): FBO + glReadPixels
tools/host/mesa-test.sh probe
# 2) KMS на панели: card1 (mediatek-drm) + kmsro → renderD128 (panfrost)
tools/host/mesa-test.sh kmscube 10
# 3) приёмка: 904 кадра / 16.02 с, 56.4 fps
```

`egl-probe` (полный вывод):

```
node        : /dev/dri/renderD128
gbm backend : drm
EGL_VERSION : 1.5
EGL_VENDOR  : Mesa Project
note        : no window surface, using surfaceless context
GL_VENDOR   : Mesa
GL_RENDERER : Mali-G72 (Panfrost)
GL_VERSION  : OpenGL ES 3.1 Mesa 25.0.7
GL_SL_VERSION: OpenGL ES GLSL ES 3.10
clear+read  : rgba(64,128,191,255) err=0x0
RESULT      : render OK
```

«note: no window surface» — `gbm_surface_create()` на render-узле не нужен и не
поддерживается; контекст создаётся surfaceless (`EGL_KHR_surfaceless_context`),
рендер идёт в FBO. Для kmscube на card1 GBM-поверхность работает штатно.

`kmscube` (во время работы, снято с живого устройства):

```
== clients ==            command  tgid dev master
                         kmscube   950   1   y    y
== framebuffer ==        framebuffer[66]: allocated by = kmscube, format=XR24,
                         size=1600x2176
Rendered 904 frames in 16.021118 sec (56.425525 fps)
```

56.4 fps ≈ частота панели; KMS идёт через legacy page-flip (`drm-legacy.c`).
После выхода: `card1-DSI-1: connected/On`, `fb0` — 3168 ненулевых байт
(консоль вернулась), список DRM-клиентов пуст.

Нюанс: при запуске по SSH **без stdin** kmscube сразу печатает
`user interrupted!` — он трактует EOF на stdin как нажатие клавиши
(`poll(STDIN_FILENO)`). Поэтому в скрипте прогон идёт как `( sleep N ) | kmscube`.
Для `-c N` это тоже важно: без открытого stdin он завершится после первого кадра.

## Что осталось / следующий шаг

1. **glmark2** (`-Dflavors=drm-glesv2`, требует libdrm+gbm из sysroot и той же
   Mesa) — даст цифры производительности; сейчас есть только счётчик kmscube.
2. **DVFS**: GPU работает на 512 МГц при VGPU 900 мВ / VSRAM 1000 мВ (см.
   `docs/panfrost-plan.md` §3). Для скорости нужно вернуть OPP, но только
   вместе с управлением VSRAM (coupler или OPP на оба рельса).
3. **Wayland/KDE**: композитору нужен тот же split-путь (KMS на card1, рендер
   на renderD128). kmsro его закрывает, но KWin/Weston надо запускать с
   `GBM_BACKENDS_PATH`/`LD_LIBRARY_PATH` из `mesa-env.sh`; проверять на
   `kwin_wayland --drm` или `weston --drm`.
4. `glxinfo`/`eglinfo` не применимы/не собраны: GLX отключён осознанно (нет
   X11), `eglinfo` тянет лишние зависимости — его роль выполняет `egl-probe`.
5. Ограничение скорости kmsro: кадр — линейный dumb-буфер (`modifier=0`),
   композиция без AFBC/tiling. Для десктопа это может стать узким местом —
   проверить на Weston/KWin, а не на кубе.

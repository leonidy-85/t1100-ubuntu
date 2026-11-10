# Wayland-композитор на T1100: план, сборка, запуск (фаза 4)

Состояние на 10.11.2026: Ubuntu 24.04 arm64 на `p54`, systemd, SSH по USB-RNDIS;
дисплей — `mediatek-drm` = `/dev/dri/card1` (панель DSI 1600x2176), GPU —
panfrost = `/dev/dri/card0`/`renderD128`, Mesa 25.0.7 в `/usr/local`
(`docs/mesa-cross.md`), `kmscube -D card1` = 56.4 fps. На планшете **нет сети**
(apt не работает) — всё привозится по SSH в `/usr/local`.

Здесь: почему первый композитор — Weston, что и как собрано кроссом, как
запускать и что может сломаться.

## 1. Выбор композитора: Weston (kiosk-shell), не KWin/GNOME

| | Weston 13 | KWin (Plasma) | Mutter (GNOME) |
|---|---|---|---|
| зависимости в рантайме | 15 .so (wayland, xkbcommon, input, pixman, seat, display-info, glib+gudev через libwacom) | Qt5/Qt6 Base+Declarative, KF5/KF6 (≥30 фреймворков), KDecoration, libepoxy, dbus, logind | GTK4, gjs, glib/gio, dbus-daemon, mutter-common, xdg-desktop-portal, systemd user session, dconf |
| кросс-сборка | meson + 1 сисколл pkg-config; собрано за 336 шагов | нет практичного кросс-пути: Qt-плагины, KF5 ECM, qml-кэш | нет практичного кросс-пути: gjs/meson-js, gsettings-схемы, порталы |
| seat/logind | libseat c `builtin` backend → работает от root без logind/seatd | требует logind/seatd (сессия, DRM master через logind) | требует systemd-logind + user session |
| память на 4 ГБ | ~20–40 МБ RSS + GLES | 500 МБ+ | 700 МБ+ |
| kmsro (KMS card1 + рендер panfrost) | проверяется одним прогоном | тот же путь, но отладка внутри Qt/KWin | тот же путь, отладка внутри mutter |
| что даёт сейчас | доказательство «KMS+GBM+EGL+композиция» на железе | десктоп | десктоп |

Смысл шага — проверить **сам путь** «KMS на card1 + GBM/EGL через kmsro →
panfrost + композиция кадров», а не получить десктоп. Для этого Weston —
минимальный инструмент с теми же системными вызовами, что будут у KWin/Mutter:
`libseat_open_seat`, `gbm_create_device(card1)`, `EGL_PLATFORM_GBM`,
atomic/legacy commit, `libinput` для ввода. Поэтому: сначала Weston, потом
(когда путь подтверждён и поднят ввод) — GNOME/KDE как отдельная задача
userspace-дистрибутива, а не как первый тест.

Внутри Weston выбран **kiosk-shell**, а не desktop-shell: desktop-shell тянет
клиент `weston-desktop-shell` на toytoolkit → cairo → freetype/fontconfig/X11
и шрифты (ещё ~15 .so и 10 МБ данных), а панель/фон всё равно бесполезны, пока
нет ввода и приложений. kiosk-shell не требует клиентов и просто
fullscreen'ит первое окно — этого достаточно, чтобы увидеть кадры и снять fps.

Мелочь из документации Weston, которая решает запуск без logind: в Weston 13
**нет опции `--tty`** (VT-переключение ушло вместе с launcher'ом), seat
открывается только через libseat. У libseat в noble собраны три backend'а
(`seatd`, `logind`, `builtin`), выбор — переменной `LIBSEAT_BACKEND`. От root
работает `builtin`: он открывает `/dev/dri/*` и `/dev/input/*` напрямую, никакой
VT/логин-сессии не нужно. Отсюда `LIBSEAT_BACKEND=builtin` в обёртке
(`/usr/local/bin/weston-env.sh`).

## 2. Зависимости и версии

Всё — noble 24.04 (как на планшете), sysroot `/home/l/t1100-sysroot`:

| Компонент | Версия | Откуда |
|---|---|---|
| Weston | **13.0.0** | tarball `wayland.freedesktop.org/releases` (301 → нужен `curl -L`) |
| wayland (client/server/cursor/egl) | 1.22.0-2.1build1 | libwayland-dev/-client0/-server0/-cursor0/-egl1 |
| wayland-protocols | 1.45-1~ubuntu0.24.04.2 | arch:all, **версия запинена** |
| libxkbcommon | 1.6.0-1build1 | + `xkb-data` 2.41-2ubuntu1.1 (арх:all, в bundle) |
| libinput | 1.25.0-1ubuntu3.7 | тянет libevdev 1.13.1, libmtdev 1.1.6, libwacom 2.10, libgudev, glib |
| libpixman | 0.42.2-1build1 | — |
| libseat | 0.8.0-1 | backend `builtin` в сборке Ubuntu есть (проверено `strings`) |
| libdisplay-info | 0.1.1-2build1 | EDID/имена выходов в drm-backend |
| libdrm | 2.4.125 | из sysroot (как у Mesa) |
| Mesa (EGL/GLESv2/GBM/gallium, kmsro) | 25.0.7 | уже в `/usr/local` от фазы 3 |
| glibc | 2.39 | sysroot |

Weston 13, а не 14/15: 13.0.0 — версия noble, её зависимости совпадают с
sysroot один-в-один (wayland ≥1.22, wayland-protocols ≥1.31, libdisplay-info
0.1.1). Более новые требуют libdisplay-info ≥0.2/wayland ≥1.23 и потянули бы
второй sysroot.

## 3. Сборка (кросс, build-хост)

```sh
scripts/build-weston-aarch64.sh            # сборка + забор bundle в build/weston-aarch64
scripts/build-weston-aarch64.sh --clean    # с нуля
scripts/build-weston-aarch64.sh --fetch    # только забрать готовое
```

Сама сборка — `scripts/remote/build-weston-aarch64.sh`, cross-file —
`tools/cross-aarch64-weston.txt` (отличие от mesa-варианта: в pkg-config и в
`-I/-L` добавлен `mesa-install`, потому что EGL/GLESv2/gbm собраны нами, а не
взяты из noble).

Конфигурация meson (всё лишнее выключено):

```
--prefix=/usr/local --libdir=lib/aarch64-linux-gnu --buildtype=release
-Dbackend-default=drm -Dbackend-drm=true -Dbackend-drm-screencast-vaapi=false
-Dbackend-headless=false -Dbackend-x11=false -Dbackend-wayland=false
-Dbackend-rdp=false -Dbackend-vnc=false -Dbackend-pipewire=false
-Dscreenshare=false -Dremoting=false -Dpipewire=false
-Drenderer-gl=true -Dxwayland=false -Dsystemd=false
-Dshell-desktop=false -Dshell-kiosk=true -Dshell-fullscreen=false -Dshell-ivi=false
-Dcolor-management-lcms=false -Ddeprecated-color-management-*=false
-Dimage-jpeg=false -Dimage-webp=false
-Ddemo-clients=false -Dsimple-clients=egl,shm
-Dresize-pool=false -Dwcap-decode=false -Dtools=
-Dtest-junit-xml=false -Ddoc=false
```

Грабли (новые, в `docs/cross-build.md` их не было):

1. **`apt-get install -d <pkg>:arm64` не работает** на этом хосте: apt
   разрешает зависимости и падает на мультиарх-конфликте
   (`libbz2-1.0:amd64` против `:arm64`, Breaks по разным версиям релизов
   26.04/noble). Рабочий путь — как в `docs/cross-build.md`:
   `apt-get download <pkg>:arm64` + `dpkg -x`, но со **явным** списком и
   runtime-библиотек тоже (dev-пакеты .pc/заголовки не тянут soname'ы).
2. `wayland-server.pc`/`wayland-client.pc` имеют `Requires.private: libffi` —
   без `libffi-dev:arm64` pkg-config говорит «нет wayland-server».
3. `cairo.pc` тянет `Requires.private` на `xext/xrender/x11/xcb/xcb-render`,
   которым нужны `xproto.pc`/`xextproto.pc`/`renderproto.pc` — это
   `x11proto-dev` (arch:all). В кэше хоста висит версия 26.04 (2025.1), а
   .pc-протоколы нужны от noble → версия **запинена** `x11proto-dev=2023.2-1`.
   Так же запинены `wayland-protocols=1.45-…` и `xkb-data=2.41-…`.
4. `libwacom.so.9` линкуется с glib/gudev, `libgallium` — с libstdc++:
   линковка падает на «undefined reference to g_*/std::*», пока в sysroot нет
   `libglib2.0-0t64`, `libpcre2-8-0`, `libgudev-1.0-0`, `libstdc++6`, `libgcc-s1`.
5. У Weston 13 **нет опции `-Dtests`** (тесты помечены `build_by_default:
   false`), но `-Dtest-junit-xml=true` по умолчанию требует libxml2 → сбрасываем.
   Сборка идёт через `ninja install`, поэтому тесты не собираются вообще.
6. `shared/` (cairo-util, image-loader) собирается всегда и требует cairo —
   поэтому cairo в sysroot нужен даже при `-Ddemo-clients=false`. В рантайм он
   не попадает: `weston-screenshooter` (единственный клиент на cairo) из bundle
   удалён, в NEEDED у `weston`/модулей cairo и X11 нет.
7. В sysroot soname — симлинк на файл с версией; при сборке bundle копировать
   надо **`cp -L`** (иначе в bundle остаются битые симлинки, и следующий проход
   замыкания считает зависимость закрытой).
8. `/usr/share/X11/xkb` в Debian/Ubuntu — симлинк на `../xkeyboard-config-2`;
   `dpkg -x` падает, если поверх него распаковывается каталог → перед
   распаковкой arch:all пакетов каталог/симлинк удаляется, а в bundle данные
   копируются с `-aL`.

## 4. Что собрано и куда положено

Bundle = будущий `/usr/local` планшета, 11 МБ (из них 4.5 МБ — xkb-данные):

```
bin/weston                       70 416
bin/weston-simple-egl            81 320
bin/weston-simple-shm            77 296
lib/aarch64-linux-gnu/libweston-13.so.0.0.0          570 088
lib/aarch64-linux-gnu/libweston-13/drm-backend.so    240 816
lib/aarch64-linux-gnu/libweston-13/gl-renderer.so    153 440
lib/aarch64-linux-gnu/weston/kiosk-shell.so           78 664
lib/aarch64-linux-gnu/weston/libexec_weston.so.0.0.0 160 184
lib/aarch64-linux-gnu/libwayland-{client,server,cursor,egl}.so.*
lib/aarch64-linux-gnu/{libxkbcommon.so.0,libpixman-1.so.0,libinput.so.10,
    libevdev.so.2,libmtdev.so.1,libwacom.so.9,libseat.so.1,libdisplay-info.so.1,
    libglib-2.0.so.0,libgobject-2.0.so.0,libgudev-1.0.so.0,libpcre2-8.so.0}
share/{weston/**,X11/xkb/**,libweston-13/**,wayland-sessions/weston.desktop}
```

sha256 (полный список — `tools/host/weston-test.sh verify`):

```
1cc61000e4549d63…  bin/weston
0498cf84817a4f46…  bin/weston-simple-egl
f660a91b5c20bad0…  bin/weston-simple-shm
fd6751e5ae638cb8…  libweston-13.so.0.0.0
18931f0800fee3d1…  weston/libexec_weston.so.0.0.0
```

Свойства:
- все ELF — `ELF 64-bit LSB …, ARM aarch64`, dynamic, `/lib/ld-linux-aarch64.so.1`;
- у `weston` NEEDED: `libexec_weston.so.0` (RUNPATH
  `/usr/local/lib/aarch64-linux-gnu/weston`) + `libc.so.6`;
- `drm-backend.so` → libweston-13, wayland, pixman, **libdrm**, libudev,
  libdisplay-info, **libgbm**, **libseat**, **libinput**;
- `gl-renderer.so` → libweston-13, pixman, **libEGL**, **libGLESv2**;
- libEGL/libGLESv2/libgbm/libgallium/libdrm **не дублируются** в bundle: они
  уже в `/usr/local` от фазы 3 (`docs/mesa-cross.md`), `deploy` их не трогает,
  `check` проверяет их наличие.

Meson-пути вкомпилированы от `--prefix=/usr/local`: MODULEDIR =
`/usr/local/lib/aarch64-linux-gnu/weston`, DATADIR = `/usr/local/share` —
поэтому `WESTON_MODULE_MAP` и `WESTON_DATA_DIR` не нужны.

## 5. Порядок запуска

```sh
tools/host/weston-test.sh deploy     # разложить в /usr/local (rootfs не трогается)
tools/host/weston-test.sh check      # Mesa, /dev/dri, xkb, /run/user/0, /dev/input
tools/host/weston-test.sh smoke 10   # прогон 10 с + weston-simple-egl
tools/host/weston-test.sh run        # интерактивно для владельца (фон + лог)
tools/host/weston-test.sh stop|log|undeploy
```

Окружение (`/usr/local/bin/weston-env.sh`):

```sh
LD_LIBRARY_PATH=/usr/local/lib/aarch64-linux-gnu
GBM_BACKENDS_PATH=/usr/local/lib/aarch64-linux-gnu/gbm
XKB_CONFIG_ROOT=/usr/local/share/X11/xkb     # /usr/share/X11/xkb на планшете нет
XDG_RUNTIME_DIR=/run/user/0                  # mkdir -p, chmod 700
LIBSEAT_BACKEND=builtin                      # без logind/seatd/VT
XDG_SEAT=seat0
```

Команда:

```sh
mkdir -p /run/user/0 && chmod 700 /run/user/0
. /usr/local/bin/weston-env.sh
/usr/local/bin/weston --backend=drm --drm-device=card1 --shell=kiosk \
    --socket=wayland-t1100 --idle-time=0 --log=/tmp/weston.log
```

`--drm-device=card1` обязателен: без него drm-backend выбирает «первичный» GPU
по udev и может взять `card0` (panfrost), который не умеет modeset. `card1` —
`mediatek-drm`; рендер уходит на `renderD128` через kmsro (тот же путь, что у
`kmscube -D card1`).

Критерий smoke: в логе нет `fatal`/`failed to`, появился сокет
`/run/user/0/wayland-t1100`, а `weston-simple-egl` печатает
`N frames in 5 seconds: X fps` (значит композитор реально отдаёт кадры и
GLES-рендер идёт через panfrost). Клиент запускается отдельно:

```sh
. /usr/local/bin/weston-env.sh
WAYLAND_DISPLAY=wayland-t1100 /usr/local/bin/weston-simple-egl
```

## 6. Риски и что осталось непроверенным

1. **kmsro dumb-буферы.** На `card1` GBM выдаёт линейный буфер (`modifier=0`),
   без AFBC/tiling: композиция идёт через чтение-запись в память. Для куба это
   неважно (56 fps), для полноэкранного десктопа на 1600x2176 станет узким
   местом. Мерить: fps `weston-simple-egl` + счётчики `drm`/`panfrost`
   (загрузка DDR). Если упрёмся — отдельная задача про renderonly-форматы в
   `mediatek-drm`/kmsro.
2. **Нет logind/seatd.** Работаем `LIBSEAT_BACKEND=builtin` от root: сессия
   считается всегда активной, VT-переключения нет, и `weston` не отдаст
   DRM master обратно при выходе, пока fbcon сам не перерисуется (у `kmscube`
   консоль возвращалась — проверим и здесь). Для KWin/Mutter этот путь не
   годится, им нужен logind или seatd — это отдельный пункт фазы 4.
3. **Ввод.** `libinput` через `builtin`-seat получит `/dev/input/event*`
   (`event0`, `event1` на плате есть), но появится ли тач-устройство в
   list-устройств — зависит от ядерного драйвера панели (в mainline-порте
   тачтайный драйвер ещё не проверялся). Пока композитор запускаем без
   ожидания ввода: kiosk-shell + клиент по SSH. Курсор/тач — следующий шаг,
   вместе с `docs/hardware.md` §тач.
4. **Нет шрифтов/текста.** cairo/freetype/fontconfig в bundle не входят
   (desktop-shell и текстовые клиенты отключены). `weston-simple-egl`/`-shm`
   текста не рисуют — для панели/терминала понадобится отдельный шаг
   (шрифты + cairo-стек).
5. **atomic или legacy.** mediatek-drm в 6.12 умеет atomic, но drm-backend
   Weston умеет и fallback на legacy (`device->atomic_modeset`). Что выберется
   на этом порте — увидим в логе (`atomic` vs `legacy`), на функциональность
   это не влияет.
6. **Параллельный доступ к устройству.** Экран один: `weston` держит DRM
   master, и `kmscube`/`glmark2`/`modetest` в это время упадут
   (`Failed to become DRM master`). Прогоны — только по одному, по
   согласованию с `lead` (AGENTS.md, «Устройство — эксклюзивный ресурс»).
7. **Питание/DVFS.** GPU по-прежнему на 512 МГц (OPP выключен), экран
   включённый ест батарею; во время длинных прогонов следить за `vbat`
   (`tools/host/watch-power.sh`).
8. **Не проверено на железе:** сам запуск `weston` (модуль не загружался —
   на момент сборки панель была занята прогоном `kmscube`, а `glmark2` готовил
   `gpu-mesa`). Проверять `tools/host/weston-test.sh smoke 10` после отбоя.

## 7. Дальше (после успешного smoke)

1. `weston-debug`/`--debug` + `WAYLAND_DEBUG=client` при проблемах с кадрами.
2. Тач: проверить `libinput list-devices` (собрать статически или
   `weston-info`), при необходимости — драйвер тача в DTS (`kernel-drm`/`bringup`).
3. Desktop-shell или лёгкий шелл на GTK4 (`gtk4-demo`/`gtk4-wayland`) — тогда
   понадобятся cairo, freetype, fontconfig, шрифты и `libxkbcommon`-раскладка.
4. GNOME/KDE: отдельная фаза — нужен logind/seatd, DBus, systemd user session
   и сеть для пакетов (сейчас её нет: привозить `.deb`-ы и распаковывать в
   `/usr/local`, как здесь).

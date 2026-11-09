# Кросс-сборка: ядро, userspace-утилиты, sysroot

Всё тяжёлое собирается **на build-хосте**, не на ноутбуке (см. `AGENTS.md`).

| | |
|---|---|
| хост | `172.17.141.172` |
| доступ | `l` / пароль `0` (`sudo` тот же пароль), 12 ядер, 15 ГБ RAM, Ubuntu 26.04 |
| тулчейн | `gcc-aarch64-linux-gnu` (GCC 15), `binutils-aarch64-linux-gnu` |
| прочее | `meson`, `ninja-build`, `ccache`, `rsync`, `bison`, `flex`, `libelf-dev`, `libssl-dev`, `debootstrap` |
| каталоги | `/home/l/t1100-ubuntu-build/{src,out}` — ядро, `/home/l/t1100-tools` — userspace, `/home/l/t1100-sysroot` — arm64-sysroot |

## 1. Ядро

```sh
scripts/build-kernel-remote.sh              # rsync -> defconfig+fragment -> Image dtbs
scripts/build-kernel-remote.sh --clean      # снести out/ на хосте
scripts/build-kernel-remote.sh --config     # только конфиг
```

- дерево синхронизируется без `.git`, поэтому версия ядра задаётся явно:
  `LOCALVERSION=-g<sha10>[-dirty]` — `uname -r` совпадает с локальной сборкой;
- артефакты: `build/remote/Image` (+ `Image.sha256`) и `build/remote/dtbs/`;
- лог: `build/logs/build-remote-<метка>.log`;
- полная сборка с нуля — ~8 минут; с прогретым `ccache` инкремент после правки
  конфига/файлов — секунды-минуты;
- `ccache` включён через **маскировку**: `~/.ccache-bin/aarch64-linux-gnu-gcc` →
  `ccache`, каталог первым в `PATH`, `CCACHE_DIR=~/.ccache-t1100`. Форма
  `make CC="ccache <gcc>"` не работает — kbuild/ccache отвечают
  «unknown C compiler».

## 2. Userspace-утилиты (статически)

В rootfs планшета нет ни apt-сети, ни `libdrm`, поэтому тестовые утилиты
собираются статически и заливаются по SSH.

```sh
scripts/build-tools-aarch64.sh      # libdrm 2.4.131 -> build/tools-aarch64/modetest
tools/host/kms-test.sh --dump       # снять отчёты modetest на планшете
tools/host/kms-test.sh --hold 30    # выставить режим DSI-1 и подержать 30 с
```

- libdrm собирается meson'ом с cross-file (см. скрипт), `-Ddefault_library=static`
  + `-Dc_args=-static -Dc_link_args=-static`; цель `modetest` лежит в
  `build-libdrm/tests/modetest/modetest` (каталог, не файл — не путать);
- `kmscube`/`glmark2` здесь **не собираются**: им нужны GBM/EGL/GLESv2, то есть
  Mesa под aarch64 и работающий panfrost (фаза 3).

## 3. arm64-sysroot (для Mesa и прочего линкующегося)

`/home/l/t1100-sysroot` — Ubuntu **noble** (24.04, как на планшете): `libc 2.39`,
`libdrm 2.4.125` (noble-updates), `libudev 255.4`. Нужен, когда бинарник должен
линковаться с библиотеками планшета, а не статически (Mesa/EGL в фазе 3).

Как он сделан (и на чём спотыкались):

```sh
# 1) база
sudo debootstrap --arch=arm64 --variant=minbase noble /home/l/t1100-sysroot \
     http://ports.ubuntu.com/ubuntu-ports

# 2) arm64-пакеты на хосте: отдельный источник + чистый мультиарх
sudo dpkg --add-architecture arm64
# /etc/apt/sources.list.d/ubuntu-ports.sources
#   Types: deb
#   URIs: http://ports.ubuntu.com/ubuntu-ports
#   Suites: noble noble-updates noble-security
#   Components: main restricted universe multiverse
#   Architectures: arm64
#   Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
# в основном ubuntu.sources добавить "Architectures: amd64", иначе apt тянет
# arm64 из хостового релиза (26.04) и в sysroot попадает libudev 259 вместо 255.

# 3) dev-пакеты распаковкой (chroot не нужен, arm64-бинари не запускаем)
cd /tmp && apt-get download libdrm-dev:arm64 libdrm2:arm64 libudev-dev:arm64 libudev1:arm64
for f in /tmp/*.deb; do sudo dpkg -x "$f" /home/l/t1100-sysroot; done
```

Грабли:
- второй этап `debootstrap` в chroot требует эмуляции — в apt пакет называется
  **`qemu-user`** (не `qemu-user-static`), плюс `qemu-user-binfmt`; но даже с ним
  second-stage падает на `/debootstrap/mirror` — проще не доводить его, а
  распаковывать dev-пакеты (см. выше);
- `printf ... | sudo -S tee file` **не работает** (sudo -S съедает stdin паролем):
  писать временный файл и `sudo cp`;
- .pc-файлы в sysroot указывают на `/usr/lib/aarch64-linux-gnu`, поэтому в meson
  cross-file обязателен `sys_root` + `pkg_config_libdir` (см. ниже).

Проверка, что sysroot линкуется (сделано 10.11):

```sh
aarch64-linux-gnu-gcc --sysroot=/home/l/t1100-sysroot \
  -I/home/l/t1100-sysroot/usr/include/libdrm t.c -o t \
  -L/home/l/t1100-sysroot/usr/lib/aarch64-linux-gnu -ldrm
# file: ELF 64-bit LSB pie executable, ARM aarch64, dynamically linked
# readelf -d: NEEDED libdrm.so.2, libc.so.6
```

Meson cross-file:

```
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'

[properties]
sys_root = '/home/l/t1100-sysroot'
pkg_config_libdir = ['/home/l/t1100-sysroot/usr/lib/aarch64-linux-gnu/pkgconfig',
                     '/home/l/t1100-sysroot/usr/share/pkgconfig']

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
```

## 4. Что где лежит на хосте

```
/home/l/t1100-ubuntu-build/src   # rsync-копия ../linux-t1100
/home/l/t1100-ubuntu-build/out   # O= , инкрементальная сборка ядра
/home/l/t1100-tools/             # libdrm и прочие исходники userspace
/home/l/t1100-sysroot/           # arm64 sysroot (noble)
~/.ccache-t1100                  # кэш компиляции
```

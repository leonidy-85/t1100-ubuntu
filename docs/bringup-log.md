# Bring-up log — фаза 1 (SoC bring-up)

Фактический журнал действий агента `bringup`. Только проверенные команды и их
вывод; никаких предположений. Секреты/пароли не пишутся.

Обозначения: всё, что ниже, выполнено на хосте
`Ubuntu, 4 ядра, 29 ГБ RAM` под пользователем `l`.

---

## Шаг 1. Получение дерева linux 6.12.y (2026-10-28)

### 1.1. Поиск актуального релиза в ветке 6.12.y

Листинг CDN kernel.org:

```console
$ curl -sS https://cdn.kernel.org/pub/linux/kernel/v6.x/ -o k6x.html
$ grep -oE 'linux-6\.12\.[0-9]+\.tar\.xz' k6x.html | sort -u | wc -l
114
$ grep -oE 'linux-6\.12\.[0-9]+\.tar\.xz' k6x.html | sort -u -t. -k3,3n | tail -3
linux-6.12.112.tar.xz
linux-6.12.113.tar.xz
linux-6.12.114.tar.xz
```

Проверка, что это действительно существующий файл (а не мусор в листинге):

```console
$ curl -sSI https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.114.tar.xz | head -5
HTTP/2 200
server: nginx
content-type: application/x-xz
last-modified: Wed, 21 Oct 2026 08:45:57 GMT
x-frame-options: DENY
```

**Итог: актуальный релиз ветки — `6.12.114`** (загружен 21.10.2026).

### 1.2. Скачивание tarball (без `git clone`)

```console
$ cd /home/l/projects
$ time curl -sS --retry 3 --max-time 900 -O https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.114.tar.xz
real    1m48,907s
$ ls -l linux-6.12.114.tar.xz
-rw-r--r-- 1 l l 148721296 Oct 28 22:14 linux-6.12.114.tar.xz
```

### 1.3. Проверка контрольной суммы по официальному источнику

`sha256sums.inc` на CDN отсутствует (404). Официальный подписанный список —
`sha256sums.asc` в том же каталоге:

```console
$ curl -sS -O https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
$ grep 'linux-6.12.114.tar.xz' sha256sums.asc
7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3  linux-6.12.114.tar.xz

$ sha256sum linux-6.12.114.tar.xz
7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3  linux-6.12.114.tar.xz
```

**Совпадает** с `sha256sums.asc` kernel.org. (GPG-подпись `sha256sums.asc`
отдельно не проверялась — ключи kernel.org на хост не импортировались.)

### 1.4. Распаковка в `/home/l/projects/linux-t1100`

Как и было задано, дерево лежит **вне репозитория проекта**.

```console
$ mkdir -p /home/l/projects/linux-t1100
$ time tar -xJf linux-6.12.114.tar.xz -C linux-t1100 --strip-components=1
real    0m22,228s
$ du -sh linux-t1100
1,6G    linux-t1100
```

Проверка версии дерева:

```console
$ cd /home/l/projects/linux-t1100 && make kernelversion
6.12.114
$ head -5 Makefile
# SPDX-License-Identifier: GPL-2.0
VERSION = 6
PATCHLEVEL = 12
SUBLEVEL = 114
EXTRAVERSION =
```

Шаблоны для будущего DTS-порта на месте:
`arch/arm64/boot/dts/mediatek/mt8183.dtsi`, `mt8365.dtsi`.

---

## Шаг 2. Скрипт сборки `scripts/build_kernel.sh`

Написан воспроизводимый скрипт (`set -euo pipefail`):

- `ARCH=arm64`, `CROSS_COMPILE=aarch64-linux-gnu-`;
- out-of-tree сборка `O=<repo>/build/t1100` (каталог `/build/` в `.gitignore`);
- `make defconfig` → `make -j4 Image dtbs modules_prepare`;
- проверяет наличие кросс-компилятора, печатает `make kernelversion`, версии gcc
  и dtc;
- пишет лог в `build/logs/build-<timestamp>.log`, при ошибке печатает rc и
  `tail -n 60` лога и выходит с кодом ошибки (через `PIPESTATUS[0]`, а не
  `tee`);
- в конце печатает время сборки, число `warning:`, `ls -l` + `sha256sum` для
  `Image` и для всех DTB mediatek, сводку по всем собранным DTB и полный
  `.dtbs.sha256`-файл.

Опции: `--clean` (снести `OUT`), `--defconfig` (только конфиг), `--help`.
Переопределения через env: `KERNEL_SRC`, `OUT`, `CROSS_COMPILE`, `ARCH`,
`JOBS`, `KCONFIG`.

Проверка синтаксиса и справки:

```console
$ bash -n scripts/build_kernel.sh && echo "syntax ok"
syntax ok
$ scripts/build_kernel.sh --help    # печатает usage
```

---

## Шаг 3. Baseline-сборка `defconfig`

Запуск:

```console
$ cd /home/l/projects/t1100-ubuntu
$ scripts/build_kernel.sh
```

Печатаемая скриптом шапка (фактический вывод):

```
== t1100 kernel build ==
repo         : /home/l/projects/t1100-ubuntu
kernel src   : /home/l/projects/linux-t1100
output       : /home/l/projects/t1100-ubuntu/build/t1100
arch         : arm64
cross        : aarch64-linux-gnu-
jobs         : 4
config target: defconfig
log          : /home/l/projects/t1100-ubuntu/build/logs/build-20261028-234517.log
kernelversion: 6.12.114
compiler     : aarch64-linux-gnu-gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0
dtc          : Version: DTC 1.7.2
```

### 3.1. Хронология (важно для оценки времени)

Сборка шла **в два приёма**, потому что мой инструментальный вызов был прерван
по таймауту (90 мин) — это не ошибка компиляции:

| Прогон | Окно | Итог |
|---|---|---|
| 1 | 22:15:07 → 23:45 (≈90 мин) | прерван извне (tool timeout), `make` был в `drivers/`; лог `build-20261028-221507.log` |
| 2 | 23:45:17 → 03:09:26 | **BUILD OK in 202m35s** (инкрементально продолжил прогон 1); лог `build-20261028-234517.log` |

Суммарно ≈ **4 ч 52 мин** машинного времени. Причина медленности — не дерево,
а загрузка хоста: `uptime` в процессе сборки показывал
`load average: 20,12, 23,38, 24,18` при **4 ядрах** (параллельно шли другие
задачи, например Go-сборки из соседних проектов). Цифра «202m35s» — это время
**второго** прогона; первый прогон (90 мин) свой вклад тоже внёс, отдельного
замера «чистой» сборки на разгруженном хосте нет.

### 3.2. Результат

```
BUILD OK in 202m35s

== result ==
kernelversion : 6.12.114
build time    : 202m35s
warnings      : 0
```

```console
$ make -s -C /home/l/projects/linux-t1100 O=/home/l/projects/t1100-ubuntu/build/t1100 \
       ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease
6.12.114
```

(`CONFIG_LOCALVERSION_AUTO=y` в defconfig, но дерево не git — суффикса нет;
для сборки из git-дерева версия получила бы `-g<hash>`.)

`Image`:

```console
$ ls -l build/t1100/arch/arm64/boot/Image
-rw-r--r-- 1 l l 38531584 Oct 29 03:09 build/t1100/arch/arm64/boot/Image
$ sha256sum build/t1100/arch/arm64/boot/Image
2a2cab580aa9ee3036802b7aee6edfc269d901bf70bb53f573a9719700b545a6  build/t1100/arch/arm64/boot/Image
$ file build/t1100/arch/arm64/boot/Image
... Linux kernel ARM64 boot executable Image, little-endian, 4K pages
$ dd if=.../Image bs=1 skip=56 count=4    # magic по смещению 0x38
ARMd
$ strings .../Image | grep 'Linux version'
Linux version 6.12.114 (l@l-T480) (aarch64-linux-gnu-gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0, GNU ld (GNU Binutils for Ubuntu) 2.46) #1 SMP PREEMPT Thu Oct 29 03:07:31 MSK 2026
```

Image — **несжатый** (38 531 584 B ≈ 36,7 МиБ), что ожидаемо: это артефакт
`make Image`. Для MTK `boot.img` его придётся сжимать (gzip/lz4) при
перепаковке — это шаг фазы прошивки, здесь не делался.

DTB (фактические цифры):

```console
$ find build/t1100/arch/arm64/boot/dts -name '*.dtb' | wc -l
1191
$ find build/t1100/arch/arm64/boot/dts/mediatek -name '*.dtb' | wc -l
83
$ ls -l build/t1100/arch/arm64/boot/dts/mediatek/mt8183-evb.dtb \
        build/t1100/arch/arm64/boot/dts/mediatek/mt8365-evk.dtb
-rw-r--r-- 1 l l 47858 Oct 28 22:16 .../mediatek/mt8183-evb.dtb
-rw-r--r-- 1 l l 24865 Oct 28 22:16 .../mediatek/mt8365-evk.dtb
$ sha256sum .../mediatek/mt8183-evb.dtb .../mediatek/mt8365-evk.dtb
0f53558e3aaf6c8da5c1f754b33a938c5ea4a9b22dd6ee57cab4c9e4a776a9bc  mt8183-evb.dtb
fff6fa0b9c62ad3faf932f04bef41162267be26476044d7ad517b56c764d4ec5  mt8365-evk.dtb
```

Полный список `sha256` всех 1191 DTB:
`build/logs/build-20261028-234517.dtbs.sha256` (пути относительно
`build/t1100/arch/arm64/boot/dts/`).

MD5/sha `.config` (для воспроизводимости baseline):

```console
$ sha256sum build/t1100/.config
b337952acafe1af350aaf8821021daf2bdf7c19d388d8096a3d3c7a052070134  build/t1100/.config
```

Заметные опции сгенерированного `arm64 defconfig`:
`CONFIG_ARCH_MEDIATEK=y`, `CONFIG_MODULES=y`, `CONFIG_DEBUG_INFO=y`,
`CONFIG_LOCALVERSION=""`, `CONFIG_LOCALVERSION_AUTO=y`, `CONFIG_KALLSYMS=y`.

Размеры артефактов (для понимания, откуда 38 МБ):

```console
$ ls -l build/t1100/vmlinux        # с CONFIG_DEBUG_INFO=y
148660280  build/t1100/vmlinux      # 141,8 МиБ
$ du -sh build/t1100
1,5G
$ grep -c '=y$' build/t1100/.config
3181
```

`Image` (38,5 МБ) — уже objcopy-выгрузка без отладочной информации; крупный
размер — следствие 3181 встроенной (`=y`) опции defconfig, а не debug info.

### 3.3. Предупреждения

```
build/logs/build-20261028-221507.log: 0 warning, 0 error
build/logs/build-20261028-234517.log: 0 warning, 0 error
```

`grep -c 'warning:'` по **обоим** логам (прогон 1 + прогон 2, т.е. весь объём
компиляции) — ноль. Предупреждений и ошибок сборки нет.

### 3.4. `modules_prepare`

Выполнен в том же вызове `make`, rc=0:

```console
$ ls build/t1100/include/config/kernel.release build/t1100/include/generated/autoconf.h
build/t1100/include/config/kernel.release
build/t1100/include/generated/autoconf.h
$ cat build/t1100/include/config/kernel.release
6.12.114
```

`Module.symvers` отсутствует — это **нормально**: он создаётся `modpost` при
`make modules`, а не `modules_prepare`; сами модули в этом прогоне не собирались
(цель — только `Image` + `dtbs`).

### 3.5. Размеры на диске

```console
$ du -sh /home/l/projects/linux-t1100 build/t1100 build/logs
1,6G    /home/l/projects/linux-t1100
1,5G    build/t1100
540K    build/logs
```

---

## Итог шага (критерий: baseline собирается)

- Дерево: **linux 6.12.114** (официальный tarball, sha256 сверен), вне репозитория —
  `/home/l/projects/linux-t1100`.
- Скрипт: `scripts/build_kernel.sh` (падает при ошибке, логирует, печатает
  версию/размеры/sha256).
- `make defconfig` + `make -j4 Image dtbs modules_prepare` — **OK**, 0 warnings,
  `Image` 38 531 584 B,
  sha256 `2a2cab580aa9ee3036802b7aee6edfc269d901bf70bb53f573a9719700b545a6`,
  1191 DTB (83 mediatek).
- Тулчейн (gcc 15.2, dtc 1.7.2, binutils 2.46) рабочий — сборка ядра под arm64
  на хосте подтверждена фактически.

## Что НЕ делалось (и почему)

- **DTS-порт (`mt6771.dtsi`/`mt6771-t1100.dts`) не начат** — по заданию это
  следующий заход.
- **Планшет не трогался**: ни прошивок, ни `dd`, ни `reboot`.
- **Свой конфиг не писался** — только `defconfig`, как baseline проверки
  тулчейна.
- `docs/STATUS.md` не изменялся (файл `lead`).

## Наблюдения для следующего шага

1. **Время сборки — узкое место на этом хосте** (load average 20–28 при 4 ядрах).
   Для итераций по DTS собирать точечно:
   `make ... arch/arm64/boot/dts/mediatek/<board>.dtb`
   (полный `Image` — только когда меняются C-файлы clk/pinctrl/mmsys).
2. `defconfig` для arm64 — baseline тулчейна, не целевой конфиг: `vmlinux`
   141,8 МиБ из-за `CONFIG_DEBUG_INFO=y`, Image 36,7 МиБ несжатый. Для прошивки
   понадобится отдельный `t1100_defconfig` (без debug info, с нужными
   `CONFIG_DRM_MEDIATEK`, `CONFIG_DRM_PANFROST`, `mt6577-uart`, `mtk-sd`,
   `mtu3`/`xhci-mtk`, `pstore`/`ramoops`) и сжатие при перепаковке boot.
3. `CONFIG_LOCALVERSION_AUTO=y` в defconfig: если позже собирать из git-дерева,
   версия станет `6.12.114-g<hash>` — для сверки `dmesg` на плате это надо
   учитывать (в нашем случае дерево не git, версия чистая).
4. Полный `log` и `.dtbs.sha256` лежат в `build/logs/` (каталог в `.gitignore`) —
   факты перенесены сюда, артефакты не коммитятся.

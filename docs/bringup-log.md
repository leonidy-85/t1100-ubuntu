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
---

## Шаг 4. Минимальный Device Tree MT6771 (2026-10-29)

Цель шага: `mt6771.dtsi` + `mt6771-fplus-t1100.dts`, DTB собирается, узлы
на месте. Планшет не трогался: ни прошивок, ни `dd`, ни `reboot`.

### 4.1. Ядро теперь под git (baseline — отдельный коммит)

```console
$ cd /home/l/projects/linux-t1100
$ git init -q -b master .          # user.name=bringup, user.email=bringup@t1100.local (локально)
$ git add -A && git commit -m "TREE: baseline linux 6.12.114 (kernel.org tarball, unmodified)"
```

Факт: `git add -A` по 86 707 файлам занял **4m38s** (load average 28 на 4 ядрах),
размер `.git` после коммита ≈ 220 МиБ. Коммиты:

| Коммит | Что |
|---|---|
| `728cd6e` | TREE: baseline linux 6.12.114 (без изменений) |
| `654b5aa` | arm64: dts: mediatek: add minimal MT6771 SoC description |
| `e8d525f` | arm64: dts: add Fplus T1100 (MT6771) board |

### 4.2. Сверка stock DTS с mainline `mt8183.dtsi`

Сверялось по `refs/stock-mt6771.dts` (4754 строки) и
`refs/device/fdt-live.dts.gz` (6175 строк).

| Что | Stock MT6771 | mainline MT8183 | Вывод |
|---|---|---|---|
| GIC | `arm,gic-v3`, GICD `0x0c000000`+0x40000, GICR `0x0c100000`+0x200000 | то же | версия — **GICv3**, не gic-400 |
| sysirq | `mediatek,mt6771-sysirq`/`mt6577-sysirq`, reg `0x0c530a80`+0x50 | `mt8183-sysirq`, `0x0c530a80`+0x50 | идентично, кроме compatible |
| timer | `arm,armv8-timer`, PPI 13/14/11/10, `clock-frequency` 13 МГц | то же (без clock-frequency) | совпадает |
| uart0 | `mediatek,mt6577-uart`, `0x11002000`, hwirq `0x5b`, LEVEL_LOW (8) | `GIC_SPI 91`, LEVEL_LOW | совпадает |
| память | live FDT: `reg = <0 0x40000000 1 0>` | — | **4 ГиБ** по 0x40000000 |
| ramoops | `pstore` `0x54410000`+0xe0000 (`no-map`), `ram_console` `0x54400000`+0x10000 | — | совпадает с `refs/device/iomem.txt` |
| CPU | 4×A53 (reg 0/1/2/3) + 4×A73 (reg 0x100…0x103), `enable-method = "psci"` | то же | совпадает |
| **PSCI** | **есть**: `psci { compatible = "arm,psci-1.0"; method = "smc"; }` (стр. 209–213 stock DTS) | есть | **посылка задания неверна** — см. 4.9.1 |
| i2c0 | `0x11007000`, `0x11000080`+0x80, hwirq `0x51`, `clock-div = 5` | `GIC_SPI 81`, `clock-div = 1` | адрес/IRQ совпадают |
| дисплей/GPU/PMIC | DISPSYS `0x14000000`, GPU `0x13040000`, MT6358 | есть | в этот шаг **не включались** (см. 4.10) |

Проверка «hwirq в stock DTS == `GIC_SPI` в mainline» (важно, см. 4.9.3):
`mtk_sysirq_domain_translate` (mainline `drivers/irqchip/irq-mtk-sysirq.c`)
принимает только 3 ячейки, `param[0] == 0` (SPI) и передаёт hwirq в GIC
**без смещения**. Подтверждение на двух узлах:

- stock `msdc@11230000` hwirq `0x4d` = 77 ↔ mainline mt8183 `mmc0` `GIC_SPI 77`;
- stock `i2c@11007000` hwirq `0x51` = 81 ↔ mainline mt8183 `i2c0` `GIC_SPI 81`.

### 4.3. `arch/arm64/boot/dts/mediatek/mt6771.dtsi` (300 строк)

| Узел | Значение | Источник |
|---|---|---|
| `/` | `compatible = "mediatek,mt6771"`, `interrupt-parent = <&sysirq>`, 2/2 ячейки | stock DTS |
| `aliases` | `serial0 = &uart0` | задание |
| `chosen` | `bootargs = "console=ttyS0,921600n8 earlycon=mtk8250,0x11002000 maxcpus=1 panic=10 pstore.backend=ramoops"`, `stdout-path = "serial0:921600n8"` | задание + 4.9.4 |
| `cpus` | 4×`arm,cortex-a53` @0..3, 4×`arm,cortex-a73` @0x100..0x103, **без** `enable-method` | stock DTS (reg) |
| `timer` | `arm,armv8-timer`, PPI 13/14/11/10 LEVEL_LOW, `clock-frequency = <13000000>` | stock DTS (`0xc65d40` = 13 000 000) |
| `soc/gic` | `arm,gic-v3`: GICD `0x0c000000`+0x40000, GICR `0x0c100000`+0x200000, `#redistributor-regions = <1>`, `#interrupt-cells = <3>`, `interrupts = <GIC_PPI 9 LEVEL_HIGH>` | stock DTS; наличие GICR по `0x0c100000` подтверждено dmesg стока: `GICv3: CPU0: found redistributor 0 region 0:0x000000000c100000` |
| `soc/sysirq` | `mediatek,mt6771-sysirq`,`mt6577-sysirq`, `0x0c530a80`+0x50 | stock DTS |
| `soc/pio` | заглушка: `gpio-controller`, `#gpio-cells = <2>`, `gpio-ranges … 191`, EINT `0x1000b000`, IRQ `GIC_SPI 177` LEVEL_HIGH | live FDT (`gpio-ranges = <… 0xbf>`, `apirq@1000b000 interrupts = <0 0xb1 4>`) — драйвера `pinctrl-mt6771` в mainline нет, узел не биндится |
| `soc/uart0` | `mediatek,mt6577-uart`, `0x11002000`+0x1000, `GIC_SPI 91` LEVEL_LOW, `clocks = <&clk26m>` (один клок), `status = "okay"` | stock DTS + 4.9.4 |
| `soc/i2c0` | `mediatek,mt6577-i2c`, `0x11007000`+0x1000 и `0x11000080`+0x80, `GIC_SPI 81`, `clock-div = <5>`, `status = "disabled"` | stock DTS / live FDT |
| `clocks/clk26m` | `fixed-clock`, 26 000 000 Гц | stock DTS (`0x18cba80`) |
| `memory@40000000` | `reg = <0 0x40000000 1 0>` | live FDT, `/proc/iomem` |
| `reserved-memory` | 18 регионов | live FDT, см. ниже |

`reserved-memory` (все адреса — из `mblock-*` живого FDT; `no-map` — там, где он
был в стоке):

```
ram_console      0x54400000 0x10000   no-map   (pstore оставляет логи LK)
ramoops          0x54410000 0xe0000   no-map   record 0x10000, console 0x40000, pmsg 0x10000
minirdump        0x544f0000 0x10000   no-map
atf-reserved     0x54600000 0x50000   no-map
spm-reserved     0x77ff0000 0x10000   no-map
framebuffer      0x7cd80000 0x2e80000 no-map
items-reserved   0x7fc00000 0x200000  no-map
sspm-reserved    0x7ff00000 0xc0000   no-map
log-store        0x7ffc0000 0x40000
ap-md-c-smem     0x86000000 0x1600000
ap-md-nc-smem    0x88000000 0x100000
md-mem-usage     0x8c000000 0x10000000
scp-reserved     0x9cf00000 0x600000  no-map
ccci-tag-mem     0x9d5e0000 0x10000
vpu-binary       0x9d5f0000 0x2a10000 no-map
atf-log-reserved 0xbfe00000 0x40000   no-map
dramc-rk0        0xbffff000 0x1000    no-map
dramc-rk1        0x13ffff000 0x1000   no-map
```

Итого зарезервировано ≈ 380 МиБ из 4 ГиБ (больше всего — `md-mem-usage` 256 МиБ
и `framebuffer` 46,5 МиБ), пользователю остаётся ≈ 3,6 ГиБ.

### 4.4. `arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dts` (75 строк)

- `model = "Fplus T1100"`, `compatible = "fplus,t1100", "mediatek,mt6771"`;
- `&chosen { bootargs = … }` — те же аргументы, что в dtsi (переопределение через
  метку, дублирования узла нет);
- `odm/lcm` (`compatible = "elink,lcm"`, `status = "disabled"`):
  `dvdd-gpios` 55, `rst-gpios` 45, `stby-gpios` 44, `bl-gpios` 56,
  `ext-pwr-gpios` 175, `ts-rst-gpios` 158, `ts-avdd-gpios` 163 — всё из
  live FDT (`odm/lcm`, те же числа в `dvdd = <0x37 0>` и т.д.);
- `odm/lcd-backlight` (`mediatek,lcd-backlight`, `status = "disabled"`):
  `led_mode = <5>`, `data = <1>`, `pwm_config = <4 0 0 0 0>` — live FDT `odm/led@6`;
- `&i2c0 { status = "disabled"; himax_touch@48 { compatible = "mediatek,himax_touch"; reg = <0x48>; interrupt-parent = <&pio>; interrupts = <1 1 1 0>; } }` —
  live FDT `i2c@11007000/himax_touch@48` (EINT 1). Спецификация прерывания
  оставлена вендорной (4 ячейки), как в stock.

Имена узлов/свойств вендорных узлов сохранены как в оверлее (`led_mode`,
`pwm_config`, `himax_touch`) — так проще сверять с живым FDT и с будущими
драйверами; это единственные два места, где `W=1` ругается на `_` в имени узла.

### 4.5. Makefile

```diff
 dtb-$(CONFIG_ARCH_MEDIATEK) += mt6755-evb.dtb
+dtb-$(CONFIG_ARCH_MEDIATEK) += mt6771-fplus-t1100.dtb
 dtb-$(CONFIG_ARCH_MEDIATEK) += mt6779-evb.dtb
```

### 4.6. Сборка только DTB

Важная поправка к подсказке из задания: путь в цели указывается **относительно
`arch/arm64/boot/dts`** (`make … mediatek/<board>.dtb`), иначе kbuild клеит
префикс дважды:

```console
$ make -C linux-t1100 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
       O=build/t1100 arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
make[3]: *** Нет правила для сборки цели
  «arch/arm64/boot/dts/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb»
```

Рабочие варианты (оба проверены):

```console
$ make -C linux-t1100 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
       O=build/t1100 mediatek/mt6771-fplus-t1100.dtb
  DTC     arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
real    0m13,7s

$ make -C linux-t1100 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
       O=build/t1100 dtbs
  UPD     include/config/kernel.release
  DTC     arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
real    0m26,5s
```

`make dtbs` инкрементален: пересобрался только наш DTB, **0 warning / 0 error**.
Новый DTB попал в `build/t1100/arch/arm64/boot/dts/mediatek/dtbs-list` (строка 3),
mediatek-DTB стало **84** (было 83).

### 4.7. Проверка DTB

```console
$ ls -l build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
-rw-r--r-- 1 l l 4806 Oct 29 03:24 mt6771-fplus-t1100.dtb
$ sha256sum …/mt6771-fplus-t1100.dtb
bbf097afbad78334742e5365859c6b25b0758e9463330b0b99d4f702281d8b5e
$ dtc -I dtb -O dts …/mt6771-fplus-t1100.dtb -o /tmp/mt6771-built.dts   # rc=0
```

Ключевые узлы в разобранном DTB (все на месте):

```
/cpus                    8 cpu@* (cortex-a53 ×4, cortex-a73 ×4)
/soc/interrupt-controller@c000000   arm,gic-v3, GICD/GICR
/soc/interrupt-controller@c530a80   mediatek,mt6771-sysirq
/timer                    arm,armv8-timer, PPI 13/14/11/10
/soc/serial@11002000      mediatek,mt6577-uart, GIC_SPI 91
/soc/pinctrl@10005000     заглушка pio (gpio-controller)
/soc/i2c@11007000         disabled, himax_touch@48 disabled
/memory@40000000          reg = <0x00 0x40000000 0x01 0x00>
/reserved-memory/ram_console@54400000   0x10000 no-map
/reserved-memory/ramoops@54410000       compatible = "ramoops", 0xe0000,
                                        record 0x10000 / console 0x40000 / pmsg 0x10000
/chosen                   bootargs + stdout-path = "serial0:921600n8"
```

Фрагмент разобранного DTB:

```
	memory@40000000 {
		device_type = "memory";
		reg = <0x00 0x40000000 0x01 0x00>;
	};
	ramoops@54410000 {
		compatible = "ramoops";
		reg = <0x00 0x54410000 0x00 0xe0000>;
		no-map;
		record-size = <0x10000>;
		console-size = <0x40000>;
		pmsg-size = <0x10000>;
	};
```

`record-size = 0x10000` выбран так, чтобы область делилась без остатка:
0xe0000 − 0x40000 (console) − 0x10000 (pmsg) = 0x90000 = 9 × 0x10000
(в `fs/pstore/ram.c` число записей = `mem_sz / record_size`, остаток не
используется).

Отдельно, `W=1` + `-Wnode_name_chars_strict`:

```console
$ make … W=1 mediatek/mt6771-fplus-t1100.dtb \
       DTC_FLAGS="-Wnode_name_chars_strict -Wunit_address_vs_reg -Wsimple_bus_reg
                  -Wavoid_unnecessary_addr_size"
… Warning (node_name_chars_strict): /soc/i2c@11007000/himax_touch@48: Character '_' …
… Warning (node_name_chars_strict): /reserved-memory/ram_console@54400000: Character '_' …
```

Только эти два предупреждения (имена намеренно оставлены как в стоке); в
штатной сборке (`make dtbs`) их нет.

### 4.8. Патчи

```console
$ cd linux-t1100
$ git format-patch -2 --output-directory ../t1100-ubuntu/patches \
      --numbered --no-signature --subject-prefix="PATCH t1100"
patches/0001-arm64-dts-mediatek-add-minimal-MT6771-SoC-descriptio.patch  (9166 B)
patches/0002-arm64-dts-add-Fplus-T1100-MT6771-board.patch              (4332 B)
```

Применяемость проверена обратным наложением на текущее дерево
(`git apply --check -R` по каждому — OK). Порядок — в `patches/series`.

### 4.9. Спорное / требует решения

**4.9.1. PSCI есть — посылка задания неверна.** В stock DTS узел
`/psci { compatible = "arm,psci-1.0"; method = "smc"; }` присутствует
(строки 209–213), у всех CPU `enable-method = "psci"`, есть `idle-states` с
`arm,psci-suspend-param`. В `refs/device/dmesg-stock.txt.gz`:

```
psci: probing for conduit method from DT.
psci: PSCIv1.0 detected in firmware.
psci: Using standard PSCI v0.2 function IDs
```

То есть ATF отдаёт PSCI 1.0 наружу, и сток грузит 8 CPU
(`smp: Bringing up secondary CPUs ...`, sched-energy по CPU0…CPU7).
Следствие: на первом шаге PSCI всё равно **не добавлял** (как велено), но это
искусственное ограничение — второй патч с `/psci` + `enable-method` можно
делать сразу и убрать `maxcpus=1`.

**4.9.2. GIC — v3, но с оговорками.** `#interrupt-cells = <3>` как в стоке;
`ppi-partitions` (нужны mt8183-драйверам для CPU-thermal/PMU-разделения по
кластерам) не добавлял — это потребует `#interrupt-cells = <4>`. Третье окно
`reg` стокового GIC-узла (`0x0c530a80`+0x50) в GIC **не** переносил: это
регистр полярности, он описан узлом `sysirq` (в стоке он дублируется в обоих
узлах). Стоковый GIC-узел также не содержит GICC/GICH/GICV (в отличие от
mt8183) — для GICv3 Linux они не нужны.

**4.9.3. IRQ uart0: 286 — это Linux virq, а не номер для DT.** В `dmesg`
стока `11002000.serial: ttyS0 at MMIO 0x11002000 (irq = 286 …)`, но в DT
(и в нашем dtsi) правильное значение — **`GIC_SPI 91`** (stock `0x5b`), потому
что sysirq передаёт hwirq в GIC без смещения (см. 4.2, сверка на msdc/i2c).
Вариант «286 → SPI 254» был бы неверен. Если бы взяли 254, консоль просто не
получала бы прерываний.

**4.9.4. earlycon и клоки UART.** `earlycon=mt6577,…` не сработает: в mainline
ранний консольный драйвер зарегистрирован как `mtk8250`
(`OF_EARLYCON_DECLARE(mtk8250, "mediatek,mt6577-uart", …)`), а `mt6577` — имя
platform-драйвера, не ранней консоли. В bootargs стоит
`earlycon=mtk8250,0x11002000` (форма `<name>,0x<addr>` поддержана
`parse_options()`). Клоков UART в DT только один (`clk26m`), без `clock-names`:
`8250_mtk.c` в этом случае идёт по «одноклоковой» ветке и даёт
`base_baud = 1625000` — ровно как в dmesg стока. Гейт `CLK_INFRA_UART0`
появится вместе с `clk-mt6771`; до этого UART работает на том, что оставил LK.
**Риск**: если шинный клок UART окажется выключен, запись в `console=ttyS0`
может подвесить загрузку. План B на первую загрузку — bootargs без
`console=ttyS0` (логи всё равно уйдут в `ramoops`).

**4.9.5. `reserved-memory`: `framebuffer` и `items-reserved` НЕ пересекаются**
(поправка 29.10.2026 — раньше здесь была ошибка в арифметике).
`framebuffer` = `0x7cd80000` + `0x2e80000` = `0x7fb80000` (конец), а
`items-reserved` начинается с `0x7fc00000`, то есть между ними зазор `0x80000`;
оба региона вырезаны из System RAM в стоковом `/proc/iomem`. Вывод не
меняется: при разборе дисплея уточнить, что из этого реально занято, и,
возможно, выкинуть `items-reserved` (а также `framebuffer` и `vpu-binary`).
Плюс: `md-mem-usage` 256 МиБ перенесён «на всякий случай», хотя в стоковом
`/proc/iomem` эта область показана как System RAM (модем в нашем ядре не
стартует). Если RAM понадобится — первым можно убрать его и `vpu-binary`.

**4.9.6. Имя панели в живом FDT не совпадает с `docs/STATUS.md`.**
`atag,videolfb-lcmname = "es6311_anx6585_zigzag_wxga"` и
`odm/panel@0 { compatible = "es,es6311_anx6585_zigzag_wxga"; status = "disabled"; }`,
тогда как в STATUS панель определена как BOE **TV110XUM-LB0-1SP0** (LCM-драйвер
`tv110xum_lb2_incell`). Строка в `atag` может быть дефолтом LK/чужого оверлея.
В наш DTS узел панели не включал — это вопрос к `kernel-drm`.

**4.9.7. Заглушка `pio`.** Узел `pinctrl@10005000` с
`compatible = "mediatek,mt6771-pinctrl"` в mainline ничем не биндится
(драйвера нет) — он нужен только чтобы резолвились `<&pio N>` в board-узлах.
`#interrupt-cells = <4>` — вендорная схема; в mainline `pinctrl-mt6771` будет
`<2>` (`pin, type`), тогда же обновятся `interrupts` у тача и добавится полный
список `iocfg`-баз (0x11f20000/0x11e80000/0x11e70000/0x11e90000/0x11d30000/
0x11d20000/0x11c50000/0x11f30000).

**4.9.8. `i2c0` без клоков.** `i2c-mt65xx` требует оба клока
(`main` и `dma`) — без них узел не соберётся, поэтому он `disabled` и без
`clocks`. Включим вместе с `clk-mt6771` и драйвером тача.

### 4.10. Что НЕ делалось (и почему)

- **`psci`, `enable-method`, `cpu-map`, `idle-states`, OPP/cpufreq** — по
  заданию первый шаг без PSCI (см. 4.9.1: технически PSCI есть).
- **`mmsys`/`disp`/`dsi`/`mali`/`smi`/`iommu`** — сознательно не включал:
  без `clk-mt6771`, power-domains и `mmsys`-маршрутов узлы бесполезны, а
  «пустые» узлы с придуманными `interconnects`/клоками противоречат правилу
  «регистры из исходников». Их делают `kernel-drm`/`gpu-mesa` поверх уже
  готового dtsi (адреса: DISPSYS `0x14000000`, GPU `0x13040000`, IRQ GPU
  278/279/280, SMI larb 0/1/2/3/4/5/6 — см. `refs/stock-mt6771.dts`).
- **`clk-mt6771`, pinctrl, regulator (MT6358)** — следующий шаг, отдельные
  патчи.
- **eMMC/mmc-узел** — нет клоков/пинконтроля, критерий «eMMC виден» решается
  после `clk-mt6771`.
- **Полный `Image` не пересобирал** — менялись только DTS; `Image` в
  `build/t1100` остался от baseline (`2a2cab58…`).
- Планшет не трогался; `docs/STATUS.md`, `docs/hardware.md`,
  `docs/research.md`, `docs/boot-test.md`, `scripts/*` не изменялись.

## 5. 29.10.2026 — среда восстановлена, DTS+1, найден WIP-порт

Работа велась на другом хосте (`/home/l`), и на текущей машине не было ни
дерева, ни тулчейна. Восстановлено:

| Компонент | Значение |
|---|---|
| Ядро | `/home/leo/Aurora_All/device/linux-t1100`, 6.12.114, tarball sha256 `7a858991…4af3`, git-репозиторий с базовым коммитом |
| Патчи | 0001, 0002 применились чисто (`git am`) |
| Тулчейн | Arm GNU Toolchain 14.2.Rel1 (`aarch64-none-linux-gnu-`), распакован в `../toolchains/` |
| Регресс DTB | `mt6771-fplus-t1100.dtb` 4806 B, sha256 `bbf097af…d8b5e` — **совпал** со старым |
| Хост-пакеты | `make`, `gcc`, `bc`, `flex`, `bison`, `openssl` (dev), `dtc` 1.7.2; `sudo` без пароля нет — тулчейн взят тарболлом |

Исправлено в репозитории:

- `scripts/build_kernel.sh`: дефолт `KERNEL_SRC=../linux-t1100`, автопоиск
  `CROSS_COMPILE` в `PATH` и `../toolchains/*/bin`, применение
  `configs/t1100.fragment` через `merge_config.sh`, `JOBS=nproc`.
- `scripts/repack_boot.py` / `bootimg_extract.py`: `dtb_addr` читался как
  `<IQ` с 0x670 (получался 0) — в MTK-раскладке это `<I` по 0x674 =
  `0x54000000`.
- `scripts/repack_boot.py`: хвост стокового образа больше не затирается
  нулями — round-trip всего 32-МиБ `boot_a` теперь **побайтово идентичен**
  (раньше совпадали только полезные 14,9 МБ).
- `scripts/make_test_boot.sh`: кандидаты REF (в т.ч. `../1100/boot_a.bin`).

Новые факты:

- Панель идёт **через мост ITE IT6112**, init-последовательность есть в
  публичном WIP-драйвере (`refs/it6112/`) — RE не требуется.
- В `linux-mediatek/linux` есть ветка `adomerle/mt6771-next` (base 6.16.0) с
  полным DTS нашего планшета; `mt6771.dtsi` там = `#include "mt8183.dtsi"`,
  отдельных clk/pinctrl/mmsys для MT6771 нет → гипотеза «MT8183-драйверы
  подходят» усилена (`refs/mt6771-next/`).
- Патч 0003: PSCI + `mediatek,mt8183-wdt`, из bootargs убраны
  `console`/`earlycon`/`stdout-path` (UART-гейт до `clk-mt6771` закрыт).

## 6. 29.10.2026 — SoC-DTS на базе `mt8183.dtsi`, полный конфиг, сборка «реального» ядра

Задача шага: получить не минимальный DTS, а дерево, на котором заводятся
настоящие драйверы (клоки, pinctrl, PMIC, eMMC, USB, IOMMU, DRM, GPU), чтобы
следующим шагом поднимать rootfs. Планшет не трогался (никаких прошивок).

### 6.1. Что переиспользовано из `refs/mt6771-next` (WIP-порт того же изделия)

| Что | Как |
|---|---|
| `mt6771.dtsi` = `#include "mt8183.dtsi"` + `compatible = "mediatek,mt6771"` | взято целиком как идея и структура |
| Удаление cpufreq/cpuidle у CPU (`cpu-idle-states`, `operating-points-v2`, `idle-states`) | взято (с обоснованием: `mediatek-cpufreq` не знает MT6771) |
| `/delete-node/ &scp` | взято; в 6.12 у MT8183 нет `vcodec_enc`, поэтому удаляется только `vcodec_dec` |
| `&mmc0` (HS400, `hs400-ds-delay = <0x12814>`, VEMC/VIO18, `MSDCPLL_CK`) и `&mmc1` (SD, `cd-gpios = <&pio 3>`, VMCH/VMC) | взято |
| `&ssusb` (peripheral, USB2-only, `mediatek,u3p-dis-msk = <1>`, `vusb33-supply`), `&usb_host`, `&u2port0 { mediatek,pre-emphasis = <3>; }` | взято |
| Питание: `reg_vsys`, `i2c_vbus`, `panel_dvdd` (GPIO55), весь блок `vsys-*`/`vs1-*`/`vs2-*-supply` у `&mt6358regulator`, coupler VGPU/VSRAM_GPU, `&mt6358_vdram2_reg` always-on | взято |
| `backlight` (pwm-backlight, `&pwm0 0 500000`, enable GPIO56, 1023 уровня, 576 по умолчанию) | взято, но `status = "disabled"` до появления драйвера панели |
| `panel@56` на `i2c3` (`boe,tv110xum-lb2-it6112`, reset GPIO45, dvdd/panel_dvdd, vpos/vneg от MT6370), `dsi_out <-> panel_in` | взято, `status = "disabled"` |
| `pmic@34` MT6370 на `i2c5`: `adc` + `regulators { dsvbst, dsvpos, dsvneg, vibldo }` | взято только это (зарядник/TCPC/LED выброшены) |
| `gpio-keys` Volume Down на `&pio 93`, `&mt6358keys` (Volume Up, `power-off-time-sec = <10>`) | взято |
| `&gpu { mali-supply = <&mt6358_vgpu_reg>; }`, `&mfg { domain-supply = ... }` | взято |
| `battery` (simple-battery, 8 Ач, 4.35 В) | взято (для будущего зарядника) |
| `chassis-type = "tablet"` | взято |

### 6.2. Что пришлось менять под 6.12 (и почему)

| Пункт | В референсе (6.16/linux-next) | У нас (6.12.114) | Причина |
|---|---|---|---|
| `/chosen` | `&chosen { ... }` | узел `chosen` внутри `/` в board DTS | в 6.12 у `mt8183.dtsi` **нет** метки/узла `chosen`: `&chosen` → «Label or path chosen not found» |
| `simple-framebuffer` | `chosen/framebuffer@7cb80000` + `DRM_SIMPLEDRM` | удалён | требование задачи: экран отдаётся настоящему DRM; `DRM_SIMPLEDRM` выключен |
| `&iommu` | `status = "disabled"` («ломает simple-framebuffer») | **включён** | simple-framebuffer-а больше нет; адрес и IRQ m4u совпадают со стоком (0x10205000, SPI 166) |
| `vcodec_enc` | `/delete-node/ &vcodec_enc` | нет такого узла в 6.12 | в 6.12 у MT8183 только `vcodec_dec` |
| Регистрация тача | reset `GPIO0` | reset `GPIO158` | стоковый pinctrl (`rstoutput0` → `pinmux = <0x9e00>`) и `odm/lcm.ts-rst-gpios = <55 45 44 56 175…158>`: reset тача — **158**, а не 0 |
| Тач, совместимость | `himax,hx83102e` + патч в `himax_hx83112b.c` | оставлен `himax,hx83102e` без драйвера | в 6.12 драйвер знает только `hx83100a/hx83112b`; правка — одна строка (патч есть в референсе), но это код драйвера, а не DTS |
| `pinctrl-0/1` у MMC | `mmc0_pins_default/uhs`, `mmc1_pins_default` | **не задаются** | таблица `PINMUX_GPIO122..133` для MSDC0 в `mt8183-pinfunc.h` не сверена с MT6771; LK уже сконфигурировал пады, чтобы отдать нам ядро с eMMC. Перемуксировать рабочий eMMC в непроверенную функцию = потерять rootfs |
| HDMI (IT66121 + `&dpi0`) | полный путь + `dpi_func_pins`/`dpi_idle_pins` | не описан (`dpi0` остаётся `disabled` из `mt8183.dtsi`) | `ite,it66121` в 6.12 есть, но путь DPI→HDMI не входит в критерий, а pinmux DBPI (GPIO13..28) тоже непроверен |
| MT6370 | полный sub-PMIC (charger, TCPC, LED, flashlight) | только DSV-регуляторы, `status = "disabled"` | TCPC перетягивает роль USB-порта, которая нужна для RNDIS; зарядка не нужна для userspace |
| `sgm41513` (i2c6) | `status = "disabled"` | так же | драйвера нет |
| `sound` (ES7210) | `mediatek,mt8183-mt6358-es7210` | нет | звук — не-цель v1, драйвера ES7210 в 6.12 нет |
| `&systimer` | наследуется | `status = "disabled"` | MT6771 GPT @0x10017000 поднимает **SPI 202** (сток: `sys_timer@10017000, interrupts = <0 0xca 4>`), а `mt8183.dtsi` — 200 |
| `&svs` | наследуется | `status = "disabled"` | пишет DVFS/PMIC по efuse-калибровке, layout MT6771 неизвестен (нет TRM) |
| `&cci` | `&cci { proc-supply = ... }` | `status = "disabled"` | cpufreq нет, а CCI-devfreq с MT8183 clock-ID — непроверенная запись в клоки |
| `gpio-ranges` | 192 пина | 191 | сток: `gpio-ranges = <&pio 0 0 0xbf>` |
| bootargs | не задаёт | `console=tty0 maxcpus=1 panic=10 loglevel=7` + геометрия ramoops | добавлены `ramoops.mem_address=0x54410000 mem_size=0xe0000 record_size=0x10000 console_size=0x40000 pmsg_size=0x10000` (ровно как в стоковом `cmdline.txt`): у нашего ядра до сих пор **не было** канала логов |
| `DTC_FLAGS` | — | `-Wno-gpios_property` для этого DTB | `__symbols__/gpio` (метка нужна вендорскому dtbo) ложно трактуется dtc как GPIO-спектификатор |

### 6.3. Итоговый состав DTS

`arch/arm64/boot/dts/mediatek/mt6771.dtsi` (148 строк) =
`#include "mt8183.dtsi"` + `compatible` + правки из таблицы 6.2 (все они
перечислены и в комментариях самого файла, с проверенными адресами).

`arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dts` (454 строки): board-факты
(LCM GPIO 45/55/44/56/175, тач EINT 1 / reset 158 / vdd VLDO28, backlight PWM0 +
GPIO56, PMIC EINT 182, клавиши, батарея), `chosen` с bootargs и ramoops,
`memory@40000000` 4 GiB, `reserved-memory` **без детей**, и последним —
`#include "mt6771-fplus-t1100-lk-compat.dtsi"`.

Узлы, которые теперь есть в DTB (готовы к драйверам): `mmsys`, `ovl0`,
`ovl_2l0/1`, `rdma0/1`, `color0`, `ccorr0`, `aal0`, `gamma0`, `dither0`,
`dsi0`, `dpi0`, `mutex`, `larb0`, `smi_common`, `iommu`, `mipi_tx0`,
`gpu` (panfrost), `topckgen`, `infracfg`, `pericfg`, `apmixedsys`, `mfgcfg`,
`scpsys` + power domains, `pio`, `pwrap`, `watchdog`, `i2c0..11`, `mmc0/1`,
`ssusb`/`usb_host`/`u3phy`, `pwm0/1`, `auxadc`, `thermal`.

### 6.4. Что НЕ заведётся без доработки (факты, не догадки)

1. **Дисплей.** `dsi0` и `panel@56` остаются `disabled`: драйвера панели
   IT6112 `boe,tv110xum-lb2-it6112` в 6.12 нет (WIP-патч —
   `refs/mt6771-next/patches/083d4e7fa2`, `refs/it6112/`). Без него DSI
   повиснет в `-EPROBE_DEFER`, а без `simple-framebuffer` консоли на экране не
   будет вообще - поэтому включать имеет смысл только вместе с драйвером.
2. **Тач.** `himax,hx83102e` — в 6.12 нет; нужна одна строка в
   `himax_hx83112b.c` + `vdd-supply` (патчи `0f649f913f`, `41dd7e6871`).
3. **USB host / роли.** 6.12 не умеет role-switch в `phy-mtk-tphy`
   (патч `96fe48bed8`); у нас `dr_mode = "peripheral"` — годится для RNDIS.
4. **HDMI.** `dpi0` + `ite,it66121` — DPI-путь не описан (см. 6.2).
5. **Звук** — машины `mt8183-mt6358-*` и ES7210 в 6.12 нет.
6. **Wi-Fi.** В DTS не описан вообще: `wlan_drv_gen3` — out-of-tree драйвер
   MediaTek (SDIO), это отдельная задача `distro-userspace`.
7. **cpufreq/SMP.** `mediatek-cpufreq` не знает MT6771; `maxcpus=1` в
   bootargs. PSCI в дереве есть (из `mt8183.dtsi`), сток подтверждает
   `PSCIv1.0 detected in firmware`, но SMP на нашем ядре не проверялся.

### 6.5. Признанные риски «MT8183-драйверы на MT6771»

Это гипотеза, подтверждённая только чужим WIP-портом; на нашем железе не
проверялась. Что именно может не совпасть — по пунктам:

| Блок | Драйвер | Что может разойтись |
|---|---|---|
| `pwrap` (0x1000d000) | `mtk-pmic-wrap` c `pwrap_mt8183` | у MT6771 есть свой кандидат `mediatek,mt6765-pwrap`; без PMIC не заведутся eMMC (`vmmc/vqmmc`) и PMIC-клавиши |
| `scpsys` (0x10006000) | `mediatek,mt8183-power-controller` | индексы power-domain (`MT8183_POWER_DOMAIN_*`) должны совпадать с MT6771: от них зависят DISP/MFG и larb |
| `topckgen`/`infracfg`/`pericfg`/`apmixedsys`/`mfgcfg`/`mmsys` гейты | `clk-mt8183*` | соответствие gate-ID MT6771 неизвестно (downstream-таблица `clk-mt6771.c` не публична) |
| `pio` (0x10005000 + iocfg 0x11c5..0x11f3) | `pinctrl-mt8183` | таблица функций/пинов MT6771 (`pinctrl-mt6771.c`) может отличаться; поэтому пады MMC не перемуксируются (6.2) |
| `tphy` (0x11f40000) | `mediatek,mt8183-tphy` | downstream у MT6771 `mediatek,mt6771-phy` с другим набором регистров → USB может не подняться |
| `smi_common`/`larb*` | `mediatek,mt8183-smi-common` | адреса larb0..6 совпадают (сверено), но число портов larb на MT6771 может быть меньше |

Практический вывод: первый прогон должен показать в dmesg по порядку
`pwrap` → `mt6358-regulator` → `mmc0` (eMMC) → `usb` → `iommu/larb` → `gpu`.

### 6.6. Конфиг

`configs/t1100.fragment` переписан под «реальное» ядро, из него сгенерирован
`configs/t1100_defconfig` (`make savedefconfig`, 1695 строк). Проверено:
`cp configs/t1100_defconfig → .config && make olddefconfig` даёт **побайтово
тот же** `.config`, что и сборка из фрагмента (`diff` пуст).

Ключевое (всё `=y`, модулей нет — в initramfs их некому загружать):
`ARCH_MEDIATEK`, `COMMON_CLK_MT8183` (+ поддрайверы по умолчанию),
`PINCTRL_MT8183`, `MTK_SCPSYS`, `MTK_INFRACFG`, `MTK_PMIC_WRAP`,
`MFD_MT6397`, `REGULATOR_MT6358`, `RTC_DRV_MT6397`, `KEYBOARD_MTK_PMIC`,
`KEYBOARD_GPIO`, `MMC`+`MMC_MTK`+`MMC_BLOCK`+`EXT4_FS`, `I2C_MT65XX`+`I2C_CHARDEV`,
`SERIAL_8250_MT6577`, `MEDIATEK_WATCHDOG`, `MTK_IOMMU`, `MTK_SMI`,
`DRM_MEDIATEK`+`MTK_MMSYS`+`MTK_CMDQ`+`MTK_CMDQ_MBOX`+`PHY_MTK_MIPI_DSI`,
`DRM_PANFROST`, `PWM_MTK_DISP`, `BACKLIGHT_PWM`, `USB_MTU3`+`USB_XHCI_MTK`+
`PHY_MTK_TPHY`, `USB_GADGET`+`USB_CONFIGFS`+`USB_CONFIGFS_RNDIS`+
`USB_CONFIGFS_ECM`+`USB_F_RNDIS`+`USB_F_ECM`+`USB_U_ETHER`+`USB_USBNET`,
`PSTORE`+`PSTORE_RAM`+`PSTORE_CONSOLE`+`PSTORE_PMSG`, `BLK_DEV_INITRD`+`RD_GZIP`,
`DEVTMPFS`+`DEVTMPFS_MOUNT`, `ARM64_VA_BITS_39`, `DEBUG_INFO_NONE`,
`PANIC_TIMEOUT=10`.

Выключено осознанно: `MTK_SVS`, `ARM_MEDIATEK_CCI_DEVFREQ`, `DRM_SIMPLEDRM`.

### 6.6.1. Регресс патч-серии на чистом дереве

`patches/0001..0009` применяются на базовый коммит `728cd6e` (mainline
6.12.114) без конфликтов (`git am`, rc=0), и `make ... mediatek/mt6771-fplus-t1100.dtb`
в отдельном дереве `/home/l/projects/tmp/series-test` даёт **тот же DTB**:
sha256 `a0ef84b4df3fe2c905e8ea9bfab9d663114f7885782f6be9ded8da67f5d577a7`.
Значит серия самодостаточна и наш DTB воспроизводим.


## 7. 30.10.2026 — почему падал `mt6358-regulator`, почему «нет лога» и как это проверено

Состояние на входе: DTB с `regulator-coupled-with` грузится до userspace, но все
рельсы PMIC не регистрируются, и `mmc`/`usb`/`gpu`/`disp`/`iommu` навсегда в
`deferred probe`. DTB без coupling не даёт вообще никакого лога. Разобрано по
коду mainline 6.12.114 и по логу стокового 4.14 (`build/lk/last_kmsg_now.txt`).

### 7.1. Четыре независимых дефекта (все — в коде, не догадки)

**1. `regulator-coupled-with` убивает весь PMIC.**
Generic coupler принимает только `always-on`-регуляторы:
`drivers/regulator/core.c:5643` — `generic_coupler_attach()` возвращает
`-ENOTSUPP` при `!rdev->constraints->always_on`. `mt6358_regulator_probe()`
(`drivers/regulator/mt6358-regulator.c:713`) регистрирует рельсы в цикле и
**выходит на первой ошибке**. VGPU — шестая по счёту, поэтому итог: ни одного
регулятора MT6358 в системе. Дальше `devm_regulator_get()` у потребителей
получает `-EPROBE_DEFER` навсегда, отсюда весь список `deferred probe pending`.

**2. `power-domain@2` без `domain-supply` убивает весь `scpsys`.**
У MT8183 MFG_ASYNC и MFG помечены `MTK_SCPD_DOMAIN_SUPPLY`
(`drivers/pmdomain/mediatek/mt8183-pm-domains.h`), а с 6.12
`mtk-pm-domains.c` ищет регулятор **в самом узле домена**
(`scpsys_add_one_domain()`: `scpsys->dev->of_node = node;
devm_regulator_get(scpsys->dev, "domain")`). В нашем DTS `domain-supply` был
только у `&mfg` (домен 3), у `power-domain@2` (MFG_ASYNC) — нет, и
`scpsys_probe()` падает раньше `of_genpd_add_provider_onecell()`. Лог это
подтверждает дословно:

```
platform 10006000.syscon:power-controller: deferred probe pending:
  mtk-power-controller: /soc/syscon@10006000/power-controller/power-domain@2:
  failed to get power supply.
```

Следствие: провайдер power-доменов не появляется вообще, поэтому `mutex`,
`ovl`, `rdma`, `dsi`, `larb*`, `smi`, `pwm`, `mfgcfg` — все в deferred. Это и
есть причина, по которой дисплей/GPU «не готовы» даже теоретически.
`mt8183-kukui.dtsi` на том же MT6358 делает ровно то, чего не хватало:
`mfg_async → vsram_gpu`, `mfg → vgpu`.

**3. `mtk-ramconsole` не писал ни байта.**
Драйвер искал зону через `of_find_compatible_node(NULL, NULL, "ramoops")`, но
узла `ramoops` в нашем DTS нет — ramoops сконфигурирован параметрами
(в логе: `ramoops: using module parameters`, `ramoops: using 0xe0000@0x54410000`).
`mrcm_locate_zone()` выходил сразу, `nzones == 0`, `mrcm_init()` возвращал
`-ENODEV`. Работал только `mrcm_stop_wdt()` — поэтому зависание не превращалось
в reset-цикл, но и лога не давало.

**4. mainline выключает рельсы, которые вендорный драйвер запрещает выключать.**
`regulator_late_cleanup()` (`drivers/regulator/core.c:6381`, из
`late_initcall_sync`) гасит **любой** включённый регулятор без потребителя, если
он не `always-on`. Стоковый 4.14 сам себя страхует и пишет в лог:

```
mt6358_regulator_disable:VDRAM2 should not be disable.(use_count=0)
```

…и так для 16 рельсов: VDRAM1, VCORE, VPROC12, VS2, VMODEM, VS1, VDRAM2, VIO18,
VSRAM_OTHERS, VXO22, VAUX18, VBIF28, VSRAM_PROC12, VIO28, VA12, VAUD28. В
mainline-описании MT6358 `always-on` стоит только у 14 из них; **VDRAM2,
VBIF28, VAUX18, VIO28, VAUD28** никто не защищает. VDRAM2 — это рельс LPDDR4X
1.1 В, VBIF28 — bias интерфейса DRAM: выключение любого из них убивает SoC
раньше, чем успевает что-то напечатать, а вместе с ним и содержимое DRAM.

### 7.2. Почему «нет лога» ≠ «ядро не стартовало» — и что это значит

В рабочем прогоне (с coupling) в зоне pstore лежит лог начиная с
`[0.000000] Linux version 6.12.114-...`: ramoops регистрирует консоль с
`CON_PRINTBUFFER` на `postcore_initcall`, и printk **переигрывает весь
ring buffer**, поэтому в зоне оказывается весь лог с нулевой секунды (то же
самое делает переписанный `mrcm`). Значит:

* если в зоне нет ни строки нового прогона — ядро не выполнило ни одного
  `printk`, т.е. проблема до `start_kernel` (LK/образ), а не «драйвер повис»;
* если лог обрывается на какой-то строке — это и есть точка отказа.

Во втором варианте (без coupling) лог обрывался «нигде»: наиболее
правдоподобное объяснение — дефект 4: рельс выключается уже после
`late_initcall`, ядро умирает, а данные в DRAM (включая лог) теряются до того,
как плату перезагрузят. Проверяется одним прогоном: `regulator_ignore_unused`
в bootargs + `always-on` на перечисленных рельсах.

### 7.3. Что изменено

DTS (`mt6771-fplus-t1100.dts`):

* убрано `regulator-coupled-with` (патч 0010), вместо него у `&gpu`
  `mali-supply = <&mt6358_vgpu_reg>` + `sram-supply = <&mt6358_vsram_gpu_reg>`
  (panfrost сам включает sram перед VGPU — как в `refs/affenull-mt6771`);
* `&mfg_async { domain-supply = <&mt6358_vsram_gpu_reg>; }`, `&mfg` — VGPU
  (патч 0013), т.е. провайдер power-доменов теперь регистрируется;
* `always-on` для VDRAM2, VBIF28, VAUX18, VIO28, VAUD28 (патч 0013);
* включены обратно `&mmc0` (eMMC), `&mmc1`, `&ssusb` (`dr_mode = "peripheral"`,
  RNDIS-гаджет), `&usb_host`; `&gpu` осознанно остаётся `disabled`;
* bootargs (патч 0014, временно): `initcall_debug` — последняя строка лога
  называет initcall, который не вернулся; `regulator_ignore_unused` —
  не запускать `regulator_late_cleanup()`.

Драйвер (`drivers/soc/mediatek/mtk-ramconsole.c`, патчи 0011+0012):

* зона ищется (а) по узлу `ramoops`, если он появится, (б) по резервациям,
  которые создаёт сам LK (`mblock-N-pstore` в `/reserved-memory` живого DT),
  (в) по параметрам `ramoops.mem_address/mem_size/console_size/pmsg_size`;
* вместо постоянной консоли — снимки ring buffer'а в ту же зону:
  `register_console(CON_PRINTBUFFER)` → `pr_info` → `unregister_console()`,
  на `early_initcall` и `postcore_initcall_sync`. Второго писателя в зону нет,
  после второго снимка зоной владеет ramoops;
* TOPRGU стопорится по-прежнему первым делом.

Конфиг: `CONFIG_MTK_RAMCONSOLE=y` добавлен в `configs/t1100_defconfig`
(раньше он был только в `build/full/.config`, т.е. сборка из дефконфига его
теряла). Round-trip `defconfig → olddefconfig → savedefconfig` побайтово
совпадает.

### 7.4. Артефакты

```
build/full/arch/arm64/boot/Image            39670272  md5 db153cbb8baf43367aa90184c22e3b67
                                                      sha256 350a36e135f05bc0428293ee9f27e068981e10895dc4b3b177e78bb18228ea68
build/Image.pmic.gz                         14485775  md5 31e1a0082b626fbda7e76e6cb33473fc
build/full/.../mt6771-fplus-t1100.dtb          51871  md5 4fbe401d3b20540d92e891798dafaaad
                                                      sha256 61978c90a4e7d733950e4771de64bce29f0e3282c52923b178198a36f6c8fea4
build/boot_pmic1.img                        33554432  sha256 5893614c24e10f2e88ba12fadee4ee79d9fe99ba14df4263a6fdf94de1a3cc5d
```

Версия ядра: `6.12.114-g1379709143b7`. `build/boot_pmic1.img` собран
`scripts/make_test_boot.sh` из этого `Image`, DTB и `build/initramfs_net3.cpio.gz`
(kernel addr 0x40200000, cmdline скрипта по умолчанию).

Валидатор LK (`refs/pennyos-lk/check-lk-dtb.py` на `build/lk/dtbo_a.img` и
`build/lk/live.dts`): все 8 проверок `ok`, `RESULT: LK should accept this DTB`,
merged size 87147 байт.

Патч-серия: `0001..0014` применяются `git am` на базовый `728cd6e` без
конфликтов, и DTB, собранный из чистого дерева с этой серией, побайтово равен
рабочему (sha256 `61978c90…`).

### 7.5. Чего ждать на следующем прогоне

По порядку в логе (он теперь читается всегда):

1. `mrcm: zone 262144 bytes, wdt stopped: 1` и `mrcm: snapshot at
   early_initcall` — значит ранняя консоль работает; до этого сообщения
   покрыт весь диапазон от `[0.000000]`.
2. `mt6358-regulator mt6358-regulator: Chip ID = 0x5820` **без** строк
   `failed to register VGPU`.
3. `mt6358-regulator: ...` + `vdram2: disabling` **не должно быть** (при
   `regulator_ignore_unused` их и не будет).
4. `10006000.syscon:power-controller` больше не в списке deferred;
   `14016000.mutex`, `larb*`, `smi` — тоже.
5. `mmc0: ... SDHCI ...` / `mmcblk0: mmc0:...` — eMMC; `11201000.usb` →
   `mtu3` → UDC, затем RNDIS из initramfs (`usb0`).
6. Если вместо этого лог обрывается — строка обрыва и есть точка отказа
   (при `initcall_debug` видно, какой initcall не вернулся).
7. Если в зоне снова **нет ни строки** — виноват не драйвер: смотреть LK и
   загрузку образа (сравнить `build/lk/live.dts` и DTB, который реально ушёл
   в boot_a).

Что остаётся риском и проверяется только на железе: гейты `clk-mt8183` на
MT6771 (eMMC/USB могут не подняться из-за неверных gate-ID), `tphy`
(`mediatek,mt8183-tphy` против `mediatek,mt6771-phy`), и то, что
`mt8183-power-controller` действительно совместим с SPM MT6771.


## 8. 30.10.2026 — почему «нет ни одной строки»: `ioremap` по RAM, и лог в обход консоли

Вход: `boot_pmic2.img` (Image md5 `db153cbb…`, DTB md5 `4fbe401d…`, md5 образа
`fd96f69d…`) прошит; чёрный экран, сбросов нет, `/proc/last_kmsg` — старый лог
(289537 Б, uptime 3603, ядро `6.12.114-g97f79731b0d7`, т.е. содержимое зоны от
прошлого удачного прогона). Счётчик `mrcm` в логе — 0.

### 8.1. Корневая причина пустой зоны — в самом `mrcm`, а не в плате

`mrcm_locate()` брал зону через `ioremap(paddr, console_size)`. Зона ramoops
лежит в **system RAM**: LK её резервирует, но она остаётся в memory map, а
arm64 такие адреса мапить через `ioremap` запрещает:

```c
/* arch/arm64/mm/ioremap.c */
	/* Don't allow RAM to be mapped. */
	if (WARN_ON(pfn_is_map_memory(__phys_to_pfn(phys_addr))))
		return NULL;
```

Итог: `mrcm_base == NULL` → `pr_err("no ramoops console zone found")` →
`-ENODEV` → ни одного байта в зону. То есть «нет лога» здесь означало не
«ядро не дошло до раннего initcall», а «драйвер молча не нашёл зону»:
сообщение об этом уходило в printk-ring, который читать было нечем.

Вторая половина проблемы — сам механизм: запись делалась через
`register_console(CON_PRINTBUFFER)` + `pr_info()` + `unregister_console()`,
т.е. ровно тем путём, которым уже пользуется ramoops; если printk в этот
момент не переигрывает ring, в зоне не появляется ничего.

### 8.2. Что сделано (патчи 0015, 0016)

`drivers/soc/mediatek/mtk-ramconsole.c` переписан на прямую запись
`persistent_ram` (патч 0015):

* формат — `struct persistent_ram_buffer` из `fs/pstore/ram_core.c`:
  заголовок 12 байт (`sig = 0x43474244` "DBGC", `start`, `size`) + текстовое
  кольцо; `sig` совпадает с тем, что после `sig ^= PERSISTENT_RAM_SIG`
  ожидает `persistent_ram_post_init()` при `sig = 0` у console-зоны, поэтому
  ramoops позже видит «existing buffer» и **дописывает** в него, а не затирает;
* отображение — `memremap(paddr, len, MEMREMAP_WB)` (для валидной RAM это
  линейное отображение, `ioremap` больше не используется), fallback —
  `ioremap` только если зона не в RAM; после каждой порции текста —
  `dcache_clean_poc()`, иначе при мгновенной смерти SoC в DRAM остаётся
  только то, что успело вымыться само;
* геометрия — только из `ramoops.mem_address/mem_size/console_size/
  pmsg_size/ftrace_size` в `boot_command_line`; узел `ramoops`/`mblock-*` в DT
  не ищется вообще. Нет параметров — жёсткий fallback
  `0x54410000`/`0xe0000`/console `0x40000`/pmsg `0x10000`;
* смещение console-зоны считается как в `ramoops_probe()`:
  `size - console - pmsg - ftrace` (зона идёт после dmesg-записей, pmsg и
  ftrace);
* снимки ring buffer'а — `kmsg_dump_rewind()` + `kmsg_dump_get_line()`
  (хронологически, без регистрации консоли) в четырёх точках:
  `early_initcall` (самый ранний initcall: до SMP и до любых драйверов),
  `postcore_initcall_sync`, `arch_initcall`, `late_initcall_sync`. Каждый
  снимок переписывает кольцо заново и начинается строкой
  `T1100LOG mrcm: stage=…`, так что уже сам факт этой строки в
  `/proc/last_kmsg` доказывает, что чёрный ящик отработал;
* стоп TOPRGU в `head.S` и в драйвере сохранён.

`drivers/regulator/mt6358-regulator.c` (патч 0016): `mt6358_regulator_probe()`
больше не выходит на первой ошибке — печатает `failed to register <rail>:
<err>, continuing`, считает и идёт дальше; в конце
`"%d of %d regulators registered, %d failed"`; `-ENODEV` только если не
зарегистрировался ни один. `mt6358_sync_vcn33_setting()` (Wi-Fi/BT LDO) тоже
стал нефатальным (`dev_warn`). Так один негодный рельс не уносит остальные
~40 и не оставляет eMMC/USB/дисплей в вечном `-EPROBE_DEFER`, а виновник
попадает в лог по имени.

DTS не менялся: `always-on` для VDRAM2/VBIF28/VAUX18/VIO28/VAUD28 и
`regulator_ignore_unused` из патчей 0013/0014 на месте.

### 8.3. Артефакты

```
build/full/arch/arm64/boot/Image
  39670272  md5 64d4fec7114f75c03c510cef9599f4ac
            sha256 eb587132f6fdbf1aa10a32d56ce1602239d862e207c3db664bca4d6c13378b03
  Linux version 6.12.114-g5f13fc14c7fc   (0 warnings)
build/full/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
  51871     md5 4fbe401d3b20540d92e891798dafaaad
            sha256 61978c90a4e7d733950e4771de64bce29f0e3282c52923b178198a36f6c8fea4
build/boot_pmic3.img                       33554432
            md5 dc99e2b61942c4d63c64ad168d811737
            sha256 6ffc7484fa4f85db73b90cdc038dea22fb457ac9638bb2eacd0641f3cfec515e
```

Образ собран `scripts/make_test_boot.sh` из этого `Image` (kernel addr
`0x40080000`, ramdisk addr `0x55000000`, tags `0x54000000`, page 2048), DTB `61978c90…`, initramfs `build/initramfs_net3.cpio.gz`; cmdline
в заголовке — побайтово как у `boot_pmic2.img`
(`bootopt=64S3,32N2,64N2 console=tty0 maxcpus=8 panic=10 … loglevel=7`).
Проверено извлечением из готового образа: kernel → `Image` (md5 совпадает),
dtb → `61978c90…`, ramdisk → `initramfs_net3.cpio.gz`.

Валидатор LK (`refs/pennyos-lk/check-lk-dtb.py`, `build/lk/dtbo_a.img`,
`build/lk/live.dts`): 9/9 `ok`, `RESULT: LK should accept this DTB`,
merged size 87147.

Патч-серия: `0001..0016` применяется `git am` на базовый `728cd6e` без
конфликтов (rc=0), файлы после применения побайтово равны рабочим; последние
два патча трогают только `drivers/`, поэтому DTB не меняется (`61978c90…`).

### 8.4. Что должно быть видно в `/proc/last_kmsg`

1. в начале зоны — строка последнего отработавшего снимка, например
   `T1100LOG mrcm: stage=late_initcall_sync done=early_initcall,
   postcore_initcall_sync,arch_initcall,late_initcall_sync, zone=0x5441... map=wb
   uptime_ms=…`; `done` перечисляет **все** пройденные этапы (каждый снимок
   переписывает кольцо заново, поэтому список этапов переносится в самой
   строке). Нет даже `T1100LOG` — значит не отработал и `early_initcall`;
2. далее весь printk-ring с `[0.000000] Linux version 6.12.114-gf9f8035fa…`,
   затем `mrcm: zone 0x…+0x40000, wdt stopped: …`;
3. чем короче `done`, тем раньше умерло ядро: `early_initcall` = смерть до
   SMP/драйверов, `postcore`+`arch` = где-то в начале `do_initcalls`,
   все четыре = смерть на драйверах (там уже должен быть виден виновник);
4. `mt6358-regulator … Chip ID = 0x5820` и, если какой-то рельс не регистрируется,
   `failed to register <имя>: <errno>, continuing` + итоговая
   `N of M regulators registered, K failed` — вместо прежнего обрыва на
   первой ошибке;
5. при `initcall_debug` (он в DT bootargs) последняя строка перед смертью —
   имя initcall'а, который не вернулся.

Если зона снова окажется нетронутой (нет даже `T1100LOG`), то это уже не
драйвер: значит ядро не дожило до `early_initcall`, и смотреть надо
`setup_arch`/`memremap`-путь и сам образ.

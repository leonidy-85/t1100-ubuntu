# SPEC — T1100 / Linux 7.3.6

Статус: active. Дата: 25.11.2026.
Репозиторий: `t1100-ubuntu` (GitFlic `py6on/t1100-ubuntu`).
Область: перенос и развитие mainline-ядра 7.3.6 на Fplus T1100 (MT6771),
запуск ALT Linux 2026.11 + Phosh, вендорский Wi-Fi/BT MT6631 и публикация
наработок. История 6.12 — в `docs/STATUS.md`, здесь не дублируется.

## §G Goal

Одна воспроизводимая ветка Linux 7.3.6 для T1100:

- ядро собирается из чистого `linux-7.3.6.tar.xz` + патчи проекта;
- грузится в ALT Linux 2026.11 на p54, работает Phosh;
- работают дисплей/тач/GPU/звук/батарея/датчики/HDMI/vcodec/zram;
- вендорский MT6631 даёт `wlan0` и BT;
- все изменения лежат патчами в `t1100-ubuntu` и доступны на GitFlic.

## §C Constraints

| id | constraint |
|----|------------|
| C1 | Не прошивать подключённый планшет без явной команды пользователя. Сейчас подключён другой планшет — не трогать. |
| C2 | База ядра — ровно `linux-7.3.6.tar.xz`, sha256 `8183d475a76a0faffa92d6cd500af421f589dfd0300a0f1060bb875e11d45723`. |
| C3 | Конфиг ядра — только через `scripts/build_kernel.sh` (`--defconfig`). Голый `merge_config.sh` запрещён: он роняет `CONFIG_ARCH_MEDIATEK`. |
| C4 | Вендорский Wi-Fi — только публичные GPL-исходники Motorola Pie-9 + Rabbit BTIF. Проприетарные бинарники в репозиторий не кладём. |
| C5 | GitFlic: пакет/коммит по умолчанию 100 МБ. Полную git-историю ядра не пушим; канон — серия патчей. |
| C6 | Vermagic модулей обязан совпадать с `uname -r`. `LOCALVERSION` не менять произвольно. |
| C7 | p54 — рабочий rootfs ALT; не переформатировать и не затирать пользовательские данные. |
| C8 | Не делать `rmmod` загруженного Wi-Fi-стека на текущем образе: зависание и watchdog-reboot. |
| C9 | Диагностика — SSH, pstore и expdb p3. UART нет. |
| C10 | Полный архив ядра >100 МБ в один файл GitFlic не влезает; публиковать патчи или части <100 МБ. |

## §I Interfaces

| id | surface | path / value |
|----|---------|--------------|
| I.kernel | дерево ядра | `../linux-t1100-7.3`, branch `master`, 71 коммит поверх `aeab2d3f0` |
| I.project | проект | `t1100-ubuntu`, remote `git@gitflic.ru:py6on/t1100-ubuntu.git` |
| I.build | сборка | `KERNEL_SRC=../linux-t1100-7.3 OUT=../build/t1100-7.3 scripts/build_kernel.sh` |
| I.toolchain | компилятор | `../toolchains/arm-gnu-toolchain-14.2.rel1-.../bin/aarch64-none-linux-gnu-` |
| I.boot | boot_a | `/dev/mmcblk0p29`, 32 МиБ, образ из `make_test_boot.sh` |
| I.cmdline | загрузка | `console=tty0 root=/dev/mmcblk0p54 rootwait rw maxcpus=8 panic=0 loglevel=7 ignore_loglevel initcall_debug regulator_ignore_unused clk_ignore_unused` + `pstore.backend=ramoops ramoops.mem_address=0x54410000 ramoops.mem_size=0xe0000 ramoops.record_size=0x10000 ramoops.console_size=0x40000 ramoops.pmsg_size=0x10000` |
| I.device | доступ | SSH `root@10.42.66.66`, UDC `11201000.usb`, RNDIS `1d6b:0104` |
| I.modules | модули | `/lib/modules/7.3.6-wifi1+/`; Wi-Fi в `updates/wifi/` |
| I.firmware | firmware | `/lib/firmware/WIFI_RAM_CODE_6759` и WMT/BT blobs |
| I.wifi | вендор | `wifi-src/{common,wlan-gen3}`, `btif-src`, work trees `/tmp/opencode/{wifi-work,btif-work}` |
| I.publish | публикация | `patches/kernel-7.3/`, `patches/wifi-7.3/`, `docs/`, `configs/`, `scripts/` |

## §V Invariants

| id | invariant |
|----|-----------|
| V1 | Boot-образ: `KERNEL_ADDR=0x40200000`, initramfs, `maxcpus=8`, `root=/dev/mmcblk0p54`; без этого 7.3 зависает до userspace. |
| V2 | `mt6370_otg_vbus: usb-otg-vbus-regulator` лежит **внутри** узла `charger`, иначе mtu3 не получает vbus и UDC не появляется. |
| V3 | В `mt6771.dtsi` для T1100 остаются `scp`, `vcodec_dec`, `vcodec_enc`; T800 удаляет их локально. |
| V4 | После конфигурации `CONFIG_ARCH_MEDIATEK=y`; все зависимые MTK-драйверы включены. |
| V5 | `CONFIG_SOUND=y` (не `m`), `SND_SOC_MT8183=y`, `SND_SOC_MT6358=y`, `SND_SOC_MT6771_MT6358=y`, `CONFIG_MTK_RAMCONSOLE=y`, `CONFIG_ZRAM=m` + `lzo-rle`. |
| V6 | `vermagic` каждого модуля равен `uname -r`; установка только в `/lib/modules/$(uname -r)/`. |
| V7 | Порядок загрузки Wi-Fi: `mtk_btif_drv` → `wmt_drv` → `wlan_drv_gen3`; `rmmod` стека запрещён. |
| V8 | Публикация в GitFlic — пакетами <100 МБ; изменения ядра — патчами, не полной историей. |
| V9 | Никакой прошивки без явного разрешения пользователя. |
| V10 | В DTS нет своего ramoops на `0x70000000`; pstore — в вендорском окне `0x54410000` через cmdline. |
| V11 | `kalFirmwareOpen()` обязан искать RAM code в `/lib/firmware/` независимо от `CONFIG_ANDROID`. |

## §T Tasks

| id | task | cites | status |
|----|------|-------|--------|
| T1 | Перенести 71 патч проекта на чистый 7.3.6 | C2 | x |
| T2 | Собрать `Image`, DTB и модули без ошибок | V4,V5 | x |
| T3 | Загрузить 7.3.6 в ALT 2026.11 + Phosh, проверить SSH/UDC | V1,V2 | x |
| T4 | Опубликовать серию ядра и Wi-Fi 7.3 на GitFlic | V8 | x |
| T5 | Исправить поиск `/lib/firmware/` в `kalFirmwareOpen()`, пересобрать `wlan_drv_gen3.ko` | V11 | . |
| T6 | Получить `wlan0`, проверить scan/connect | V7,V11 | . |
| T7 | Довести BT MT6631 (func_on, HCI, скан) | V7 | . |
| T8 | Опубликовать source-only архив <100 МБ или части + сборщик | C5,C10 | . |
| T9 | Синхронизировать `docs/STATUS.md`, `docs/TASKS.md`, `patches/series` | V8 | . |
| T10 | Проверить IOMMU/Himax на production-cmdline без `initcall_debug` | V1 | . |
| T11 | Проверить, что `t1100-wifi.service` не делает `rmmod` и не вешает плату | V7 | . |

## §B Bugs / backprop

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-11-25 | `usb-otg-vbus-regulator` был соседом `charger`, regulator of_node = NULL → mtu3 `-EPROBE_DEFER` | V2; узел перенесён внутрь `charger`, `0aedddd0d` |
| B2 | 2026-11-25 | голый `merge_config.sh` сбросил `CONFIG_ARCH_MEDIATEK` и MTK-драйверы | V4; только `build_kernel.sh --defconfig` |
| B3 | 2026-11-25 | `maxcpus=1` без initramfs → раннее зависание, WDT reset | V1; `maxcpus=8` + initramfs + `regulator_ignore_unused`/`clk_ignore_unused` |
| B4 | 2026-11-25 | DAPM context стал opaque в 7.3, `w->dapm->card` не компилируется | `snd_soc_dapm_to_card()`; `9929af68a` |
| B5 | 2026-11-25 | GitFlic отклонил pack ядра 285 МиБ: лимит 100 МиБ | V8; серия патчей `cae28ee`, Wi-Fi `ee5d653` |
| B6 | 2026-11-25 | `rmmod` Wi-Fi-стека повесил плату в watchdog | V7; не выгружать стек |
| B7 | 2026-11-25 | `kalFirmwareOpen()` не ищет `/lib/firmware/` при `CONFIG_ANDROID` | V11; задача T5 |

## §R Research

| id | fact | source |
|----|------|--------|
| R1 | GitFlic: `gitflic.defaultPackSize` по умолчанию 100MB; стандартный размер коммита 100 МБ; бесплатный репозиторий до 4 ГБ | docs.gitflic.ru (`application.properties`, Git LFS) |
| R2 | `linux-7.3.6.tar.xz` sha256 `8183d475…` | kernel.org `sha256sums.asc` |
| R3 | 7.3: `drm_panel_init()` не экспортируется, панели через `devm_drm_panel_alloc()`; `of_drm_get_panel_orientation()` → `drm_of_get_panel_orientation()` | upstream 7.3.6 `drm_panel.c`, `drm_of.h` |
| R4 | 7.3: AFE — child `audiosys` syscon, `COMP_PLATFORM` по имени больше не матчится; нужен `platforms->of_node` | upstream `mt8183.dtsi`, `mt8183-mt6358-*.c` |

## Definition of done

T5–T7 закрыты на живой плате без прошивки нового образа; `wlan0` и BT
работают после reboot; `systemctl is-system-running` без failed-юнитов
Wi-Fi/BT; T8–T10 закрыты; `SPEC.md`, патчи и документация запушены в
GitFlic; ни один планшет не прошит без явного разрешения.

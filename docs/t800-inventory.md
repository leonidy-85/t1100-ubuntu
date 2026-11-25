# T800: read-only инвентарь и gap-list для mainline/Ubuntu

Дата: 24.11.2026. Устройство: **Fplus T800**, `defaultuser@192.168.2.76`,
Aurora 5.2.1.210 (Khabarovsk). Устройство — рабочий эталон, снимались только
файлы `/proc`, `/sys` и списки `/vendor`; **ничего не прошивалось, rootfs не
выгружался, `/vendor` и boot не изменялись**.

Сырой инвентарь: `/tmp/opencode/t800-inventory/` (24 МБ, `SHA256SUMS`,
`live-t800.dts`, `device-tree.tar`, `dmesg.txt`, `config.gz`, `getprop.txt`,
дампы sysfs и списки `/vendor`). Живой DT в репозитории:
`refs/t800/live-t800.dts.gz` (34 КБ, `dtc -I fs` с `/proc/device-tree`).

## 1. Идентичность и ядро

| Параметр | Значение |
|---|---|
| платформа | `MT6771V/C`, `compatible = "mediatek,mt6771"` |
| продукт | `ro.product.model = O621PQ`, `ro.product.device = tb8788p1_64_bsp` |
| сборка | `alps/full_tb8788p1_64_bsp/...:11/RP1A.200720.011/...:user/release-keys` (Android 11 base, сборка 12.05.2026) |
| ядро | `Linux T800 4.14.186 #1 SMP PREEMPT Tue Nov 26 23:51:17 UTC 2024 aarch64` |
| RAM | 3 897 644 kB (~3.72 GiB), 8 CPU |
| eMMC | `mmc0:0001 A3A561`, 57.6 GiB, HS400, 56 разделов |
| UFS | контроллер `ufshci@11270000` в DT присутствует, но UFS-устройства и разделов нет — плата на eMMC |
| загрузка | `root=/dev/ram`, слот `_a`, `androidboot.dtb_idx=0`, `dtbo_idx=0` |
| boot state | `ro.boot.flash.locked=1`, `verifiedbootstate=green`, `veritymode=enforcing` |
| DRM | **нет** (`CONFIG_DRM` не задан, `/dev/dri` и `/sys/class/drm` отсутствуют), дисплей — legacy `mtkfb`/`/dev/fb0` |
| VDEC | vendor AP-side `/dev/Vcodec` (char 160:0), **не через SCP**; mainline VDEC/SCP не трогаем |

Ключевые `CONFIG` из `/proc/config.gz`: `CONFIG_MTK_FB=y`, `CONFIG_MTK_LCM=y`,
`CONFIG_MTK_LCM_PHYSICAL_ROTATION="0"`, `CONFIG_PSTORE* y`,
`CONFIG_SERIAL_8250_MT6577=y`, `CONFIG_COMMON_CLK_MT6771=y`,
`CONFIG_PINCTRL_MT6771=y`, `CONFIG_MTK_CMDQ* y`, `CONFIG_MTK_SMI* y`;
`CONFIG_DRM`, `CONFIG_DEBUG_FS`, `CONFIG_DEVMEM`, `CONFIG_KEXEC` — нет.

## 2. Дисплей, тач, подсветка

| Блок | Факт с T800 |
|---|---|
| режим fb0 | **1200×1920**, 32 bpp, stride 4864, `virtual_size 1216,5760` |
| панель | прямой **DSI0** (узла IT6112/bridge в живом DT **нет**), DDIC **Himax HX8279**, WUXGA |
| имя панели | в бинарном `chosen/atag,videolfb` лежит `hx8279_k080_mm2ba13_a_wuxga`; отдельное свойство `atag,videolfb-lcmname = "es6311_anx6585_zigzag_wxga"` — **устаревшее** (WXGA 1280×800, как и на T1100) |
| GPIO панели | `avdd` GPIO69, `stby` GPIO44, `rst` GPIO45, `bl` GPIO53 |
| DSI | `dsi0@14014000`, IRQ 236 (SPI 236), `mipi_tx0@11e50000` |
| подсветка | `/sys/class/leds/lcd-backlight` max 255, `led_mode = 5`, `pwm_config = <4 0 0 0 0>`; отдельно есть `mt6370_pmu_bled` (max 255). На T1100 mainline `led_mode=5` = DISP_PWM + enable-GPIO, для T800 ожидаемо PWM ch0 + GPIO53 (проверить при bring-up) |
| backlight-контроллер | `/sys/class/backlight` отсутствует |
| тач | **Silead gslX680** на `i2c0 @0x40`, драйвер `mtk-tpd`, IRQ GPIO1, reset GPIO158, питание `vldo28` |
| тач (данные) | 1200×1920, 5 касаний, project config `X621_8_HT_GG`; контроллер реально работает (в dmesg `gsl_load_fw`, `gsl_post_init`) |
| Goodix | узлы `goodix_touch@5d/@5e` (gt738x) в DT есть, но не активны: `[GTP-ERR] Module [goodix-fwu] timeout` |

Проводка панели/тача (из `odm/lcm` и `i2c@11007000`):

```
lcm:  avdd-gpios = <&pio 69>; stby = 44; rst = 45; bl = 53
touch: silead_touch@40, interrupt-parent = &pio, interrupts = <1 ...>,
       rst-gpio = <&pio 158>, vldo28
```

## 3. PMIC, питание, зарядка

| Блок | Факт |
|---|---|
| PMIC | **MT6358** через pwrap `0x1000d000`, EINT GPIO182; полный набор rails, `vldo28` = 2.8 В на тач |
| sub-PMIC | **MT6370** на `i2c5 @0x34` (pmu), TCPC `@0x4e`; EINT pmu GPIO10, TCPC GPIO41 |
| зарядник | `mt6370_pmu_charger`: `ichg 2 A`, `cv 4.35 V`, `aicr 500 mA`, safety timer 12 h |
| Type-C | role `dual`, sink PDO 5 V/2 A, PD-capable; MTU3 `dr_mode = "otg"` |
| батарея | Li-ion, **7 450 000 µA·h**, 3.8 В, сейчас 41 %, rate -80 mA; `charge_full_design` в sysfs битый (745000) |
| gauge | `mt6358_gauge` |
| второй зарядник | `sgm41513 @i2c6 0x1a` (драйвер привязан), плюс `bq25601 @0x6b`; на T1100 в mainline этот узел `disabled` — для T800 проверить, какой реально заряжает |

Регуляторы (sysfs, выборочно): `vemc 3.0 V`, `vio18 1.8 V`,
`vcn33_bt 3.5 V` включён, `vcn33_wifi` выключен (Wi-Fi не поднят),
`vgpu`/`vsram_gpu` выключены на idle; тач получает питание от `vldo28`
(phandle `vtouch-supply`). Состояния `vmc`/`vmch`/`vldo28` в sysfs не
показательны: часть rails включается потребителями/default-on.

## 4. Память, разделы, boot/recovery

eMMC: **57.6 GiB**, HS400, 56 разделов (та же `A3A561`, что на T1100).
`/dev/block/platform/bootdevice/by-name` читается:

| Раздел | Узел | Размер |
|---|---|---|
| `boot_a` / `boot_b` | p29 / p45 | 32 МиБ / 32 МиБ |
| `vendor_boot_a` / `_b` | p30 / p46 | 64 МиБ / 64 МиБ |
| `dtbo_a` / `_b` | p31 / p47 | 8 МиБ / 8 МиБ |
| `recovery` | p50 | 32 МиБ |
| `super` | p49 | 6 ГиБ (dynamic partitions) |
| `userdata` | p54 | ~50 ГиБ |
| `vbmeta_a` / `vbmeta_b` | p16 / p33 | 8 МиБ |
| `vbmeta_system_a/_b` | p17 / p34 | 8 МиБ |
| `vbmeta_vendor_a/_b` | p18 / p35 | 8 МиБ |
| `seccfg` | p11 | 8 МиБ |
| `md1img_a/_b` | p19 / p36 | 104 МиБ |
| `tee_a/_b` | p32 / p48 | 8 МиБ |

`super` — Android dynamic partitions; Aurora root — **LUKS/LVM внутри
`userdata`** (`/dev/sailfish/root` 9 ГиБ, `/home` — LUKS), rootfs не выгружался.

Внешняя SD: `mmcblk1` 116.5 GiB, один ext4-раздел смонтирован в
`/run/media/defaultuser/...` (данные пользователя, не трогать).

## 5. Wi-Fi / BT, сенсоры, клавиши, прочее

| Блок | Факт |
|---|---|
| Wi-Fi | MT6631 через **CONSYS `0x18070000`**, IRQ 289/291; прошивки `WIFI_RAM_CODE_6759`, `soc3_0_ram_*`, `WMT_SOC.cfg`; `wlan0` MAC `08:26:ae:xx:xx:xx` |
| BT | `hci0`, `rfkill0..2`, `BT_FW.cfg`, модули `bt_drv.ko`, `wmt_drv.ko`, `wlan_drv_gen3.ko`, `wmt_chrdev_wifi.ko` |
| IMU | ICM42607: accel `i2c1 @0x18`, gyro `@0x68` |
| магнитометр | MMC5603NJ `i2c1 @0x30` |
| ALS/PS | STK3x3x `i2c1 @0x49` |
| hall | GPIO2 (`elink,hallsensor`), USB-клавиатура — GPIO176 (`elink,intdev`) |
| клавиши | `mtk-kpd @0x10010000`, `kpd-hw-init-map = <0x72 ...>` (VOLUMEDOWN), power — PMIC pwrkey; homekey — PMIC |
| HDMI | IT66121 `i2c3 @0x4c`, `power_enable_gpio` GPIO54, `power_5vdd_gpio` GPIO176 (на T1100 — 52/53) |
| аудио | ES7210 mic array `i2c6 @0x40`; **AW882xx smart amp на T800 отсутствует** (на T1100 есть) |
| NFC/камеры/модем | присутствуют (pn54x, cam_main/sub, ccmni/md1img), вне скоупа v1 |

`lshal` в прошивке отсутствует (Android user build), каталоги `/vendor/bin`
и `/vendor/bin/hw` для `defaultuser` закрыты. Состав HAL восстановлен по
`/vendor/etc/init/*.rc` и `/vendor/lib64/hw/*` (списки — в инвентаре):
composer 2.1 (fbdev), gralloc 4.0, allocator 4.0, memtrack, audio,
bluetooth, gnss, sensors 2.0, thermal 2.0, health 2.1, keymaster/gatekeeper,
drm clearkey/widevine, wi-fi 1.0, usb 1.1, power, lights, fingerprint.

## 6. Что уже есть в mainline-дереве T1100 (база для T800)

Локальное дерево: `/home/leo/t1100-build/linux-6.12.114/`:

- `arch/arm64/boot/dts/mediatek/mt6771.dtsi` — `#include "mt8183.dtsi"` +
  MT6771-дельты; адреса/IRQ дисплея, GPU, SMI/IOMMU, UART, I2C, MMC, USB
  совпадают с T800 (проверено по живому DT).
- `arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dts` — board DTS T1100
  (1508 строк): eMMC/SD, USB, PMIC/MT6370, GPU, CONSYS, HDMI, сенсоры, клавиши,
  панель IT6112 1600×2176 и тач Himax.
- В mainline 6.12 уже есть `panel-boe-himax8279d.c` (1200×1920, 4 lane,
  283 init-команды) — **ближайший кандидат для панели T800**.

## 7. Gap-list: T800 vs T1100 mainline

| Блок | T1100 mainline | T800 (факт) | Что делать |
|---|---|---|---|
| SoC dtsi | `mt6771.dtsi` из `mt8183.dtsi` | те же адреса/IRQ | **без изменений** |
| Панель | IT6112 @i2c3 0x56 + BOE TV110XUM 1600×2176 | прямой DSI0, HX8279 1200×1920, GPIO avdd69/stby44/rst45 | новый `panel@0` на `&dsi0`; адаптировать `panel-boe-himax8279d` (у T800 нет pp18/pp33, есть avdd/stby) или свой `panel-hx8279`; проверить init |
| Тач | Himax HX83102E @0x48, reset158, IRQ1, vdd GPIO163 | Silead gslX680 @0x40, reset158, IRQ1, vldo28 | mainline `silead.c` (gsl1680/…), но нужна прошивка; в стоке она вкомпилирована в ядро (в `/vendor/firmware` её нет) |
| Подсветка | PWM ch0 + enable GPIO56 | GPIO53 (предположительно), MT6370 BLED тоже присутствует | проверить один раз при bring-up (яркость/blank), затем pwm-backlight enable GPIO53 либо mt6370-backlight |
| Батарея | 8 Ah, профиль T1100 | 7.45 Ah | `simple-battery` 7 450 000 µA·h + профиль gauge T800 из стокового DT |
| Сенсоры | ICM42607 @0x68, STK3338 @0x57 | accel 0x18, gyro 0x68, mag 0x30, alsps 0x49 | отдельные узлы; для MMC5603NJ в 6.12 драйвера нет (нужен порт) |
| Клавиши | GPIO93 vol-down + PMIC home vol-up | тот же kpd-map, GPIO93 в pinmux как на T1100 | проверить evdev; при необходимости те же `gpio-keys` |
| HDMI | IT66121, GPIO52/53 | IT66121, GPIO54/176 | поправить GPIO, если включать HDMI |
| Аудио | ES7210 + AW882xx | ES7210, без AW882xx | machine driver T1100 не подходит; вне v1 |
| Wi-Fi/BT | CONSYS/MT6631, патчи 0049/0056 | тот же CONSYS/MT6631 | патчи переносятся, MAC другой |
| eMMC/SD | MSDC0 HS400, MSDC1 CD GPIO3 | идентично | **без изменений** |
| USB | MTU3 + MT6370 TCPC, role switch | идентично (проверено по DT) | **без изменений** |
| VDEC/SCP | T1100 патч 0080 включает SCP/VDEC | vendor AP-side `/dev/Vcodec`, SCP не используется | **не включать** `scp`/`vcodec` в DTS T800 |
| Прошивка | recovery dd, fastboot залочен | `flash.locked=1`, AVB green/enforcing | только recovery/dd с бэкапом, как на T1100; fastboot не использовать |

## 8. План DTS

1. Новый файл `arch/arm64/boot/dts/mediatek/mt6771-fplus-t800.dts` — **копия
   board DTS T1100** (не overlay: у панели/тача другие узлы и шина).
2. Общее оставить как есть: `mt6771.dtsi`, memory, uart0, PMIC/MT6358,
   MT6370 + charger + TCPC, eMMC, SD, USB, GPU, pinctrl MMC, CPU OPP,
   CONSYS.
3. Заменить board-узлы: панель (DSI0, HX8279), тач (Silead @0x40),
   подсветку (GPIO53), сенсоры (адреса T800), батарею/профиль gauge,
   HDMI GPIO, убрать AW882xx. Для тача сохранить EINT1 с `bias-pull-up`
   (как в T1100 mainline).
4. `scp` и `vcodec_dec/enc` **не включать**.
5. Для первой загрузки — минимальный DTS без панели/тача: console/pstore,
   RAM, eMMC, USB-RNDIS. Панель/тач добавлять после подтверждения, что
   платформа грузится.

## 9. Первый безопасный шаг (без прошивки)

Сначала — **read-only бэкап** boot-разделов и GPT. Root на T800 — только
интерактивный `devel-su` (setuid, код блокировки приватный, в отчёт не
попадает). Точные команды для владельца (выполнять в root-shell):

```sh
devel-su                       # код блокировки вводит владелец
mkdir -p /tmp/t800-backup && cd /tmp/t800-backup

# только чтение разделов; rootfs/userdata/super НЕ трогаем
for p in boot_a vendor_boot_a dtbo_a vbmeta_a vbmeta_system_a \
         vbmeta_vendor_a seccfg; do
    dd if=/dev/block/by-name/$p of=$p.img bs=1M conv=fsync
done

# GPT: primary (34 сектора) + backup (если есть sgdisk)
dd if=/dev/mmcblk0 of=gpt-primary.img bs=512 count=34
sgdisk --backup=gpt-full.bin /dev/mmcblk0 2>/dev/null || true

sha256sum *.img *.bin > SHA256SUMS
ls -l
```

Забрать каталог на хост (`scp -r defaultuser@192.168.2.76:/tmp/t800-backup .`),
хранить две копии. Затем **офлайн**:

1. Распаковать `boot_a`/`vendor_boot_a` инструментами T1100
   (`scripts/repack_boot.py`, `bootimg_extract.py`), проверить, где kernel и
   DTB (`dtb_idx=0`), сделать round-trip без изменений.
2. Из стокового `Image` вытащить init панели HX8279 и прошивку Silead
   (`extract-vmlinux` + `strings`/RE) — это закроет два главных gap.
3. Собрать `mt6771-fplus-t800.dtb` (минимальный P1) в дереве T1100, сверить
   `dtc` и список узлов с `refs/t800/live-t800.dts.gz`.
4. Прошивка `boot_a` — только после проверки recovery-пути и с явным
   подтверждением владельца; откат — стоковый `boot_a.img` из бэкапа.

## 10. Риски и ограничения

- `ro.boot.flash.locked=1`, AVB `green/enforcing`: `fastboot flash` не
  использовать. Рабочий путь T1100 — recovery (USB RNDIS) + `dd` в `p29`;
  для T800 способ входа в recovery **не проверялся** (устройство не
  перезагружалось).
- `vendor_boot_a` 64 МиБ: формат boot/vendor_boot подтвердить по бэкапу,
  прежде чем перепаковывать.
- Панель HX8279: mainline-драйвер `boe,himax8279d10p` — кандидат, но
  init-последовательность T800 может отличаться; до проверки на стекле
  DTS-узел держать `disabled`. GPIO69 (`avdd`) сначала держать
  `regulator-always-on`: на T1100 аналогичный rail (GPIO55) питал ещё и
  level-shifters I2C, и его выключение убивает i2c0..6.
- Тач Silead: без firmware-блоба драйвер не поднимется; альтернатива —
  портировать vendor `gslX680` (как T1100 портировал Himax).
- VDEC: vendor AP-side уже работает; mainline VDEC/SCP **не поднимать**.
- `/sys/firmware/fdt` и `/sys/fs/pstore` для `defaultuser` недоступны
  (root-only); живой DT снят через `/proc/device-tree`, этого достаточно.

# Aurora OS 5.2.1.200 — RPM-адаптация Fplus T1100 (справочный слепок)

**Дата разбора:** 10.11.2026
**Источник:** `/home/leo/omv-share/leo/Projects/aurora-5.2.1.200/omp-hw/adaptation-mediatek-fplus_t1100/`
**Тип:** бинарный RPM-репозиторий (armv7hl/i486/main/tb-cert/tb-corp/tz-cert/tz-corp),
403 RPM, из них 107 в `main`. SRPM и исходников драйверов нет.

Это не готовый порт для mainline, а склад **точных вендорских бинарников**:
прошивок, модулей ядра 4.14.186, DTB и init-скриптов. Полезен как источник
firmware и как референс для RE; заменить драйверы mainline он не может.

## Пакеты

Базовый путь `main/pj:hw:mediatek:fplus_t1100:/noarch/`:

| Пакет | Версия | Размер | Что внутри |
|---|---|---|---|
| `droid-hal-fplus_t1100-kernel` | 0.3.13-1.4.2 | 9.9 МБ | `boot/kernel-4.14.186`, `boot/dt.img`, пустой `boot-initramfs.gz` |
| `droid-hal-fplus_t1100-kernel-modules` | 0.3.13-1.4.2 | 5.2 МБ | `/vendor/lib/modules/4.14.186/*.ko` (Wi-Fi/BT/GPS/FM/fpsgo/met) |
| `droid-hal-fplus_t1100-kernel-dtbo` | 0.3.13-1.4.2 | — | DTBO-оверлеи (odm/lcm, backlight, touch и т.п.) |
| `droid-hal-fplus_t1100-kernel-modules-sample` | 0.3.13-1.4.2 | — | только пример kobject, не исходники |
| `droid-hal-fplus_t1100-lk` | 0.3.13-1.4.2 | — | `lk_a.bin` (использован в RE панели IT6112) |
| `droid-hal-fplus_t1100-preloader` | 0.3.13-1.4.2 | — | preloader |
| `droid-hal-fplus_t1100-trustzone` | 0.3.13-1.4.2 | — | TEE |
| `droid-hal-fplus_t1100-tools` | 0.3.13-1.4.2 | — | `wmt_loader`, `wmt_launcher`, `autobt` и др. |
| `droid-system-vendor-fplus_t1100` | 0.3.5-1.2.13 | 115 МБ | весь `/vendor`, включая `firmware/` и Wi-Fi/BT HAL |
| `droid-config-fplus_t1100-sailfish` | 0.7.5-1.3.9 | — | конфиги системы |
| `droid-hal-fplus_t1100` | 0.3.13-1.4.2 | — | метапакет адаптации |

`droidsrc-info` и `droidsrc-extra-sources-info` содержат **пустой cpio** —
только метаданные. `-devel` — Android-заголовки, не исходники ядра.

## Ядро и модули

- Ядро: **4.14.186**, `boot/kernel-4.14.186` (10 375 665 Б), aarch64.
- `boot/dt.img` — MTK-контейнер (`d7 b7 ab 1e`, первый DTB `0x1b1b7` =
  111 095 Б); внутри вендорский DTB с `wifi@180f0000`, `touch` и т.п.
- Модули: `/vendor/lib/modules/4.14.186/`; `modinfo` даёт vermagic
  `4.14.186 SMP preempt mod_unload modversions aarch64`.
  Зависимости: `wlan_drv_gen3 -> wmt_chrdev_wifi, wmt_drv`;
  `bt_drv -> wmt_drv`.
- `modules.load` (порядок загрузки): `kheaders, bt_drv, wmt_drv,
  fmradio_drv, gps_drv, wmt_chrdev_wifi, wlan_drv_gen3, fpsgo, met`.
- **В 6.12 эти модули не загрузятся**: vermagic + `modversions` + символы
  `mtk_wcn_*`, которых в mainline нет.

Ключевые модули (локальные копии — `vendor/aurora-5.2.1.200/modules-4.14.186/`):

| Файл | Размер | sha256 (начало) |
|---|---|---|
| `wlan_drv_gen3.ko` | 4 083 080 | `0790085d…` |
| `wmt_drv.ko` | — | `a4ebe951…` |
| `wmt_chrdev_wifi.ko` | 42 832 | `3ae33b0c…` |
| `bt_drv.ko` | 65 968 | `f09337dc…` |

`wlan_drv_gen3.ko` в строках содержит `mediatek,wifi`, `MT6631`,
`/vendor/firmware/`, `WIFI_RAM_CODE_`, `wifi_fw.cfg`,
`mtk_wcn_consys_hw_wifi_paldo_ctrl`. `bt_drv.ko` — STP-char-драйвер
(`mtk_wcn_stp_*`, `driver/bt_dbg`), а не обычный `hci_uart`.

## Firmware (`/vendor/firmware/`)

14 файлов; локальная копия — `vendor/aurora-5.2.1.200/firmware/`
(8.9 МБ вместе с модулями, gitignored).

| Файл | Размер | sha256 |
|---|---|---|
| `WIFI_RAM_CODE_6759` | 480 752 | `0aa28a876f5fe8fe18f0cd02544f43fec655303d995283fa0d884d5e593b9729` |
| `WMT_SOC.cfg` | 119 | `ea673ab15c936ebf98a6ab356685528173e9458f7069cc50064363ebe551cf32` |
| `BT_FW.cfg` | 410 | `e018d7b8153af454d7e5c51626d584582904ffc5ba2bd8edb5d2a1ed27124b67` |
| `soc3_0_ram_bt_1_1_hdr.bin` | 671 276 | `7e3628110424e901a7057029f0a77110062325599b52995c59316d67cddbb450` |
| `soc3_0_ram_bt_1a_1_hdr.bin` | 671 276 | `af45d8b86be7e0c3012483ef1c60351f4fd91e9259d7fb8c599b3b5b69065106` |
| `soc3_0_ram_mcu_1_1_hdr.bin` | 165 344 | `1b8330fddfaac8d894494ad1a7e327089fe97acca28515cd83b5787e23a92330` |
| `soc3_0_ram_mcu_1a_1_hdr.bin` | 165 344 | то же |
| `soc3_0_ram_mcu_e1_hdr.bin` | 165 344 | то же |
| `ROMv4_be_patch_1_0_hdr.bin` | 229 384 | `83f7e9bc06628b2c3768b190de1c19ecb7846b0bd990e2728f72638b4340da6c` |
| `ROMv4_be_patch_1_1_hdr.bin` | 314 120 | `2203d8b76a497d85c0e8cd7daa6da0e8158f7a148a296150a46e1c977e9cd95d` |
| `mt6631_fm_v1_patch.bin` | 1 028 | `ba35c74d26660729caf83b41a567e700f633b6c99384dfa6cbb3c17ceb767e26` |
| `mt6631_fm_v1_coeff.bin` | 1 092 | `d32f4a16b35f950ed1a57f2ae88f77ac4b5674d5c4210b65f6fe7912901fd8db` |
| `fm_cust.cfg` | 304 | `0f24efadab3d3e8286774cb50495f65d26ed96b280d9d684f54fdd1d4f6c72d7` |
| `Himax_firmware.bin` | 131 072 | `c9cfe8b4e1bbdab128298da2b8342973b968f254fbea97edcff5436d4534e5d5` |

`WMT_SOC.cfg` целиком:

```
coex_wmt_ant_mode=1
wmt_gps_lna_pin=0
wmt_gps_lna_enable=0
co_clock_flag=0
bt_tssi_from_wifi=3
bt_tssi_target=3815
```

## Init-скрипты (Android/Aurora)

- `init.wmt_drv.rc`: на boot `insmod /vendor/lib/modules/wmt_drv.ko`.
- `init.wlan_drv.rc`: по свойству `vendor.connsys.driver.ready=yes`
  грузит `wmt_chrdev_wifi.ko`, затем `wlan_drv_${ro.vendor.wlan.gen}.ko`,
  стартует `wlan_assistant`.
- `init.bt_drv.rc`: грузит `bt_drv.ko`, делает chown `/proc/driver/bt_dbg`.

То есть порядок вендора: **WMT driver → (firmware download) → Wi-Fi/BT
char-драйверы**, а не «просто hci_uart».

## Что это даёт mainline-порту

1. **Точные firmware-блобы** для будущего WMT/CONNSYS-драйвера: их не надо
   искать по интернету, они совпадают с этой платой.
2. **Вендорский DTB** (`dt.img`) — сверка узлов `wifi@180f0000`, `touch`,
   регуляторов и GPIO.
3. **Модули как RE-референс**: строки, SDIO ID, порядок инициализации,
   зависимость BT от `wmt_drv`.
4. **`Himax_firmware.bin`** — если mainline-драйвер (`himax_hx83112b.c`,
   патчи 0040/0041) не поднимет HX83102E без загрузки прошивки.

## Чего здесь нет

- Исходников `wlan_drv_gen3`, `wmt_drv`, `bt_drv` — только бинарники 4.14.
- Готового mainline-драйвера: Wi-Fi/BT по-прежнему требует WMT/CONNSYS
  (power-on, firmware download, STP) — это отдельная большая задача фазы 5.
- Alpine/Ubuntu-пакетов: репозиторий Aurora (rpm), не для нашего rootfs.

Альтернативный путь «взять вендорское ядро 4.14» дал бы работающие Wi-Fi/BT,
но это не mainline-порт и он несовместим с уже сделанным DRM/panfrost-стеком.

## Воспроизведение

RPM распаковывались `7z` (внешний cpio) → `gzip`/`zstd` → `cpio -id`.
Готовые деревья на момент разбора:

- `/tmp/opencode/t1100-rpms/kern/x/boot/` — ядро и `dt.img`;
- `/tmp/opencode/t1100-rpms/km/x/lib/modules/4.14.186/` — модули;
- `/tmp/opencode/t1100-rpms/ven-x/vendor/firmware/` — прошивки.

`/tmp` не является хранилищем: долговременные копии — в
`vendor/aurora-5.2.1.200/` (gitignored) и в самом RPM-репозитории на
`omv-share`.

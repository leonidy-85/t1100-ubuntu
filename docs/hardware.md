# Железо: Fplus T1100 (MT6771 / MT8788)

Данные сняты с живого экземпляра (Aurora 5.1.6.110) 27–28.10.2026.

## SoC / CPU / GPU

| Параметр | Значение |
|---|---|
| Маркировка | `MT6771V/C` (`/proc/device-tree/model`), `mediatek,mt6771` |
| Идентичность | **MT8788 = MT6771 = Helio P60/P70** — один кристалл (TSMC 12nm FinFET) |
| CPU | 4× Cortex-A73 + 4× Cortex-A53 (big.LITTLE), aarch64 |
| GPU | **Mali-G72 MP3 (Bifrost)**, `arch 6.2.2 r0p3` |
| GPU-драйвер (ядро) | `mali_kbase` DDK **r26p0-01eac0**, `/dev/mali0` |
| RAM | 3791 MiB |
| eMMC | 60 416 000 КБ (~64 ГБ) |
| APU/ISP | APU 1.0, dual ISP (не нужны для десктопа) |

## Ядро (текущее, Aurora)

- `Linux 4.14.186 #1 SMP PREEMPT ... aarch64` — **downstream MTK + hybris**.
- Конфиг: `/proc/config.gz` (`CONFIG_IKCONFIG=y`).
- **DRM/KMS нет** (`/sys/class/drm`, `/dev/dri` отсутствуют; `CONFIG_DRM` не задан).
- Дисплей — **`mtkfb`** (framebuffer), `/dev/fb0`.
- `CONFIG_FB=y`, `CONFIG_VT=y`, `CONFIG_DEVTMPFS=y`, `CONFIG_CGROUPS=y`,
  `CONFIG_NAMESPACES=y`, `CONFIG_VETH=y`, `CONFIG_SYSVIPC=y` — systemd/Ubuntu
  совместимы.
- `CONFIG_KPROBES` **не задан**, `CONFIG_STRICT_KERNEL_RWX=y`,
  `CONFIG_SECURITY_WRITABLE_HOOKS` не задан.
- `CONFIG_MODULES=y`, `CONFIG_MODVERSIONS=y`, `CONFIG_MODULE_SIG=y`
  (`MODULE_SIG_FORCE` не задан; в cmdline `module.sig_enforce=1`).

## Дисплей

- Драйвер `mtkfb` (MTK legacy), панель по **MIPI DSI** (`lcm_get_params`,
  DSI PLL 790) — **не напрямую, а через мост ITE IT6112** (DSI → panel),
  см. `docs/hardware.md#мост-ite-it6112` и `refs/it6112/`.
- Второй выход дисплея: **HDMI через ITE IT66121** от DPI0 (`&dpi0`, 12 бит),
  i2c3 @0x4c, reset GPIO79 — есть в `refs/mt6771-next/mt8788-fplus-t1100.dts`.
- Тач: **Himax** (`touchpanel.config.himax_tp=1`, project `X107_10`),
  `i2c@11007000`, адрес `0x48`, IRQ 19.
- Конвейер (из `dispsys`):
  - DIRECT_LINK: `OVL → COLOR → CCORR → AAL → GAMMA → DITHER → DSI`
  - DECOUPLE: `OVL → WDMA → fb → RDMA → COLOR → … → DSI`
- Для KMS нужен DRM-драйвер: DSI-host + CRTC (OVL/RDMA) + MMSYS/mutex/CMDQ.

### Board-узлы из dtbo (нужны для DTS)

| Узел | Значение |
|---|---|
| `odm/lcm` (`elink,lcm`) | `rst` GPIO45, `dvdd` GPIO55, `stby` GPIO44, `bl` GPIO56, `ext_pwr` GPIO175, `ts_rst` GPIO158, `ts_avdd` GPIO163 |
| backlight | `mediatek,lcd-backlight`, `led_mode = 5`, `pwm_config = <4 0 0 0 0>` |
| тач | `himax_touch@48` на `i2c@11007000`, `mediatek,himax_touch` |
| прочее | `usbkeyboard` (док-клавиатура), `hallsensor`, `focaltech_fp`, `vibrator` |
| CPU OPP | A53/A73: 793…1989 МГц (`policy0`/`policy4`) |

### Мост ITE IT6112 (уточнено 29.10.2026)

Панель подключена не к DSI-хосту напрямую, а к мосту **ITE IT6112**
(DSI-DUAL_DSI). Факты из публичного WIP-драйвера
`refs/it6112/panel-it6112-boe-tv110xum-lb2.c` (`linux-mediatek/linux` @ `935fe30`):

| Параметр | Значение |
|---|---|
| I2C-адрес моста (MIPI TX) | **0x56** на `i2c3` (в board DTS adomerle; в нашем DTS i2c3 пока нет) |
| I2C-адрес MIPI RX | **0x5e** (dummy-клиент на том же адаптере) |
| Product ID | `(revid << 8) | chipid` = **0x6112** |
| `compatible` | `boe,tv110xum-lb2-it6112` |
| DSI | **4 lane**, video mode + sync pulse, RGB888 |
| Режим | 1600×2176, clock **255798 кГц**, 166×226 мм |
| Питание | `dvdd` (GPIO55 fixed), `vpos`/`vneg` (**MT6370** dsvpos/dsvneg) |
| Reset | GPIO45 (active high) |
| Backlight | `pwm-backlight`: PWM0, enable GPIO56 |
| Init | I2C-регистры моста, DCS-команды через регистр **0x73** |

### Панель (уточнено 29.10.2026)

| Параметр | Значение | Источник |
|---|---|---|
| Модель | **BOE TV110XUM-LB0-1SP0** (11.0", a-Si, 1600×2176, 245 PPI, 3:4) | Panelook + `/sys/.../fb0` (1600×2176, stride 6400) |
| Интерфейс | MIPI DSI, **4 lane**, `BURST_VDO_MODE`, RGB888 | dmesg/lcm |
| PLL clock | 790 (МГц) | `dmesg: lcm_get_params ... PLL_CLOCK = 790` |
| LCM-драйвер в стоке | `drivers/misc/mediatek/lcm/elink_lcm/tv110xum_lb2_incell/` (вкомпилирован в ядро) | `strings Image` |
| `atag,videolfb-lcmname` | `es6311_anx6585_zigzag_wxga` — **устаревшая строка** от другого продукта, не соответствует реальной панели | ATAG на устройстве |
| Тач | in-cell + внешний Himax | `touchpanel.config.*` |
| Мост | **ITE IT6112** (i2c3 0x56 / MIPI RX 0x5e) | `refs/it6112/` |

> Панель 1600×2176 (портрет), за мостом IT6112. Init-последовательность и
> тайминги **есть в исходнике** — WIP-драйвер `refs/it6112/panel-it6112-boe-tv110xum-lb2.c`
> (автор Arseniy Velikanov). Риск «RE бинарника LCM» снят; остаётся бэкпорт
> драйвера с 6.16 на 6.12 и проверка на железе.

### Карта регистров дисплея (из стокового DTB, `refs/stock-mt6771.dts`)

| Блок | Адрес | IRQ (SPI) | mainline-аналог |
|---|---|---|---|
| `mmsys_config` | `0x14000000` | 0xef | `mediatek,mt8183-mmsys` |
| disp OVL0 | `0x14008000` | 0xe1 | `mt8183-disp-ovl` |
| disp OVL0_2L | `0x14009000` | 0xe2 | `mt8183-disp-ovl-2l` |
| disp OVL1_2L | `0x1400a000` | 0xe3 | `mt8183-disp-ovl-2l` |
| disp RDMA0 / RDMA1 | `0x1400b000` / `0x1400c000` | 0xe4/0xe5 | `mt8183-disp-rdma` |
| disp WDMA0 | `0x1400d000` | 0xe6 | `mt8183-disp-wdma`? |
| disp COLOR0 | `0x1400e000` | 0xe7 | `mt8183-disp-color` |
| disp CCORR0 | `0x1400f000` | 0xe8 | `mt8183-disp-ccorr` |
| disp AAL0 | `0x14010000` | 0xe9 | `mt8183-disp-aal` |
| disp GAMMA0 | `0x14011000` | 0xea | `mt8183-disp-gamma` |
| disp DITHER0 | `0x14012000` | 0xeb | `mt8183-disp-dither` |
| **DSI0** | `0x14014000` | 0xec | `mt8183-dsi` |
| DPI0 | `0x14015000` | 0xed | `mt8183-dpi` |
| mutex | `0x14016000` | 0xd9 | `mt8183-disp-mutex` |
| smi_larb0 | `0x14017000` | 0xf0 | `mt8183-smi-larb` |
| smi_common | `0x14019000` | — | `mt8183-smi-common` |
| DISP_PWM0 | (см. DTB) | — | `mt8183-disp-pwm` |
| MDP RDMA0/1 | `0x14001000` / `0x14002000` | 0xda/0xdb | MT6771-специфично (MDP3) |
| mipi_tx0 | `0x11e50000` | — | `mt8183-mipi-tx`? (сверить) |

Совпадение адресов OVL/RDMA/COLOR/CCORR/AAL/GAMMA/DITHER/DSI/mutex/larb/smi
с mainline `mt8183.dtsi` — **полное**. Это основа решения фазы 0.

## PMIC / питание

- **MT6358** (`mt6358-pmic`, `mt6358_gauge`) — тот же PMIC, что у MT8183;
  mainline-драйверы `mt6358-regulator`, `mt6358-keys`, `mt6358-rtc` применимы.
- `pwrap@1000d000`, `topckgen@10000000`, `infracfg_ao@10001000`,
  `pericfg@10003000` — адреса как у MT8183.

## GPU (уточнено)

- `mali@13040000` (0x4000), `mfgcfg@13000000`, IRQ SPI **278 (`job`), 279
  (`mmu`), 280 (`gpu`)** — ровно как в mainline `mt8183.dtsi`
  (`gpu@13040000`, `mediatek,mt8183b-mali`, `arm,mali-bifrost`).
- Стоковый compatible: `mediatek,mali`, `arm,mali-midgard`, `arm,mali-bifrost`;
  DDK `mali_kbase` r26p0. Для panfrost достаточно `arm,mali-bifrost` + питание/клоки.

## Разметка (ключевое)

| Раздел | Устройство | Размер |
|---|---|---|
| `boot_a` | `/dev/mmcblk0p29` | 32 МБ |
| `vendor_boot_a` | p30 | 64 МБ |
| `dtbo_a` | p31 | 8 МБ |
| `vbmeta_a` | p16 | 8 МБ |
| `seccfg` | p11 | 8 МБ |
| `super` | p49 | 6 ГБ (Android system/vendor для hybris) |
| `userdata` | p54 | ~52 ГБ (сток — LVM `sailfish`; сейчас ext4, метка `ubuntu`) |
| `recovery` | p50 | 32 МБ |
| `md1img_a` | p19 | 64 МБ (модем) |
| `tee_a` | p32 | 8 МБ |
| `preloader`/`lk` | boot1 / p28 | — |

`userdata` (p54) в стоке — LVM VG `sailfish` с `sailfish-root` (`/`, 9 ГБ) и
`sailfish-home` (`/home`, 41 ГБ). 31.10.2026 LVM снесён (с подтверждения
владельца), p54 переформатирован в **ext4 с меткой `ubuntu`** под Ubuntu
24.04; сейчас это единственный rootfs проекта.

## Wi-Fi / BT / USB

- Combo: **CONSYS_6771 = MT6630/MT6631** (сток: `CONFIG_MTK_COMBO_CHIP_CONSYS_6771`,
  `CONFIG_MTK_COMBO_WIFI`, `CONFIG_MTK_COMBO_BT`).
- В стоковом DTS — узел `wifi@180f0000` (`compatible = "mediatek,wifi"`,
  регистры `0x180f0000`, `0x10212180`, `0x10001000`, `0x180e0000`; IRQ 290 и 118;
  клок `wifi-dma`). Это **не SDIO**: у `msdc0` стоит `no-sdio`, `msdc1` — карта
  памяти, `wifi-pwrseq` в стоке `disabled`.
- Питание: LDO MT6358 **`vcn33_wifi`** и **`vcn33_bt`** (3.3 В).
- Wi-Fi — через WMT/CONNSYS, вендорский `wlan_drv_gen3`; BT — HCI UART H4 через
  тот же WMT (сток: `CONFIG_BT_HCIUART_H4=y`).
- Прошивка: **`/vendor/firmware/`** (`WIFI_RAM_CODE_6759`, `WMT_SOC.cfg`,
  `soc3_0_ram_*.bin`, `mt6631_fm_*` и т.п.). В Ubuntu-rootfs `/lib/firmware` нет.
- **Mainline 6.12: поддержки нет** — ни драйвера, ни узлов в DTS; `mt76` этот
  чип не покрывает, для BT готового CONNSYS/WMT-пути тоже нет. Сейчас Wi-Fi и
  BT не работают, сеть — только RNDIS по USB. Порт вендорского стека — фаза 5.
- USB: MUSB-HDRC + XHCI (база `0x11200000`), OTG. В mainline
  `dr_mode = "peripheral"`, host/OTG не поднят (`tcpc` отключён, `tcpci` не
  находит `connector`), поэтому USB-донгл Wi-Fi/BT — не быстрый обход.

## Отладка / консоль

- **UART0**: `11002000.serial`, MMIO `0x11002000`, Linux virq **286** = DT
  `GIC_SPI 91`, `mt6577-uart` (`base_baud 1625000`), `/dev/ttyS0`; консоль в стоке включена
  (`mtk_printk_ctrl.disable_uart=0`), но вывод идёт в `ram_console`/`pstore`.
- **ramoops**: `0x54410000`, size `0xe0000` (`console_size 0x40000`,
  `pmsg_size 0x10000`); `ram_console` — `0x54400000..0x54410000`.
- **UART-подключения к плате нет** — логи снимаются из `pstore` после перезагрузки
  (проверено: `console-ramoops` прошлой загрузки читается).
- Для mainline: `ramoops.mem_address=0x54410000 ramoops.mem_size=0xe0000
  ramoops.console_size=0x40000` (или узел `ramoops` в DTS) + `console=ttyS0`,
  `earlycon` — как только появится доступ к UART.

## Загрузка

- **PSCI есть**: `arm,psci-1.0`, `method = "smc"`, 8 CPU online (сток).
- **GICv3**: `GICD 0x0c000000`, `GICR 0x0c100000` (dmesg стока).
- A/B-слоты; текущий `_a`.
- Android boot image **header v2** (gzip-ядро + ramdisk + DTB 111095 байт):
  `kernel_addr=0x40080000`, `ramdisk_addr=0x55000000`, `tags_addr=0x54000000`,
  `dtb_addr=0x54000000`, page 2048, `header_size=1660`, cmdline без `console=`.
- DTB в образе — **не голый FDT**: MTK-контейнер 64 байта
  (`magic d7 b7 ab 1e` BE, `total=0x40+len(fdt)`, `payload_len`, `payload_off=0x40`).
  Поля контейнера — **big-endian**. Перепаковка: `scripts/repack_boot.py`
  (round-trip стокового образа — **побайтово идентично**, sha256 совпадает).
- Загрузчик — MTK `lk`; **verified boot не проверяет патченный boot** (проверено:
  модифицированный `boot_a` с IMA/diehard off загружается).
- `fastboot` залочен: `devices`/`reboot-bootloader` отвечают, `getvar`/`flash`/
  `oem*` виснут. BROM — `0e8d:0003` (нужны кнопки + USB). Recovery —
  `2931:0a06 "Jolla Recovery"`, RNDIS `10.42.66.66`.

## Доступ (тестовый экземпляр)

- SSH: `defaultuser@172.17.141.62`, ключ `~/.ssh/id_ed25519`, пароль `12345`.
- Root: `devel-su`, пароль `12345`.
- Recovery: `root`/`recovery` (RNDIS `10.42.66.66`, telnet → «5) Run sshd»;
  devicelock `12345`). **Внимание:** recovery T1100 и NS220 оба на `10.42.66.66`
  — перед записью сверять `/proc/partitions` (T1100: p29=32768, p54≈52 ГБ).

## Стоковое состояние (после security-off)

- `ima_appraise=off`, diehard убран из LSM (`capability,yama`).
- `/home` — plain ext4 на `/dev/mapper/sailfish-home` (не LUKS).
- device-lock снят сервисом `devlock-unlock.service`.
- Это не важно для порта (rootfs всё равно заменяется), но полезно для доступа.

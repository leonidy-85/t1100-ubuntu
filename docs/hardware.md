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
  DSI PLL 790).
- Тач: **Himax** (`touchpanel.config.himax_tp=1`, project `X107_10`),
  `i2c@11007000`, адрес `0x48`, IRQ 19.
- Конвейер (из `dispsys`):
  - DIRECT_LINK: `OVL → COLOR → CCORR → AAL → GAMMA → DITHER → DSI`
  - DECOUPLE: `OVL → WDMA → fb → RDMA → COLOR → … → DSI`
- Для KMS нужен DRM-драйвер: DSI-host + CRTC (OVL/RDMA) + MMSYS/mutex/CMDQ.

### Панель (уточнено 28.10.2026)

| Параметр | Значение | Источник |
|---|---|---|
| Модель | **BOE TV110XUM-LB0-1SP0** (11.0", a-Si, 1600×2176, 245 PPI, 3:4) | Panelook + `/sys/.../fb0` (1600×2176, stride 6400) |
| Интерфейс | MIPI DSI, **4 lane**, `BURST_VDO_MODE`, RGB888 | dmesg/lcm |
| PLL clock | 790 (МГц) | `dmesg: lcm_get_params ... PLL_CLOCK = 790` |
| LCM-драйвер в стоке | `drivers/misc/mediatek/lcm/elink_lcm/tv110xum_lb2_incell/` (вкомпилирован в ядро) | `strings Image` |
| `atag,videolfb-lcmname` | `es6311_anx6585_zigzag_wxga` — **устаревшая строка** от другого продукта, не соответствует реальной панели | ATAG на устройстве |
| Тач | in-cell + внешний Himax | `touchpanel.config.*` |

> Панель 1600×2176 (портрет). Для KMS нужен DRM-panel с таймингами из
> `tv110xum_lb2_incell` (init-последовательность придётся извлечь из
> вкомпилированного LCM-драйвера — исходника в публичных репо нет; см. риск RE).

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
| `userdata` | p54 | ~52 ГБ (LVM `sailfish`: root 9 ГБ + home 41 ГБ) |
| `recovery` | p50 | 32 МБ |
| `md1img_a` | p19 | 64 МБ (модем) |
| `tee_a` | p32 | 8 МБ |
| `preloader`/`lk` | boot1 / p28 | — |

`userdata` (p54) — это LVM VG `sailfish` с `sailfish-root` (`/`, 9 ГБ) и
`sailfish-home` (`/home`, 41 ГБ).

## Wi-Fi / BT / USB

- Wi-Fi/BT: **MT6630/MT6631** (combo), драйвер `wlan_drv_gen3` (+ `wmt_drv`).
- Прошивка: **`/vendor/firmware/`** (`WIFI_RAM_CODE_6759`, `WMT_SOC.cfg`,
  `soc3_0_ram_*.bin`, `mt6631_fm_*` и т.п.). `/lib/firmware` отсутствует.
- USB: MUSB-HDRC + XHCI (база `0x11200000`), OTG.

## Отладка / консоль

- **UART0**: `11002000.serial`, MMIO `0x11002000`, IRQ **286**, `mt6577-uart`
  (`base_baud 1625000`), `/dev/ttyS0`; консоль в стоке включена
  (`mtk_printk_ctrl.disable_uart=0`), но вывод идёт в `ram_console`/`pstore`.
- **ramoops**: `0x54410000`, size `0xe0000` (`console_size 0x40000`,
  `pmsg_size 0x10000`); `ram_console` — `0x54400000..0x54410000`.
- Для mainline: `earlycon=mt6577,0x11002000 console=ttyS0,921600n8` (baud уточнить).

## Загрузка

- A/B-слоты; текущий `_a`.
- Android boot image **header v2** (gzip-ядро + ramdisk + DTB 111095 байт).
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

## Текущее состояние (после security-off)

- `ima_appraise=off`, diehard убран из LSM (`capability,yama`).
- `/home` — plain ext4 на `/dev/mapper/sailfish-home` (не LUKS).
- device-lock снят сервисом `devlock-unlock.service`.
- Это не важно для порта (rootfs всё равно заменяется), но полезно для доступа.

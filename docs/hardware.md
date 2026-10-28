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
- Тач: **Himax** (`touchpanel.config.himax_tp=1`, project `X107_10`).
- Конвейер (из `dispsys`):
  - DIRECT_LINK: `OVL → COLOR → CCORR → AAL → GAMMA → DITHER → DSI`
  - DECOUPLE: `OVL → WDMA → fb → RDMA → COLOR → … → DSI`
- Для KMS нужен DRM-драйвер: DSI-host + CRTC (OVL/RDMA) + MMSYS/mutex/CMDQ.

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

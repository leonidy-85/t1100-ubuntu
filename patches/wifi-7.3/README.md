# Wi-Fi MT6631 vendor stack — Linux 7.3 port

This directory holds the Linux 7.3 API adaptations for the MediaTek MT6631
vendor Wi-Fi stack.  They apply **on top of** the existing 6.12 series in
`patches/wifi/`, which in turn applies to the public Motorola GPL sources.

## Sources

| tree | repository | commit |
|------|------------|--------|
| `common` | `github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common` | `3ff67212dcc4` (branch `Pie-9-release-POBS`) |
| `wlan` | `github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-core-gen3` | `249649d877d8` (branch `Pie-9-release-POBS`) |
| `btif` | `github.com/haretic/android-kernel-mt6765-rabbitr1` | `main`, sparse path `drivers/staging/mtk-connectivity/btif` |

The BTIF tree gets `scripts/remote/m23-btif/{m23_board.c,m23_board.h,Makefile}`
and `patches/wifi/0010-btif-mt6771-glue.patch` before the 7.3 patch below.

## Applying

```sh
# 1. vendor 6.12 port (split by filename)
for p in patches/wifi/*.patch; do
    case "$(basename "$p")" in
        *-common-*) (cd common && patch -p1 --forward -F3 < "$OLDPWD/$p");;
        *-wlan-*)   (cd wlan   && patch -p1 --forward -F3 < "$OLDPWD/$p");;
    esac
done

# 2. this 7.3 series
(cd common && patch -p1 < "$OLDPWD/patches/wifi-7.3/0001-common-7.3-api.patch")
(cd wlan   && patch -p1 < "$OLDPWD/patches/wifi-7.3/0002-wlan-7.3-api.patch")
(cd btif   && patch -p1 < "$OLDPWD/patches/wifi-7.3/0003-btif-7.3-api.patch")
```

`scripts/remote/wifi-compat/` is copied next to the trees (the wrappers expect
`../compat/include`).  The 7.3 additions there are `linux/of_gpio.h` (the
upstream header was removed) and the `FB_EVENT_BLANK` fallback in
`mtk_port_414.h`.

Use the Kbuild wrappers from `scripts/remote/wifi-kbuild/` instead of the
vendor Makefiles.

## What the 7.3 patches change

`0001-common-7.3-api.patch`
- `osal.c`: `from_timer` -> `timer_container_of`, `del_timer[_sync]` ->
  `timer_delete[_sync]`, `strncpy` -> `memcpy`/`strscpy`.
- `connsys_debug_utility.c`: new alarmtimer API (`alarm_start_timer(...,
  true)`, void callback, no `ALARMTIMER_NORESTART`).
- `wmt_ctrl.c`: `strncpy` -> `strscpy`.

`0002-wlan-7.3-api.patch`
- `gl_init.c`, `gl_p2p.c`, `gl_p2p_kal.c`: cfg80211 callbacks now receive
  `struct wireless_dev *`; wrappers convert with `wdev->netdev`.
- `mgmt_tx`/`remain_on_channel`: cookie and address are passed by value.
- `set_wiphy_params` and set/get TX power gained `radio_idx`/`link_id`.
- `gl_kal.c`: timer API renames.
- `gl_vendor.c`, `gl_wext.c`, `gl_kal.h`: `strncpy` -> `strscpy`.

`0003-btif-7.3-api.patch`
- `m23_board.c`: `of_node_to_fwnode()` -> `of_fwnode_handle()`.

## Build

```sh
K=linux-t1100-7.3
O=build/t1100-7.3-wifi
CC=.../aarch64-none-linux-gnu-
W=/tmp/opencode/wifi-work
B=/tmp/opencode/btif-work

make -C $K O=$O ARCH=arm64 CROSS_COMPILE=$CC LOCALVERSION=-wifi1 \
     M=$B -j20 modules

make -C $K O=$O ARCH=arm64 CROSS_COMPILE=$CC LOCALVERSION=-wifi1 \
     KBUILD_EXTRA_SYMBOLS=$B/Module.symvers M=$W/common -j20 modules

make -C $K O=$O ARCH=arm64 CROSS_COMPILE=$CC LOCALVERSION=-wifi1 \
     KBUILD_EXTRA_SYMBOLS="$W/common/Module.symvers $B/Module.symvers" \
     M=$W/wlan -j20 modules
```

The kernel out tree must have `CFG80211`, `MAC80211`, `WEXT_CORE`,
`WEXT_PRIV`, `NL80211_TESTMODE` and `RFKILL` built in (or their modules
installed); `LOCALVERSION` must match the running kernel.

## Built artifacts

Vermagic `7.3.6-wifi1+ SMP preempt mod_unload aarch64`:

| file | size | sha256 |
|------|------|--------|
| `wlan_drv_gen3.ko` | 2904696 | `a77b6e22e86d5a65fb812e96637b70080199e98dea0acf2c8221ebab9248bd86` |
| `wmt_drv.ko` | 1190024 | `29716e6f1b2acbfc23e2a18cf1692dd4a37c72c2f1d29d8431b2f5da596e78d0` |
| `mtk_btif_drv.ko` | 195656 | `ee5d1296326221556903f97a770a08e2e6a745f52d068b1ce107e986e54761d8` |

Install to `/lib/modules/$(uname -r)/updates/wifi/` and run `depmod -a`.
Load order: `mtk_btif_drv` -> `wmt_drv` -> `wlan_drv_gen3`.

## Runtime status (2026-11-25)

- `mtk_btif_drv` and `wmt_drv` load; `wlan_drv_gen3` loads and probes.
- With `t1100_probe=0`, driver-own succeeds (`CMD52`, `DRIVER OWN, status=1
  count=17`), so the STP/BTIF transport and CONSYS power-on work.
- Firmware download still fails:
  `kalFirmwareOpen: Open FW image failed! Cur/Max ECO Ver[E1/E1]` then
  `wlanAdapterStart: No valid RAM code found!`; no `wlan0`.
- The RAM code file is present as `/lib/firmware/WIFI_RAM_CODE_6759` (480704
  bytes), but `kalFirmwareOpen()` only adds `/lib/firmware/` to its search
  path when `CONFIG_ANDROID` is **not** defined.  Verify that define, or add
  the path unconditionally.
- Do **not** `rmmod`/reload the loaded stack on the current image: it can hang
  the tablet and trigger a watchdog reboot.

## Next step

Fix the firmware search path / credential override in `kalFirmwareOpen()`,
rebuild `wlan_drv_gen3.ko`, install it, and retry with the service parameters:

```
t1100_probe=0 t1100_rom_patch_mcif=0 t1100_pwr_on_done=1
t1100_readback=0 t1100_ready_rx=0 t1100_mcr_dump=0
```

Once the RAM code downloads, the next checkpoint is `wlan0` and
`iw dev`/`ip link` seeing the interface.

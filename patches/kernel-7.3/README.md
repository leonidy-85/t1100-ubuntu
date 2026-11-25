# Linux 7.3.6 for the Fplus T1100 (MT6771)

This directory publishes the complete out-of-tree 7.3.6 kernel work as a
reviewable patch series.  It is the 7.3 continuation of the 6.12.114 series in
`patches/` and adds the board, audio, sensors, USB, HDMI and GPU pieces that
are not in mainline.

## Base

    linux-7.3.6.tar.xz
    sha256 8183d475a76a0faffa92d6cd500af421f589dfd0300a0f1060bb875e11d45723

The first commit of the series is the pristine kernel.org tarball.

## Applying

    tar xf linux-7.3.6.tar.xz
    cd linux-7.3.6
    git init && git add -A && git commit -m 'linux 7.3.6'
    git am -3 /path/to/patches/kernel-7.3/*.patch

or, without git history:

    patch -p1 < 0001-...patch
    ...

The series has 71 commits and ends at `0aedddd0d` ("arm64: dts: t1100: nest
the OTG vbus regulator inside the charger node").

## Building

Use the project script (it also merges `configs/t1100.fragment` correctly;
do not run a bare `merge_config.sh`, it silently drops `CONFIG_ARCH_MEDIATEK`):

    KERNEL_SRC=/path/to/linux-7.3.6 \
    OUT=/path/to/out-7.3 \
    JOBS=$(nproc) scripts/build_kernel.sh

Toolchain used: `arm-gnu-toolchain-14.2.rel1` aarch64-none-linux-gnu.

## State

- Image `7.3.6-g5c6d1f8b9ce5` boots ALT Linux 2026.11 + Phosh from eMMC p54.
- USB gadget/RNDIS works (`mt6370` OTG vbus regulator is a child of the
  charger MFD node; see the last DTS patch).
- Audio MT6771+MT6358, fuel gauge, ALS/PS, IMU, cpufreq/thermal, GPU,
  HDMI IT66121, vcodec/SCP and dma-heap are ported.
- Wi-Fi/BT MT6631: the 7.3 vendor modules (`mtk_btif_drv`, `wmt_drv`,
  `wlan_drv_gen3`) build and load against a separate out-tree with
  `CONFIG_LOCALVERSION="-wifi1"`; firmware `WIFI_RAM_CODE_6759` is installed,
  but `kalFirmwareOpen()` still fails before firmware download.  This is the
  next bring-up item and is documented in the project repo.

See `docs/` in the project repo for the full bring-up log.

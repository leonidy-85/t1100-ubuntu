# MT6771 vendor `Vcodec` AP driver → mainline 6.12.114 port

Date: 2026-11-20
Tablet: `root@192.168.2.146`, kernel `6.12.114-wifi1`, tree `/root/kbuild/linux-6.12.114`.
No flashing, no p29/boot image change, no reboot.

## Result

| item | result |
|---|---|
| module compiles against 6.12.114 | **yes** (`KBUILD_MODPOST_WARN=1`) |
| module loads | **yes**, probe returns 0, no oops |
| `/dev/Vcodec` | **yes** (dynamic major 500 on this boot; major 160 attempted first) |
| `MFV_INIT_CMD` | **0** |
| `MFV_SET_PWR_CMD` (1 then 0) | **0**, hw_power=0 so no register access |
| `VCODEC_INITHWLOCK` / `DEINITHWLOCK` | **0** |
| `VCODEC_LOCKHW` / `UNLOCKHW` | **works** (vendor return 255), pm_runtime refcount 1→0 |
| `VCODEC_INC_PWR_USER` / `DEC_PWR_USER` | **works** (vendor return 255) |
| oops/WARN during ioctl tests | **none** |

Runtime log of a successful load:

```
[VCODEC] iomap VENC=... VDEC=... GCON=... irq dec=398 enc=0
[VCODEC] clocks from DT: vdec=ok larb1=ok venc=missing
[VCODEC] cannot create /sys/vcodec (non-fatal)
[VCODEC] cannot reserve major 160 (-16), using dynamic major
[VCODEC] char device /dev/Vcodec major=503 minor=0
[VCODEC] cannot request dec irq 398 (probably owned by mtk-vcodec-dec), continuing without ISR
[VCODEC] DT-less platform device, keeping clocks from init
probe of VcodecPort returned 0 after 491 usecs
```

Ioctl smoke test (`/tmp/vcodec_test`):

```
MFV_TEST_CMD             -> 0
MFV_INIT_CMD             -> 0
MFV_SET_CMD_CMD          -> 0
MFV_SET_PWR_CMD(1)       -> 0
MFV_SET_PWR_CMD(0)       -> 0
MFV_SET_ISR_CMD          -> 0
VCODEC_INITHWLOCK        -> 0
VCODEC_DEINITHWLOCK      -> 0
VCODEC_GET_CORE_NUMBER   -> 255 (vendor return, core_number=8)
VCODEC_MB                -> 0
MFV_DEINIT_CMD           -> 0
unknown ioctl            -> 255 (vendor default, no crash)
PASS: 0 failure(s)
```

## Build

Production module:

```sh
make -C /root/kbuild/linux-6.12.114 M=/root/vcodec-port \
     KBUILD_MODPOST_WARN=1 modules -j8
# -> /root/vcodec-port/vcodec_kernel_driver.ko
```

Live-test module (unique driver/class names because the first crashed probe
could not be unloaded without reboot):

```sh
# /root/vcodec-live/Makefile = Makefile.live
make -C /root/kbuild/linux-6.12.114 M=/root/vcodec-live \
     KBUILD_MODPOST_WARN=1 modules -j8
insmod /root/vcodec-live/vcodec_port.ko
```

`KBUILD_MODPOST_WARN=1` is required because this tree has no `Module.symvers`/
`vmlinux`; modpost therefore reports every core-kernel symbol as unresolved.
The symbols resolve normally at `insmod` from the running kernel
(`CONFIG_MODVERSIONS` is off).

## DT / hardware mapping used

- Live DT has a **root-level** `video-codec@16020000` node
  (`mediatek,mt8183-vcodec-dec`, IRQ 250 → virq 398, clocks `vdec`).
- `VDEC_MISC` = 0x16020000, `VDEC_VLD` = +0x1000; mapped 0x29000.
- `VDEC_GCON` = 0x16000000 (mapped by fallback; no vendor node in live DT).
- `VENC` = 0x17020000 (mapped, unused in this milestone).
- `vdec` and `larb1` gates acquired with `of_clk_get_by_name()` from
  `video-codec@16020000` and `/soc/larb@16010000` (`clk-mt8183-vdec` provider).
- VENC clock/IRQ 247 are absent from the live DT; left optional.
- IRQ 398 is held by `mtk-vcodec-dec` without `IRQF_SHARED`, so the vendor
  driver cannot request it in this boot. It logs and continues without ISR.

## Compile errors hit and fixes

1. `do_gettimeofday()` removed → `ktime_get_real_ts64()` in
   `common/val/src/val.c` and `common/drv/src/dvfs_v2.c`.
2. `class_create(THIS_MODULE, name)` → `class_create(name)` (6.4+ API).
3. `pud_offset(pgd, va)` type mismatch (p4d level) in the 4.14 page-table
   walk → replaced the whole `pmem_user_v2p_video()` with
   `follow_pfnmap_start()` (PFNMAP/ION) + `pin_user_pages_fast()` fallback.
4. `__pte_offset_map` is not exported → same replacement as (3).
5. `struct platform_driver.remove` must return `void` (was `int`).
6. `enc_cur_job` undeclared when `VCODEC_DVFS_V2` is off → forward declaration
   and hoisted pointer out of the `#ifdef`.
7. `compat_alloc_user_space()` removed in 6.12 → compat handler reduced to
   scalar/`MFV_*` commands; structure-carrying compat ioctls return `-ENOTTY`
   until the 32→64 conversion is ported.
8. `mmsys_cg_check()` and `smi_debug_bus_hanging_detect_ext2()` are declared
   `extern` in the vendor header; the stub header must not define them
   `static` (conflicting linkage).
9. `of_iomap(NULL, 0)` in module_init if a vendor DT node is absent → robust
   `of_address_to_resource()`/`ioremap()` fallback with stock MT6771 addresses.
10. `device_create()` on char major 160 returned `-EEXIST` after a previous
    crashed load left a stale device kobject; the probe now checks `IS_ERR()`
    and retries with a dynamically allocated major.
11. `unregister_chrdev_region()` used count 1 while `register_chrdev_region()`
    used 2 → leaked a major on every unload after the two-minor fix; both
    paths now unregister 2 minors.

## Compatibility stubs (`compat/`)

| file | provides |
|---|---|
| `mt-plat/dma.h` | includes `<linux/dma-mapping.h>` |
| `mt-plat/sync_write.h` | `mt_reg_sync_writel/readl` → `writel/readl` |
| `smi_public.h` | `SMI_LARB*`, `smi_bus_prepare_enable/disable_unprepare` no-ops |
| `mtk_smi.h` | includes `smi_public.h` |
| `mmdvfs_pmqos.h` | MTK PM-QoS class IDs, `MAX_FREQ_STEP`, `MMDVFS_VOLTAGE_*`, `mmdvfs_qos_get_freq_steps()` stub (−ENODEV) |
| `mmdvfs_config_util.h` | includes `mmdvfs_pmqos.h` |
| `mach/mt_clkmgr.h` | includes `<linux/clk.h>` |
| `vcodec_compat.h` | `get_detect_count()` / `set_detect_count()` no-ops |

`CONFIG_MTK_QOS_SUPPORT` is intentionally **not** defined, so the MTK
`pm_qos_add_request()`/`pm_qos_update_request()` code (removed upstream) is
compiled out. `VCODEC_DVFS_V2` is therefore also off.

## Source changes

- `Makefile` — external-module kbuild file replacing the vendor in-tree one.
- `mt6771/videocodec_kernel_driver.c` — 6.12 APIs, optional DT/clock/IRQ,
  DT-less platform device, `/dev/Vcodec` creation with major-160/dynamic
  fallback, MFV ioctl handlers, class/device cleanup, `hw_power` parameter.
- `videocodec_kernel.c` — `pmem_user_v2p_video()` rewrite for 6.12.
- `mt6771/common/val/src/val.c` — `do_gettimeofday` → `ktime_get_real_ts64`.
- `mt6771/common/drv/src/dvfs_v2.c` — same.
- `videocodec_kernel.h` — include `<linux/types.h>`.
- Full unified diff: `PORT-DIFF.txt`.

Runtime-tunable module parameters:

- `hw_power=0|1` — allow `MFV_SET_PWR_CMD` to enable clocks/touch VDEC
  registers (default 0; real power/register access not yet validated).
- `class_name=`, `class_name2=` — override the sysfs class names.

## System-state side effect (important)

During the first bring-up attempt the probe crashed on `device_create()`'s
`ERR_PTR(-EEXIST)` (`vcodec_device->pm_domain` store), and the oops left the
platform device's `device_lock` held. Consequences on the **current boot**:

- the first `vcodec_kernel_driver` module cannot be unloaded
  (`/sys/module/vcodec_kernel_driver/refcnt = 1`), and one `bash` process is
  stuck in `D` state in `device_release_driver_internal`;
- char major **160** and classes `Vcodec`/`Vcodec2`/`VcodecAP` and
  `/sys/vcodec` remain owned by that module;
- repeated test loads also leaked dynamic majors 501–508 because the exit
  path unregistered 1 minor while the probe reserved 2; this is fixed in the
  final source (`unregister_chrdev_region(devno, 2)`), but the already-leaked
  entries need a reboot to clear;
- therefore the live test uses `vcodec_port.ko` with driver name
  `VcodecPort`, classes `VcodecLive*`, and a **dynamic** major (500).

The production module (`vcodec_kernel_driver.ko`, driver `Vcodec`, classes
`Vcodec`/`Vcodec2`, `/dev/Vcodec` on major **160**) will take 160 on a clean boot.
If those class names are already taken it falls back to `VcodecPort`/`VcodecPort2`.
A reboot is required only to clear the leaked kobjects/major and the D-state
task; it was **not** done.

## Not done / next steps

- `hw_power=1` path: attach to the VDEC genpd (e.g. via the existing
  `16020000.video-codec` device) before enabling gates/writing registers.
- Request IRQ 250: needs `mtk-vcodec-dec` unbound or an IRQ-sharing design.
- VENC: DT node/IRQ 247 mapping missing on this board.
- 32-bit compat structure conversion for `VCODEC_LOCKHW`, `WAITISR`,
  `INC/DEC_PWR_USER`, `SET_FRAME_INFO` (currently `-ENOTTY`).
- Buffer allocation is intentionally absent (matches vendor source: no
  `dma_alloc`/`ion_`/`m4u`; HAL uses `/dev/ion`).

## 23.11.2026 — состояние после дня отладки (AP-side VDEC)

Что работает на железе (планшет 172.17.141.157, ядро 6.12.114-wifi1):
- модуль `vcodec_kernel_driver` собран под точный конфиг живого ядра
  (`/home/l/live-out`, vermagic `6.12.114-wifi1`), без правки байтов;
- `mtk-vcodec-dec` отвязан (`echo 16020000.video-codec > .../unbind`),
  вендорский модуль получает IRQ 400 (`MT_SYSIRQ 250`, Level);
- `compat LOCKHW ret=0` — 32-битный ABI HAL проходит целиком;
- аллокатор: `VCODEC_ALLOC_NON_CACHE_BUFFER` → `alloc_pages` + реальный PA,
  `mmap` по `virt_to_phys(kva)` с `pgprot_writecombine` (SIGBUS ушёл);
- ION-шим `tools/ionshim_vc.c` → `libionshim_vc4.so`: ALLOC через Vcodec,
  page-align mmap, defer-free, alias-чистка; HAL видит `pa=` и пишет в буферы.

Где стоит:
- `Vdec_Drv_H264_decodeEx` доходит до железа, но поток не разбирается:
  `Fail to parse Slice header data structure` (hw_power=1) /
  `Fail to Fetch Barrel shifter` (hw_power=0), кадров нет;
- затем вендорский HAL падает SIGSEGV: пойман `addr=0x0 pc=0x0` — вызов
  через NULL-указатель, `lr=0xf5dbcfeb`, `r2=0x2`, `r3=0xf66c3080`;
  библиотека по `lr` пока не определена (нужен дамп `/proc/self/maps`
  в момент падения: `tools/device/crashinfo.c`, см. /tmp/opencode).

В DT `video-codec@16020000` (`mediatek,mt8183-vcodec-dec`) **нет `iommus`** —
VDEC работает без IOMMU, версия «нужен MVA» отпадает. Есть
`power-domains = <0x47 0x0a>` и `clocks = <0x71 0>` (имя `vdec`);
genpd-путь в модуле реализован (`vcodec_vdec_genpd_get`).

Следующие шаги: (1) поймать `lr`-регион через дамп maps в обработчике
SIGSEGV; (2) сравнить формат AU/CSD с тем, что HAL отдаёт на эталонном
Android (там `/dev/Vcodec` живой и `media.codec` работает);
(3) при подтверждении — добить парсер/формат, затем собрать YUV.

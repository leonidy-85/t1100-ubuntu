# GPU (Mali-G72 MP3) через panfrost: что включает патч 0039 и что осталось

Итерация 09.11.2026, агент `gpu-mesa`. **Обновление 10.11: образ прошит —
panfrost 1.2.0 поднялся, Mesa 25.0.7 даёт GLES 3.1 (`kmscube` 56.4 fps,
`glmark2` Score 452), см. `docs/STATUS.md` 10.11 (3)–(5).** **Обновление 13.11:
DVFS включён (0058/0059) — coupler MT6771/MT8788, high-OPP 698/743/800,
VGPU/VSRAM spread 100 мВ; devfreq `simple_ondemand`, `glmark2` Score 1409/1583;
в отдельных shader-сценах — таймаут panfrost (не DVFS), см. 13.11 (1).** Всё ниже — факты из
дерева, публичных исходников и дампов со стоковой прошивки; предположения
помечены явно.

| Артефакт | Значение |
|---|---|
| ядро | `6.12.114-geed4580b9b` (build-хост, `scripts/build-kernel-remote.sh`) |
| `Image` sha256 | `157fe51334a3a5a8bdebdb0b80144617f7f0b20ac947245d0990dd258534825d` |
| DTB sha256 | `0eaf6dff7784d1bef795b8ab057169e4872aa99e9e7598df24d8dd8673fbc0a4` (52 439 Б) |
| образ | `build/boot_ubuntu28.img`, 33 554 432 Б |
| boot sha256 | `0ae1c4b51daddb01342b6f76907c8119eb62163fba412096bdef844570bc12f8` |
| boot md5 | `d822a2ac032f5fb83fe96fdb2e27c8e3` |
| содержимое | kernel 14 548 052 + ramdisk `initramfs_root_usb.cpio.gz` 1 033 291 + DTB 52 439 |
| cmdline | как в `boot_ubuntu27` (ref-образ переиспользован целиком) |
| LK | `tools/lk/verify-dtb.sh` → `RESULT: validator passed` |

## 1. Что изменено (patch 0039, коммит `eed4580b9`)

Один файл — `arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dts`, блок `&gpu`:

```diff
 &gpu {
 	mali-supply = <&mt6358_vgpu_reg>;
-	sram-supply = <&mt6358_vsram_gpu_reg>;
-	status = "disabled";
+	/delete-property/ operating-points-v2;
+	status = "okay";
 };
+
+/* Only the GPU used it; leaving it behind would invite a DVFS enable by accident. */
+/delete-node/ &gpu_opp_table;
```

Плюс переписан комментарий блока и добавлен комментарий к рельсам
`VGPU`/`VSRAM_GPU` (границы 625–900 мВ / 850–1000 мВ = то, что оставляет
загрузчик и что допускает PMIC).

Diff готового DTB против DTB из `boot_ubuntu27`: только `gpu@13040000`
(`status` disabled→okay, минус `operating-points-v2`, минус `sram-supply`),
минус узел `opp-table-0` (≈1 КБ) и перенумерация phandle ниже по дереву.
Все остальные узлы (дисплей, MMSYS/DSI, LARB/SMI, PMIC) не тронуты.

## 2. Чего «не хватало» на самом деле: инвентаризация узлов

Всё GPU-описание приходит из `mt8183.dtsi` через `mt6771.dtsi`
(`#include "mt8183.dtsi"`), поэтому новых узлов писать не пришлось.

| Что | Есть? | Откуда / почему |
|---|---|---|
| `gpu@13040000`, `mediatek,mt8183b-mali` + `arm,mali-bifrost` | наследуется | mt8183.dtsi:1642; адрес и SPI 278/279/280 совпадают со стоковым `mali@13040000` (`refs/stock-mt6771.dts`) |
| `clocks = <&mfgcfg CLK_MFG_BG3D>` | наследуется | гейт `0x13000000`, драйвер `clk-mt8183-mfgcfg` (`need_runtime_pm`: включает PD MFG_ASYNC перед доступом к регистрам). В логе стоковой загрузки `13000000.syscon` уже успешно пробиндился (один `-517`, затем `0`) |
| `mfg@13fff000` / `mfg_async` | **не нужен** | ни в mainline, ни в биндингах такого узла нет (в mainline нет вообще `mediatek,mfg`; `0x13fff000`/`0x13020000` — вендорные тест/DFV-блоки без драйверов). Иерархия MFG — это 5 power-domain'ов в `spm`, см. ниже |
| `mfgcfg` (syscon `0x13000000`) | наследуется | `mediatek,mt8183-mfgcfg`; в стоковом DT тоже `mfgcfg@13000000` с `#clock-cells` |
| power-domains `core0/core1/core2` + родители `mfg_async`→`mfg` | наследуется | mt8183.dtsi:1653; `domain-supply` для `&mfg_async`/`&mfg` уже стоял в board DTS (иначе `scpsys_probe()` падал, см. STATUS 30.10) |
| OPP-таблица частот/напряжений | **наследуется, но отключена** | mt8183 `gpu_opp_table` 300–800 МГц / 625–825 мВ; vendor-таблица MT6771 совпадает в верхней точке (800 МГц / 825 мВ). Отключена сознательно — см. §3 |
| SVS / nvmem `speed-bin` | не нужен | `panfrost_read_speedbin()`: `-ENOENT` = «на платформе нет speedbin»; `&svs` в `mt6771.dtsi` намеренно `disabled` |
| IOMMU (`&iommu`, larb) | не нужен | у panfrost свой MMU внутри блока; в mt8183 GPU-узел без `iommus` (в отличие от MMSYS/larb). IOMMU-узел используется дисплеем и не трогается |
| `resets` | не нужен | `panfrost_reset_init()` — optional (`devm_reset_control_array_get_optional_exclusive`); на mt8183 их нет |
| `interrupt-names = job/mmu/gpu` | наследуется | порядок SPI 280/279/278 совпадает со стоковым `GPU/MMU/JOB` (0x116/0x117/0x118) |
| `CONFIG_DRM_PANFROST=y` | стоит давно | `configs/t1100.fragment:100`; в собранном ядре 129 символов `panfrost*` в `System.map` |

Почему это должно работать на MT6771 (публичные источники, без TRM):

1. `refs/affenull-mt6771` — mainline-порт MT6771 (PennyOS на Planet Cosmo):
   `&gpu` включён по умолчанию, из свойств только `mali-supply`.
2. `refs/mt6771-next` — WIP-порт **этого же** планшета (Arseniy Velikanov,
   base 6.16): то же самое, `&gpu { mali-supply }` без `status`.
3. Вендорный `gpufreq` перечисляет ровно те пять MTCMOS, что и mt8183:
   `mtcmos_mfg_async`, `mtcmos_mfg`, `mtcmos_mfg_core0`, `mtcmos_mfg_core1`,
   `mtcmos_mfg_core2` — значит набор и порядок MFG-доменов совпадает.
4. Домены MFG **уже включаются на каждом буте** (см. §4): `mtk-pm-domains`
   на probe поднимает все домены, не помеченные `KEEP_DEFAULT_OFF`. В
   `refs/device/dmesg-exp38-default-path.txt.gz` нет ни одного
   «failed to power on domain», т.е. `ctl_offs` 0x0334/0x0338/0x034c/0x0310/
   0x0348, `pwr_sta_offs` 0x180 и release bus-protection для MFG_2D на
   MT6771 отрабатывают без ошибок. Это самое сильное офлайн-доказательство,
   что scpsys-таблица mt8183 применима.

## 3. Почему DVFS выключен (и как его включить)

Стоковый лог 4.14 (`refs/device/dmesg-stock.txt.gz`) печатает и состояние
рельсов, и вендорную OPP-точку:

```
[GPU/DVFS] __mt_gpufreq_pdrv_probe: gpufreq driver probe, clock is 512001 KHz
[GPU/DVFS] VGPU is enabled = 1 (900 mV), VSRAM_GPU is enabled = 1 (1000 mV)
[GPU/DVFS] current freq = 800000 KHz, current volt = 825000 uV,
           g_cur_opp_volt = 82500, g_cur_opp_vsram_volt = 92500
```

То есть вендор **всегда двигает VSRAM_GPU на 100 мВ выше VGPU** (0.825/0.925 В
на верхней точке) — это тот же предел, что в `mt8183-kukui.dtsi` записан как
`regulator-coupled-max-spread = <100000>`.

У нас связать рельсы нечем:

- `mediatek,mt8183b-mali` знает **один** supply (`mali` = VGPU), VSRAM драйвер
  не запрашивает;
- generic coupler в mainline принимает только *always-on* регуляторы
  (`regulator/core.c`: «Coupling of a non always-on regulator is
  unimplemented»), а `mt6358_regulator_probe()` падает на первой такой
  ошибке — именно это в 30.10 оставило без питания eMMC/USB/MMSYS.

Поэтому с OPP-таблицей `simple_ondemand` на простое опустил бы VGPU до
625–700 мВ, оставив VSRAM на 1000 мВ: расхождение 300–375 мВ там, где
железо допускает 100. Без OPP-таблицы panfrost уходит в ветку
`panfrost_regulator_init()`: включает VGPU на том напряжении, что оставил
загрузчик (900 мВ), VSRAM остаётся 1000 мВ (пара ровно как у вендора),
`clk_set_rate` не вызывается вообще.

Цена: GPU работает на частоте, которую оставил LK/`mfg_sel`. В стоковом логе
`clk_get_rate` до вмешательства gpufreq = **512 МГц** — этого достаточно для
GBM/EGL/GLES-bring-up. Проверить на устройстве:
`cat /sys/kernel/debug/clk/clk_summary | grep -i mfg` и строка
`panfrost 13040000.gpu: clock rate = ...` в dmesg.

Как вернуть DVFS (отдельный патч, после проверки GPU):

1. либо реализовать в DTS связку VGPU↔VSRAM (±100 мВ) с **обоими**
   `regulator-always-on` и перепроверить, что `mt6358-regulator` не падает;
2. либо оставить OPP только с верхней точкой (800 МГц / 825 мВ) и прибить
   VSRAM к 925 мВ, чтобы расхождение не превышало 100 мВ;
3. либо добавить в panfrost второй supply для MT6771 (`mali`+`sram`) — это
   код ядра, не DTS.

## 4. Что физически произойдёт при включении узла

Порядок в `panfrost_device_init()` (drivers/gpu/drm/panfrost):

1. `panfrost_clk_init()` — `devm_clk_get(dev, NULL)` → гейт `mfg_bg3d`,
   `clk_prepare_enable()`. Гейт живёт в PD MFG_ASYNC; `clk-mt8183-mfgcfg`
   (`need_runtime_pm`) сам поднимет домен через runtime PM. Доступ к
   регистрам `0x13000000` происходит только после этого.
2. `panfrost_devfreq_init()` — `operating-points-v2` нет → `-ENODEV` →
   «continue without devfreq», devfreq/OPP не создаются, `clk_set_rate` не
   вызывается.
3. `panfrost_regulator_init()` — `regulator_bulk_enable("mali")`: VGPU
   включается на 900 мВ (регистратора напряжения никто не меняет).
4. `panfrost_reset_init()` — у узла нет `resets`, это no-op.
5. `panfrost_pm_domain_init()` — три `dev_pm_domain_attach_by_name(core0/
   core1/core2)` + `device_link_add(DL_FLAG_RPM_ACTIVE)`: MFG_ASYNC→MFG→
   CORE0/CORE1/2D поднимаются (VGPU при этом включается ещё и как
   `domain-supply` домена `mfg`).
6. `devm_platform_ioremap_resource(0)` → `panfrost_gpu_init()`: soft reset
   GPU, чтение `GPU_ID`/фич, запрос трёх IRQ.
7. `panfrost_mmu_init()`, `panfrost_job_init()`, `drm_dev_register()` —
   появляется **render-node** (`DRIVER_RENDER`, `DRIVER_MODESET` в
   `driver_features` нет).

Важное следствие: `/dev/dri/card0` остаётся у `mediatek-drm`, panfrost даёт
`/dev/dri/renderD128`. Это влияет на kmscube/Wayland (фаза 3): EGL/GBM нужно
уговорить брать буферы у render-node, а режим выставлять на card0.

## 5. Офлайн-риски и сценарии отказа

| # | Риск | Что произойдёт | Признак в dmesg | Влияние на дисплей |
|---|---|---|---|---|
| 1 | VGPU/VSRAM не готовы (mt6358 ещё не пробиндился) | `-EPROBE_DEFER`, panfrost пробуется позже | `probe of 13040000.gpu returned -517` | нет |
| 2 | PD-провайдер/clock-провайдер не готовы | `-EPROBE_DEFER` | то же | нет |
| 3 | Неверные `ctl_offs` MFG | `readx_poll_timeout` не дождётся ACK → probe fail; пишутся биты в чужой регистр SPM (могут включить/выключить неиспользуемый блок: VDE/VENC/ISP) | `mtk-pm-domains ...: failed to power on domain: -110` | маловероятно: DISP уже поднят и живёт отдельным `ctl_offs` 0x030c; MFG-домены и сейчас включаются на probe без ошибок (§2.4) |
| 4 | Неверные `sta_mask`/`sram`-биты для MFG | тот же таймаут/ошибка, что #3 | `-110` | нет |
| 5 | Bus-protection MFG_2D (`TOP_AXI_PROT_EN_1_MFG`) на MT6771 не тот | шина MFG может остаться заблокированной → таймауты в probe | `-110`, `failed to power on domain` | те же регистры `infracfg` уже используются доменом DISP, который работает → риск низкий |
| 6 | Частота `mfg_sel`/`MFGPLL` другая (или PLL выключен) | GPU отвечает медленно/не отвечает: soft-reset timeout, чтение ID = 0 или 0xffffffff | `gpu soft reset timed out`, `mali-unknown id 0x…`, «Fatal error during GPU init» | нет: clk_set_rate не вызывается, PLL/мультиплексор не перепрограммируются |
| 7 | Гейт `mfg_bg3d` (bit 0, `0x13000000`) просыпается не тем битом | доступ к `0x13040000` даёт SNoC hang (зависание шины = зависание платы, лога нет) | — | **единственный сценарий, опасный для всей платы** |
| 8 | GPU-регистры на MT6771 отличаются от G72 r0p3 | probe fail после частичной инициализации | `mali-unknown`, «Fatal error during GPU init» | нет |
| 9 | Всё хорошо, но нет OPP → нет devfreq | GPU всегда на частоте загрузчика; `/sys/class/devfreq/13040000.gpu` не появится | — | нет |

Итог по риску для уже работающего дисплея: MFG и DISP — разные домены и
разные клоки, общий у них только `spm`/`infracfg`-regmap, который сейчас
используется и работает. SMI/LARB дисплея GPU не затрагивает (у GPU нет larb).
Единственный реально опасный исход — #7 (зависание AXI при доступе к
выключенному блоку) и #3 при совсем неверных смещениях.

### Если после прошивки плата не поднимается

Порядок восстановления (тот же, что в `docs/boot-test.md`):

1. выключить/перезагрузить удержанием Power; при чёрном экране — вход в
   recovery (Vol+ + Power), как в `../t1100`;
2. `dd` обратно `build/boot_ubuntu27.img` (sha256
   `a89b264d31b7ef91d23a4f3dd12af50495b4bf599cd6d6096c34b1e73cbe8283`) в
   `boot_a` (`/dev/mmcblk0p29`), проверить sha;
3. `boot_a` не трогали ничем другим — DTB/ядро целиком внутри boot.img.

Если ядро дошло до pstore, лог будет в
`/sys/fs/pstore/console-ramoops` — искать `panfrost`, `mtk-pm-domains`,
`genpd`.

## 6. Ожидаемые строки dmesg (первая загрузка)

```
13000000.syscon: probe ... 0                     (уже есть сегодня)
panfrost 13040000.gpu: clock rate = 512001000    (значение = rate от LK)
panfrost 13040000.gpu: mali-g72 id 0x6001 major 0x0 minor 0x0 status 0x3
panfrost 13040000.gpu: features: ...             (bitmap)
panfrost 13040000.gpu: Features: L2:0x… Shader:0x… Tiler:0x… Mem:0x… MMU:0x… AS:0x… JS:0x…
panfrost 13040000.gpu: shader_present=0x7 l2_present=0x1     (MP3)
```

`id 0x6001` и `shader_present=0x7` — G72 MP3 (id берётся из `GPU_ID >> 16`,
таблица `gpu_models[]` в `panfrost_gpu.c`). Если вместо этого `mali-unknown`,
`error powering up gpu shader/L2/tiler` или `Fatal error during GPU init`,
см. §5 (#6/#8).

Ошибок быть не должно; в частности **не** ожидается
`failed to power on domain`, `Failed to get regulators`, `Can't get clock`.

## 7. Проверка на устройстве (когда планшет вернётся; по SSH)

```sh
# 0) прошивка (пример, НЕ выполнять без бэкапа и без разрешения лида)
#    md5 d822a2ac032f5fb83fe96fdb2e27c8e3
#    tools/host/flash-ssh.sh build/boot_ubuntu28.img /dev/mmcblk0p29 --reboot

# 1) ядро и версия
uname -r                                   # 6.12.114-geed4580b9b
dmesg | grep -iE "panfrost|mali|bifrost"

# 2) устройства DRM
ls -l /dev/dri                             # card0 (mediatek), renderD128 (panfrost)
cat /sys/class/drm/card0-DSI-1/status      # connected  (дисплей не должен сломаться)
ls /sys/kernel/debug/dri                   # 0 -> card0, 128 -> renderD128
cat /sys/kernel/debug/dri/128/name         # panfrost
ls /sys/kernel/debug/dri/128              # name, clients, gem_names (своих файлов у panfrost нет)

# 3) питание и клоки
grep -iE "vgpu|vsram_gpu" /sys/kernel/debug/regulator/regulator_summary
cat /sys/kernel/debug/clk/clk_summary | grep -i mfg
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary | grep -i mfg

# 4) прерывания GPU (появятся три строки 13040000.gpu)
grep -i gpu /proc/interrupts

# 5) отпечаток GPU из userspace (Mesa ещё не собрана — пока только node)
#    после сборки Mesa: es2gears_x11 / glmark2-es2-drm / kmscube
```

`/sys/class/devfreq/13040000.gpu` **не появится** — это ожидаемо при
выключенном DVFS (§3).

## 8. Дальше (фаза 3, не в этой итерации)

1. **Mesa с panfrost** под aarch64 на build-хосте: `meson`/`ninja`/`bison`/
   `flex` там есть, libdrm 2.4.131; нужен aarch64-sysroot (см.
   `docs/cross-build.md`, раздел про `build-tools-aarch64.sh`) + `libwayland`,
   `wayland-protocols`, `libx11`/`libxcb` (для `es2gears_x11`) или сборка
   `kmscube`/`es2gears_drm`. Версию Mesa фиксировать в этом файле.
2. Проверить `eglinfo`/`glxinfo`: `OpenGL renderer string: Mali-G72 (Panfrost)`
   и что драйвер не `llvmpipe`.
3. `glmark2-es2-drm`/`kmscube` — учесть, что panfrost **render-only**
   (`/dev/dri/renderD128`), а режимы выставляет `card0` (mediatek-drm):
   возможны варианты `-D /dev/dri/card0` с `EGL_PLATFORM=gbm` и
   `MESA_LOADER_DRIVER_OVERRIDE=panfrost`, либо compositor (KWin/Weston),
   который сам разводит KMS и GPU. Это первый вопрос, который надо решить
   после того, как panfrost поднимется.
4. Решить DVFS (§3) и только потом включать OPP-таблицу обратно.

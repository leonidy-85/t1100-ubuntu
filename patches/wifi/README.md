# patches/wifi — патчи к вендорским исходникам, НЕ к ядру

Эти патчи **не применяются к `../linux-t1100`** и не входят в `patches/series`
(там серия патчей ядра). Они применяются к чистым клонам вендорского
connectivity-стека MediaTek (Motorola Pie-9):

```
common   github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common
         Pie-9-release-POBS @ 3ff67212dcc45757c434ca5e1d35161c73ad7f55
wlan     github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-core-gen3
         Pie-9-release-POBS @ 249649d877d87a151525c3c5629709eba337d2bd
```

Применение (`patch -p1` из корня соответствующего дерева) делает
`scripts/remote/build-wifi-remote.sh` в каталоге на build-хосте. Локально патчи
генерировались как `git diff` «чистый клон → портированное дерево»; никакой
вендорский код в этот репозиторий не копируется.

Логика порта и список правок по темам — `docs/wifi-port-log.md`, §18.

## Текущий набор

| файл | дерево | что делает |
|---|---|---|
| `0001-common-port-6.12.patch` | `common` | порт WMT-ядра 4.14 → 6.12 (API, probe/driver_unregister, CCF-заглушки) |
| `0002-common-consys-power-on-dt.patch` | `common` | питание CONSYS из mainline-DT (регуляторы/`of_iomap`/IRQ) |
| `0004-common-export-wmt-plat-pwr-ctrl.patch` | `common` | `EXPORT_SYMBOL(wmt_plat_pwr_ctrl)` — чтобы WLAN мог питать чип в обход STP |
| `0005-common-consys-spm-power-on.patch` | `common` | питание CONN по-настоящему: SPM-последовательность, когда клока `conn` нет (mainline), и корректная снятие AXI-protect (`0x100012a4` — write-1-to-clear) |
| `0001-wlan-port-6.12.patch` | `wlan` | порт gen3 4.14 → 6.12 |
| `0002-wlan-port-6.12-vendor-commands.patch` | `wlan` | выключены MTK vendor-команды (`wiphy_register` требует `.policy`) |
| `0003-wlan-t1100-probe-param.patch` | `wlan` | модульный параметр `t1100_probe=1`: питание чипа + `wlanProbe()` из `initWlan` (M6) |
| `0006-wlan-probe-stage-and-no-reset.patch` | `wlan` | пошаговый прогон: `t1100_probe_stage` (1 = только питание), `t1100_no_reset` (не дёргать whole-chip reset) и `glResetInit()` **до** probe — иначе `GL_RESET_TRIGGER` планирует неинициализированный work (NULL-вызов в kworker = смерть ядра) |
| `0007-wlan-fw-download-debug.patch` | `wlan` | печать таблицы секций divided-download (dest/len/off) + включение гейта `wifi-dma` (`infra_cqdma`) в `HifDmaInit` с логом в `pr_info` |
| `0008-wlan-override-fw-start-address.patch` | `wlan` | MCIF-диагностика (return-коды `wlanImageSectionConfig`/`WIFI_START`, полный дамп MCR-страницы `0x180f0000`) + `CFG_OVERRIDE_FW_START_ADDRESS=1`: `WIFI_START` идёт с `override=TRUE` и адресом из DT (`hardware-values[2] = 0xa5800`), иначе чип просят стартовать «по умолчанию» — а это работает только с ROM-patch, залитым через STP |
| `0009-common-mt6771-rom-patch.patch` | `common` | ROM-patch MCU для MT6771: читает `/lib/firmware/soc3_0_ram_mcu_e1_hdr.bin`, разбирает `struct wmt_rom_patch` (48 Б: `u4PatchAddr=0xf0000000`, `u4PatchType=0x4000000`, `PLat="ALPS"`, Hw/Sw=0x108a) и кладёт тело (165 296 Б) в EMI через `osal_memcpy_toio` (`patchAddr & 0xfffff` = EMI+0), как `mtk_wcn_soc_rom_patch_dwn()`. Вызывается из `polling_consys_chipid()` (как в `mt6765.c:681`). **Пока без эффекта**: MCU к этому моменту уже вышел из сброса и патч не подхватывает (см. §33) |
| `0010-common-mt6771-rompatch-before-reset.patch` | `common` | перенос записи ROM-patch внутрь `consys_hw_power_ctrl_spm()` (между снятием изоляции и снятием сброса) + печать `cpupcr` сразу/+50/+100 мс после сброса; вызов из `polling_consys_chipid()` убран |
| `0011-common-mt6771-romdesel-after-reset.patch` | `common` | перепрошивка `CONSYS_ROM_DESEL` (`0x18070600 = 0x1702a4`) уже **после** снятия CPU SW reset + печать `cpupcr` сразу и через 20 мс (видно, что MCU стартует с `0x1170`, а не с RAM `0xa5800`) |
| `0012-common-xo-wcn-clock-buffer.patch` | `common` | `consys_clock_buffer_ctrl()` больше не no-op: включает XO_WCN (26 МГц референс MT6631) тремя записями — `MT6358 DCXO_CW00[4:3] = WCN_EN_M`, `TOP_SPI_CON1` бит0 `RG_SRCLKEN_IN3_EN`, AP-сторонний `pwrap+0x184` бит1 `DCXO_CONN_ENABLE`. regmap PMIC берётся у pwrap-устройства (`of_find_compatible_node("mediatek,mt8183-pwrap")` → `of_find_device_by_node` → `dev_get_regmap`) |
| `0012-common-mt6771-spm-pwron-confg.patch` | `common` | `consys_hw_spm_clk_gating_enable()` (у вендора пустая, только комментарий) пишет `CONSYS_PWRON_CONFG_EN_VALUE = 0x0b160001` в `SPM+0`; на железе регистр принимает только бит0 (`0x3 -> 0x1`), т.е. это не гейт CONN main — попытка зафиксирована и безвредна |
| `0011-common-default-chip-type-soc.patch` | `common` | `wmt_detect_get_chip_type()` возвращает `WMT_CHIP_TYPE_SOC`, если тип никто не выставил (в mainline нет userspace `wmt_loader`, который зовёт `COMBO_IOCTL_SET_CHIP_ID`). Без этого `wmt_plat_init()` уходил в SDIO-combo ветку, `mtk_wcn_consys_hw_init()` не вызывался, и platform-драйвер `mediatek,mt6771-consys` не регистрировался вовсе (в `/sys/bus/platform/drivers` пусто) |

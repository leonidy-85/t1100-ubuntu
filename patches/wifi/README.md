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

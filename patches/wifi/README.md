# patches/wifi — вендорский connectivity-стек MT6771 под mainline 6.12

Все патчи применяются к **чистым** клонам Motorola Pie-9
(`vendor/{common,wlan}` на build-хосте) скриптом
`scripts/build-wifi-remote.sh` — он каждый раз пересоздаёт `work/` из
`vendor/` + этого каталога. **Правки, сделанные прямо в `work/`, теряются при
следующем прогоне** (это случилось в M41) — всё, что должно жить, лежит здесь.

Порядок применения — по имени (`0001` → `0013`), для common и wlan отдельно.

## common (wmt_drv.ko)

| патч | зачем |
|---|---|
| `0001-common-port-6.12.patch` | порт 4.14 → 6.12 (API, вызовы, заголовки); заглушка `KERNEL_clk_buf_ctrl` (XO_WCN не включался — см. `0012`) |
| `0002-common-consys-power-on-dt.patch` | CONSYS power-on через наши DT-узлы (`vcn18/vcn28/vcn33-supply`, `memory-region`) |
| `0004-common-export-wmt-plat-pwr-ctrl.patch` | экспорт `wmt_plat_pwr_ctrl()` для `wlan_drv` |
| `0005-common-consys-spm-power-on.patch` | SPM-последовательность включения домена CONN (`0x1000632c`), `CONSYS_PWR_ON_OFF_API_AVAILABLE=0` |
| `0009-common-mt6771-consys-rompatch.patch` | EMI-путь ROM-патча (диагностика, по умолчанию off) |
| `0010-common-btif-stp.patch` | STP-over-BTIF: `stp_btif.o` в Kbuild, `t1100_btif_stp` (HIF_CONF+PWR_ON после `WMT_init`), `t1100_rom_patch` — ROMv4-патч из `/lib/firmware` |
| `0011-common-default-chip-type-soc.patch` | `INVALID` chip-type трактуется как SOC для MT6631 |
| `0012-common-xo-wcn-clock-buffer.patch` | `XO_WCN`/`DCXO_CONN_ENABLE` (MT6358 `DCXO_CW00`, `TOP_SPI_CON1`, pwrap `0x184`) |
| `0013-common-rom-patch-from-firmware.patch` | multi-patch-путь берёт файл из `/lib/firmware` (без `srh_patch`), `patch_num=1`, последний фрагмент без ожидания EVT (+100 мс) |

## wlan (wlan_drv_gen3.ko)

| патч | зачем |
|---|---|
| `0001-wlan-port-6.12.patch` | порт gen3-драйвера 4.14 → 6.12 |
| `0002-wlan-port-6.12-vendor-commands.patch` | `vendor_commands[].policy` — WARN при `wiphy_register` (M5) |
| `0003-wlan-t1100-probe-param.patch` | `t1100_probe` — probe на module init |
| `0006-wlan-probe-stage-and-no-reset.patch` | `t1100_probe_stage`, `t1100_no_reset` |
| `0007-wlan-fw-download-debug.patch` | отладочный вывод загрузки FW |
| `0008-wlan-override-fw-start-address.patch` | адрес старта FW из DT (`hardware-values`) |
| `0009-wlan-query-status-and-two-start.patch` | `wlanImageQueryStatus()`, два `WIFI_START`, дамп WCIR/`cpupcr` |
| `0010-wlan-pwr-on-done.patch` | `t1100_pwr_on_done` — не поднимать CONSYS повторно, если его поднял `wmt_drv` |

## BTIF-драйвер (отдельный модуль)

| файл | зачем |
|---|---|
| `0010-btif-mt6771-glue.patch` | правки публичного порта BTIF: без DT (базы/IRQ параметрами), sysirq-маппинг IRQ (SPI 114/139/140), фикс PIO (`p_rx_dma` NULL), печать before/after `hw_init` |
| `scripts/remote/m23-btif/m23_board.c` | glue: platform device, гейты INFRACFG_AO (**CLR** — на MT6771 бит «CG» = 1 закрывает клок), дампы |

## Как пересобрать с нуля

```sh
scripts/build-btif-remote.sh                     # mtk_btif_drv.ko
KERNEL_OUT=/home/l/t1100-merge2-out \
LOCALVERSION=-g400cb6f-touch-rot \
    scripts/build-wifi-remote.sh                 # wmt_drv.ko + wlan_drv_gen3.ko
```

## Утрачено при пересборке (M33–M41) — переносить сюда

Правки жили только в `work/` и были стёрты пересборкой; их сценарии сохранены в
`scripts/remote/m23-btif/worktree-edits/`:

* `m32.py` — best-effort `WMT reset` + защита `WMT_STAT_STP_*` при
  `t1100_patch_active`;
* `m35.py` — подавление `wmt_core_trigger_assert()` на время патча + readback;
* `m38.py`/`m40.py` — STP-reinit после патча, `patch_hdr_len`;
* `m41_responder.py` — «ответчик» `srh_patch` в ядре (начато).

Их надо оформить как `0014-common-rom-patch-delivery.patch` (после вывода
`reverse-engineer`), а не держать в `work/`.

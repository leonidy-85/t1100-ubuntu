# patches/wifi — вендорский connectivity-стек MT6771 под mainline 6.12

Все патчи применяются к **чистым** клонам Motorola Pie-9
(`vendor/{common,wlan}` на build-хосте) скриптом
`scripts/build-wifi-remote.sh` — он каждый раз пересоздаёт `work/` из
`vendor/` + этого каталога. **Правки, сделанные прямо в `work/`, теряются при
следующем прогоне** (это случилось в M41, а в M70–M80 — с прототипом
`wlanImageQueryStatus()`: без него `wlan_drv_gen3.ko` не собирается, см.
`docs/wifi-port-log.md` §82.5).

Порядок применения — по имени (`0001` → `0020`), для common и wlan отдельно;
каталог `optional/` сборкой **не** подхватывается (glob только верхнего уровня).

## Воспроизводимая серия (проверено сборкой 14.11.2026)

```
common: 0001-common-port-6.12
        0002-common-consys-power-on-dt
        0004-common-export-wmt-plat-pwr-ctrl
        0005-common-consys-spm-power-on
        0009-common-mt6771-consys-rompatch
        0010-common-btif-stp
        0011-common-default-chip-type-soc
        0012-common-xo-wcn-clock-buffer
        0013-common-rom-patch-from-firmware
        0015-common-stp-transport-trace
        0016-common-stp-rx-trace
        0017-common-warm-reset-and-mt6771-platform   <- снимок, дельта к базе выше

wlan:   0001-wlan-port-6.12
        0002-wlan-port-6.12-vendor-commands
        0003-wlan-t1100-probe-param
        0006-wlan-probe-stage-and-no-reset
        0007-wlan-fw-download-debug
        0008-wlan-override-fw-start-address
        0018-wlan-warm-reset-and-redownload         <- снимок, дельта к базе выше
        0020-wlan-access-reg-and-tx-diag
```

Результат: `wmt_drv.ko` (1 167 544 Б) + `wlan_drv_gen3.ko` (2 947 328 Б), 0
errors, против out-дерева `6.12.114-g675178729a-dirty`
(`/home/l/t1100-wifi-build/out`).

**Важно про 0017/0018.** Это не дельты, а **снимки состояния файлов**
(`diff -u -r a/ b/`): 0018 меняет `common/wlan_lib.c`, `include/wlan_lib.h`,
`os/linux/gl_rst.c`, `os/linux/hif/ahb_sdioLike/ahb.c`; 0017 — `wmt_ctrl.c`,
`wmt_ic_soc.c`, `wmt_lib.c`, `mt6771.c`. Исторически они генерировались поверх
дерева, где уже были применены 0009-wlan/0010-wlan/0014/0014z/0015/0016, и
поэтому «в лоб» не применялись. 14.11 они **перегенерированы как дельты к базе
из списка выше**, а поглощённые ими патчи убраны в `optional/`:

| в `optional/` | почему |
|---|---|
| `0009-wlan-query-status-and-two-start.patch` | вошёл в 0018 (как и весь M20–M53) |
| `0010-wlan-pwr-on-done.patch` | то же |
| `0014-common-rom-patch-delivery.patch` | вошёл в 0017 (delivery + quiet window + `t1100_patch_scan`) |
| `0014z-common-last-fragment-evt.patch` | то же |
| `0015-common-rom-patch-single-reset.patch` | то же |
| `0016-common-patch-addr-align.patch` | то же (`addressByte[0] = 0`) |
| `0014-common-skip-rom-patch.patch` | опция `t1100_skip_rom_patch`, не нужна |

`0019-build-makefiles.patch` сборкой не применяется: имя не содержит `common`/
`wlan`, а `Makefile` обоих модулей всё равно заменяется обёрткой
`scripts/remote/wifi-kbuild/*.Kbuild`.

## common (wmt_drv.ko)

| патч | зачем |
|---|---|
| `0001-common-port-6.12.patch` | порт 4.14 → 6.12 (API, вызовы, заголовки); заглушка `KERNEL_clk_buf_ctrl` (XO_WCN не включался — см. `0012`) |
| `0002-common-consys-power-on-dt.patch` | CONSYS power-on через наши DT-узлы (`vcn18/vcn28/vcn33-supply`, `memory-region`) |
| `0004-common-export-wmt-plat-pwr-ctrl.patch` | экспорт `wmt_plat_pwr_ctrl()` для `wlan_drv` |
| `0005-common-consys-spm-power-on.patch` | SPM-последовательность включения домена CONN (`0x1000632c`), `CONSYS_PWR_ON_OFF_API_AVAILABLE=0` |
| `0009-common-mt6771-consys-rompatch.patch` | EMI-путь ROM-патча (диагностика, по умолчанию off) |
| `0010-common-btif-stp.patch` | STP-over-BTIF: `stp_btif.o` в Kbuild, `t1100_btif_stp` (HIF_CONF+PWR_ON после `WMT_init`) |
| `0011-common-default-chip-type-soc.patch` | `INVALID` chip-type трактуется как SOC для MT6631 |
| `0012-common-xo-wcn-clock-buffer.patch` | `XO_WCN`/`DCXO_CONN_ENABLE` (MT6358 `DCXO_CW00`, `TOP_SPI_CON1`, pwrap `0x184`) |
| `0013-common-rom-patch-from-firmware.patch` | multi-patch-путь берёт файл из `/lib/firmware` (без `srh_patch`), `patch_num=1` |
| `0015-common-stp-transport-trace.patch` | трассировка STP-транспорта (`t1100_*`), диагностика M23–M30 |
| `0016-common-stp-rx-trace.patch` | трассировка RX-пути STP |
| `0017-common-warm-reset-and-mt6771-platform.patch` | **снимок**: `mtk_wcn_consys_warm_reset()` (AP_RGU + STP-reinit + polling `hwcode`), `consys_hw_spm_partial_reset()` (iso/rst без power-gating, M59), ROMv4-delivery (`t1100_patch_scan`, quiet window, `t1100_mem_write`/STP-запись, `addressByte[0]=0`), MT6771 platform-фиксы |

## wlan (wlan_drv_gen3.ko)

| патч | зачем |
|---|---|
| `0001-wlan-port-6.12.patch` | порт gen3-драйвера 4.14 → 6.12 |
| `0002-wlan-port-6.12-vendor-commands.patch` | `vendor_commands[].policy` — WARN при `wiphy_register` (M5) |
| `0003-wlan-t1100-probe-param.patch` | `t1100_probe` — probe на module init |
| `0006-wlan-probe-stage-and-no-reset.patch` | `t1100_probe_stage`, `t1100_no_reset` |
| `0007-wlan-fw-download-debug.patch` | отладочный вывод загрузки FW (таблица секций) |
| `0008-wlan-override-fw-start-address.patch` | адрес старта FW из DT (`hardware-values`) |
| `0018-wlan-warm-reset-and-redownload.patch` | **снимок**: `t1100_hif_state`, `t1100_rom_patch_send` (MCIF-путь ROMv4), два/три `WIFI_START`, warm-reset + re-download (M55–M62), `t1100_spm_partial`, диагностика MCR/MCIF (M43–M79), `t1100_mem_write`/`t1100_stp_write`, а также **фикс прототипа `wlanImageQueryStatus()`** в `include/wlan_lib.h` (без него сборка не проходит) |
| `0020-wlan-access-reg-and-tx-diag.patch` | **M81, не прогнан**: чтение памяти MCU через ROM (`INIT_CMD_ID_ACCESS_REG`, CID 3 → `INIT_EVENT_ID_ACCESS_REG`), `t1100_tx_state()` (`WHISR`/`WTQCR`/`WASR`/`WRPLR`) вокруг data-пакетов и стартов, vendor-вариант `WIFI_START` с `override=0`. См. `docs/wifi-port-log.md` §82 |

## BTIF-драйвер (отдельный модуль)

| файл | зачем |
|---|---|
| `0010-btif-mt6771-glue.patch` | правки публичного порта BTIF: без DT (базы/IRQ параметрами), sysirq-маппинг IRQ (SPI 114/139/140), фикс PIO (`p_rx_dma` NULL), печать before/after `hw_init` |
| `scripts/remote/m23-btif/m23_board.c` | glue: platform device, гейты INFRACFG_AO (**CLR** — на MT6771 бит «CG» = 1 закрывает клок), дампы |

## Как пересобрать с нуля

```sh
scripts/build-btif-remote.sh                     # mtk_btif_drv.ko
KERNEL_OUT=/home/l/t1100-wifi-build/out \
KERNEL_SRC=/home/l/t1100-ubuntu-build/src \
    scripts/build-wifi-remote.sh                 # wmt_drv.ko + wlan_drv_gen3.ko
```

## Что осталось незакоммиченным (проверять в первую очередь)

Всё, что «работало в прогоне», должно быть здесь. Известные пробелы прошлых
сессий, закрытые 14.11: прототип `wlanImageQueryStatus()` и порядок серии.
Если следующий прогон снова опирается на правку в `work/` — её сначала
переносить в патч, иначе дерево опять не воспроизводится.

# FM-радио на MT6631 (журнал порта)

## 1. Откуда взят драйвер

Вендорский `fmradio_drv.ko` (4.14, Aurora 5.2.1.200, 512 312 Б) — char-девайс
`/dev/fm`, ioctl magic `0xf5`, работает через WMT (`func_on(FM)`) и STP-канал
`FM_TASK_INDX=1`. Публичные исходники того же драйвера:

- `Winkmoon/android_kernel_xinran_oppo_mt6771`, ветка `android11`,
  `drivers/misc/mediatek/connectivity/fmradio_drv/` (MT6631 + RDS + patch/coeff).

Скопировано в `fmradio/` (33 файла). Вендорский `Makefile` сохранён как
`fmradio/Makefile.vendor`; сборка идёт своим `fmradio/Makefile` (out-of-tree).

## 2. Что адаптировано под 6.12

- `compat/{osal_typedef.h,stp_exp.h,wmt_exp.h}` — минимальные типы/enum/прототипы
  WMT/STP (`UINT8…`, `MTK_WCN_BOOL`, `WMTDRV_TYPE_*`, `WMTMSG_TYPE_*`, `PF_WMT_CB`,
  `mtk_wcn_stp_{send,receive}_data`, `register_event_cb`, `func_on/off`, …).
- `inc/fm_main.h` — свой `struct fm_timeval` (в 6.12 `struct timeval` недоступен
  модулям).
- `core/fm_reg_utils.c` — `ioremap_nocache` → `ioremap`.
- `core/fm_module.c` — `class_create(FM_NAME)`, `struct proc_ops`,
  `remove` → `void`, убран `.driver.owner`.

Сборка: `scripts/build-fm-remote.sh` (rsync в `/home/l/t1100-fm`, make против
`out-wifi`, `KBUILD_EXTRA_SYMBOLS=…/work/common/Module.symvers`).
Модуль: `build/fm/fmradio_drv.ko` (sha256 `e61b9ea2…`, vermagic `6.12.114-wifi1`).

## 3. FM-блок в wmt_drv

`CFG_FUNC_FM_SUPPORT` включается только `-DCONFIG_MTK_FMRADIO`
(`common_main/core/include/wmt_func.h:43`). Флаг добавлен в
`scripts/remote/wifi-kbuild/common.Kbuild`; пересобранный `wmt_drv.ko` —
1 177 832 Б, sha256 `478adcac…`. Теперь `gpWmtFuncOps[WMTDRV_TYPE_FM]` заполнен
и `mtk_wcn_wmt_func_on(FM)` доходит до `wmt_func_fm_on()`.

## 4. Контракт ioctl (magic 0xf5)

`_IOWR(0xf5, nr, struct fm_tune_parm *)` → cmd `0xC008F500 | nr`:

| nr | ioctl | nr | ioctl |
|----|-------|----|-------|
| 0 | POWERUP | 7 | GETRSSI |
| 1 | POWERDOWN | 8 | SCAN |
| 2 | TUNE | 10 | GETCHIPID |
| 3 | SEEK | 13 | GETMONOSTEREO |
| 4 | SETVOL | 18 | RDS_ONOFF |
| 5 | GETVOL | 24 | IS_FM_POWERED_UP |
| 6 | MUTE | 33 | I2S_SETTING |

`struct fm_tune_parm` (8 Б): `u8 err, band, space, hilo, deemphasis; u16 freq;`
`freq` в единицах 10 кГц (87.5 МГц → 8750), `band 0` = 87.5…108, `space 1` =
100 кГц.

## 5. Результат на T1100 (16.11)

- `modprobe fmradio_drv` → OK, `/dev/fm` (`509:0`), `fm_cust.cfg` прочитан.
- `FM_IOCTL_POWERUP`: `wmt_func_fm_on` → `OPID(3) type(1) ok`,
  `mt6631_pwron: WMT turn on FM OK!`.
- Сразу после этого прошивка CONSYS уходит в assert:
  `mtk_wcn_stp_coredump_start_ctrl: set f/w assert (1)`,
  `<ASSERT> patch/sys_patch_bin_t.c #4891`, `id=0x4 FM, irq=0x5`,
  `lr=0x9A7A6` → paged dump → whole-chip reset.
- Итог: POWERUP возвращает `errno 1005`, TUNE/GETRSSI/GETCHIPID — `1008`
  (`FM subsys is resetting`). FM-канал мёртв до восстановления MCU.
- `wmt-func: co_clock_type is not 1!` — не причина: на Aurora тот же
  `WMT_SOC.cfg` (`co_clock_flag=0`), FM там работает.
- Формат `FUNC_CTRL` проверен (`WMT_PKT CMD`, `OPCODE_FUNC_CTRL`, param =
  type + on/off, PDU 6 Б) — совпадает с вендорским.

## 6. Что осталось

Нужен вендорский порядок подготовки FM: либо загрузка FM-патча/flash-patch до
`FUNC_CTRL` (`WMT_OPID_FLASH_PATCH_DOWN`/`mtk_wcn_wmt_flash_patch_ctrl` в дереве
есть), либо RE `wmt_chrdev_wifi`/`wmt_launcher` (какие patch-name и порядок
команд они используют). Дополнительно для звука нужен ASoC-линк FM-I2S
(в стоковом DTS — `mt_soc_pcm_fm_i2s`), в нашем `mt6358-sound` его нет.

## 6b. Проверено: MCU-образ в списке патчей не помогает

Эксперимент 16.11 (позже): службы `t1100-wifi`/`t1100-bt` отключены
(`systemctl disable`; `mask` не сработал — юниты лежат в `/etc/systemd/system`),
чистая загрузка, затем

```
modprobe wmt_drv t1100_quiet_ms=100 \
  t1100_rom_patch="ROMv4_be_patch_1_1_hdr.bin ROMv4_be_patch_1_0_hdr.bin soc3_0_ram_mcu_e1_hdr.bin"
modprobe fmradio_drv
```

`mtk_wcn_wmt_func_on(FM)` снова проходит (`OPID(3) type(1) ok`), и снова сразу
assert: `patch/sys_patch_bin_t.c #4891`, `id=0x4 FM`, на этот раз `irq=0xC`,
`lr=0x9A7A6` → paged dump → coredump → `mt6631_PowerUp: power up read top 0xc0
failed`. Вывод: порядок загрузки и наличие `soc3_0_ram_mcu_e1_hdr.bin`
(addr `0xf0000000`) ничего не меняют — ассертит сам MCU-патч на включении FM.
Без вендорского FM-загрузчика/иного MCU-образа FM не поднять.

## 7. Откат

FM не меняет p29; достаточно не загружать `fmradio_drv` и вернуть прежний
`wmt_drv.ko` (`73256ebb…`), если нужен вариант без FM-блока.

# M36 — вендор после патча аппаратно домен не перезапускает; наш power-cycle не оживил STP (13.11)

## 1. Что делает вендор после `mtk_wcn_soc_patch_dwn()` (п.1)

`common_main/core/wmt_ic_soc.c`, ветка `CFG_WMT_MULTI_PATCH` (`:1283-1330`):

```c
	for (patch_index = 0; patch_index < patch_num; patch_index++) {
		iRet = mtk_wcn_soc_patch_dwn(patch_index);
		if (iRet) { ... return -7; }
		if (patch_index == (patch_num - 1))
			WMT_STEP_DO_ACTIONS_FUNC(STEP_TRIGGER_POINT_POWER_ON_BEFORE_CONNSYS_RESET);

		iRet = wmt_core_init_script(init_table_3, osal_array_size(init_table_3));
		...
		if (iRet) { ... return -8; }
	}
```

То есть после успешной загрузки патча вендор делает **только**:
* `WMT_STEP_DO_ACTIONS_FUNC(STEP_TRIGGER_POINT_POWER_ON_BEFORE_CONNSYS_RESET)` —
  хук фабричного режима `WMT_STEP` (в продуктовой сборке пуст; `wmt_step.c` в наш
  Kbuild не входит, см. `scripts/remote/wifi-kbuild/common.Kbuild`);
* `wmt_core_init_script(init_table_3)` → `WMT_RESET_CMD {01 07 01 00 04}`.

`consys_hw_reset_bit_set()`, `consys_hw_pwr_ctrl()` и `wmt_lib_hw_rst()` в
`mtk_wcn_soc_sw_init()` **не вызываются** (grep по файлу пуст) — аппаратного
перезапуска домена там нет.

## 2. Наш эксперимент: power-cycle домена после патча (п.2)

Добавлен `t1100_pwr_cycle_after_patch` (после патча и best-effort reset):

```c
	wmt_plat_pwr_ctrl(FUNC_OFF);  osal_sleep_ms(100);
	wmt_plat_pwr_ctrl(FUNC_ON);   osal_sleep_ms(50);
```

Реально выполнилось (лог платформы):

```
[61.926] mtk_wcn_consys_hw_pwr_off: CONSYS-HW-PWR-OFF, start … finish(0)
[62.029] mtk_wcn_consys_hw_pwr_on : CONSYS-HW-PWR-ON, start
[62.030] consys_hw_power_ctrl_spm: cpupcr right after reset 0x00000000
```

То есть домен действительно погашен и поднят заново. Но:

```
after-patch patchmem[0x80098020] = 0x00000000 (ret -3)
after-patch ctrl GEN_HCR         = 0x00000000 (ret -3)
after-2s    … те же -3
```

⇒ **и после аппаратного перезапуска STP-команды не обслуживаются**, включая
контрольный `GEN_HCR`.

## 3. Наиболее вероятная причина (по коду)

После аппаратного сброса чипа его STP-состояние обнуляется, а наш хост-STP
сохраняет свои `txseq`/`winspace`/`stp_en` — тем более что в M32 мы специально
«заморозили» очистку (`t1100_patch_active`). Вендор в такой ситуации не
перезапускает домен, а если бы перезапускал — обязан был бы заново пройти
`wmt_core_stp_init()` (`stp_open` → `WMT_STP_CONF_MODE` = `MTKSTP_BTIF_MAND_MODE`
→ `WMT_STP_CONF_EN` = 1), иначе кадры уходят в никуда.

## 4. Итоговое состояние

`cpupcr` в ROM (`0x11 70 … 0x14f12`), `WCIR`/READY = 0, `wlan0` нет;
`hwcode` после перезапуска не читается (`ret -3`).

## 5. Один следующий шаг

После power-cycle **переинициализировать STP** ровно как `wmt_core_stp_init()`:
`stp_close` → `stp_open` → `WMT_STP_CONF_MODE = MTKSTP_BTIF_MAND_MODE` →
`WMT_STP_CONF_EN = 1`, затем `hw_check` (`REG_READ` `GEN_HCR` → `0x788`) и
readback. Это единственная непройденная часть вендорской последовательности,
которая объясняет «после сброса чип молчит» без новых гипотез о payload.

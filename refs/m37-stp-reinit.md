# M37 — реинициализация STP оживляет чип; power-cycle стирает патч (13.11)

## 1. Реинициализация STP после power-cycle (п.1)

Добавлено в `t1100_pwr_cycle_after_patch` (после PWR-OFF/ON, с снятием
`t1100_patch_active`):

```c
			t1100_patch_active = 0;
			rc1 = wmt_core_ctrl(WMT_CTRL_STP_CLOSE, &p1, &p2);
			rc2 = wmt_core_ctrl(WMT_CTRL_STP_OPEN, &p1, &p2);
			p1 = WMT_STP_CONF_MODE; p2 = MTKSTP_BTIF_MAND_MODE;
			rc3 = wmt_core_ctrl(WMT_CTRL_STP_CONF, &p1, &p2);
			p1 = WMT_STP_CONF_EN; p2 = 1;
			rc4 = wmt_core_ctrl(WMT_CTRL_STP_CONF, &p1, &p2);
			rc5 = wmt_core_reg_rw_raw(0, 0x80000008, &hw, 0xffffffff);
```

Результат:

```
t1100: stp reinit close=0 open=0 mode=0 en=0        <- все шаги успешны
t1100: hwcode after stp reinit = 0x00000788 (ret 0)  <- ЧИП СНОВА ОТВЕЧАЕТ
```

## 2. Судьба патча после power-cycle (п.2)

```
after-reinit patchmem[0x80098020] = 0x00000000 (ret 0)
after-reinit patchmem[0x80098024] = 0x00000000 (ret 0)
after-reinit patchmem[0x80098028] = 0x00000000 (ret 0)
after-reinit ctrl GEN_HCR         = 0x00000788 (ret 0)
```

`ret 0` = чтение **обслуживается** (в отличие от `-3` до реинициализации), но
данные — **нули**: патч, доставленный до power-cycle, **стёрт вместе с MCU-памятью**
(чего и следовало ожидать: `consys_hw_power_ctrl_spm()` сбрасывает домен).

⇒ подтверждены две вещи:
1. «Молчание» после загрузки патча — это **рассинхронизация STP**, а не гибель
   чипа: после `stp_close/open/mode/en` он снова обслуживает команды
   (`hwcode 0x788`).
2. Патч в памяти не выживает power-cycle ⇒ перекладывать надо **без** перезапуска
   домена.

## 3. Состояние

`cpupcr = 0x1170` (ROM), `WCIR`/READY = 0, `wlan0` нет
(`ip -br link` → `lo`, `usb0`). В `wlan`-логе после реинициализации —
`mtk_wcn_stp_psm_enable: STP Not Ready`, т.е. до `wlanAdapterStart` дело не дошло.

## 4. Один следующий шаг

Раз STP-реинициализация лечит рассинхронизацию, а power-cycle стирает патч —
сделать **STP-reinit сразу после доставки патча, без power-cycle**:

`patch_dwn()` → (STP сам «замолкает») → `stp_close` → `stp_open` →
`WMT_STP_CONF_MODE = MTKSTP_BTIF_MAND_MODE` → `WMT_STP_CONF_EN = 1` →
`hw_check` (`GEN_HCR`) → readback `0x80098020`.

Если после этого `hwcode = 0x788` **и** в `0x80098020` лежат байты файла
(`0x00002144`, `0x000100a8`, `0x00021ef4`) — патч на месте и связь жива; тогда
сразу отправлять «старт» (`WMT_RESET_CMD` или, при его молчании, повторный
power-cycle уже *после* проверки, что патч в памяти) и идти к `WIFI_START`.

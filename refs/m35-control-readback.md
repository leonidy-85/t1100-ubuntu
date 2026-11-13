# M35 — контрольные чтения: до патча чип отвечает, после — нет (13.11)

## 1. Контроль `REG_READ` в одной и той же точке инициации

Прогон с `t1100_patch_readback=1`; helper читает `0x80098020/24/28` и контроль
`GEN_HCR = 0x80000008`, `wmt_core_trigger_assert` заглушён на время патча.

**До передачи патча (та же точка, после `hw_check`):**

```
t1100: before-patch patchmem[0x80098020] = 0x00000000 (ret 0)
t1100: before-patch patchmem[0x80098024] = 0x00000000 (ret 0)
t1100: before-patch patchmem[0x80098028] = 0x00000000 (ret 0)
t1100: before-patch ctrl GEN_HCR = 0x00000788 (ret 0)
```

⇒ метод валиден (контроль отдаёт chip-id `0x788`), а **область патча до загрузки
читается нулями**.

**После передачи патча (и через 2 с):**

```
t1100: after-patch patchmem[0x80098020] = 0x00000000 (ret -3)
t1100: after-patch ctrl GEN_HCR = 0x00000000 (ret -3)
t1100: after-2s  patchmem[0x80098020] = 0x00000000 (ret -3)
t1100: after-2s  ctrl GEN_HCR = 0x00000000 (ret -3)
```

⇒ после загрузки патча чип **не отвечает ни на один REG_READ**, включая
контрольный адрес, и через 2 с не восстанавливается.

**Вывод:** патч не применён (память не содержит тела файла — там читались нули),
а сама передача переводит ROM в состояние, где он не обслуживает WMT-команды.
`t1100: assert suppressed (patch in flight)` в логе подтверждает, что in-band
assert больше не отправляется — значит замолкание не от нашего assert'а.

## 2. `nicpmSetDriverOwn` — проверка корректна

`os/linux/include/gl_typedef.h:56`: `#define TRUE ((BOOL) 1)`, `FALSE = 0`.
`nic/nic_pwr_mgt.c:167-273`: функция возвращает `fgStatus`, который
выставляется в `FALSE` в ветке «LP fail, Timeout…», и печатает
`DRIVER OWN, status=%d count=%d`. В логе `status=0 count=513` — это
**status = FALSE**, т.е. функция **корректно сообщает об ошибке**.

Причина отказа: чип не выставляет `WHLPCR_FW_OWN_REQ_SET` (`BIT(8)` регистра
`MCR_WHLPCR`, `include/nic/mt6630_reg.h:259`) в течение
`LP_OWN_BACK_TOTAL_DELAY_MS = 512` мс. Это не ошибка проверки — это отсутствие
ответа WLAN-стороны (ROM без патча не обслуживает PM-handshake).

⇒ правка проверки не требуется и была бы подменой факта.

## 3. Полный `wlan`-лог (stage=3)

```
HifAhbPltmProbe; t1100_wlan_probe: CONSYS already up (wmt_drv BTIF STP)
wlanNetCreate: net_device allocated; glLoadNvram: Nvram not available
nicpmSetDriverOwn:(NIC ERROR) LP fail, Timeout(516ms) Bus Error[0] Resetting[0] NoAck[0] Cnt[0]
wlanPollingCpupcr: 00014f08 / 000055c2 / 000055ba / 00014ee4
nicpmSetDriverOwn:(NIC INFO) DRIVER OWN, status=0 count=512
wlanAdapterStart:(INIT ERROR) nicpmSetDriverOwn() failed!
wlanProbe failed → -5 ; mtk_wcn_stp_psm_disable: STP Not Ready
```

`cpupcr = 0x14ee4` (ROM), `WCIR`/READY = 0, `wlan0` нет.

## 4. Один следующий шаг

После неудачной загрузки патча чип замолкает навсегда (в пределах питания).
Проверить, **восстанавливается ли обслуживание после перезапуска домена**:
power-off/power-on CONSYS (или полный reboot модулей) → снова `hw_check`
(`hwcode 0x788`) и readback `0x80098020`. Если после перезапуска чип снова
отвечает, значит ROM не «сломан», а именно наша передача переводит его в
необслуживаемое состояние — и тогда следующий шаг в формате передачи
(в частности: почему ROM подтверждает 229 фрагментов и молчит на 230-м, хотя
кадр уходит целиком — 347/347).

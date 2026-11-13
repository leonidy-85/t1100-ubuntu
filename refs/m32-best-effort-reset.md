# M32 — best-effort reset и полный stage=3: докуда доходит стек (13.11)

## 1. Что сделано

* `wmt_lib_hw_rst()` больше не чистит `WMT_STAT_STP_OPEN/EN/RDY/RX/CMD`, пока
  `t1100_patch_active` (то самое место, `wmt_lib.c:2096-2097`, которое давало
  `-2` на ретраях).
* `WMT_RESET_CMD` стал **best-effort**: отправляем, ждём EVT, при отсутствии —
  печатаем `t1100: reset ack: no` и продолжаем инициацию (STP остаётся открыт,
  `iRet = 0`).

Итог прогона:

```
t1100: ROMv4 patch download -> 0
t1100: reset ack: no
```

`-2` между попытками больше нет (ретраев и нет — reset один, best-effort).

## 2. `cpupcr` до/после патча (по 10 замеров с шагом 10 мс)

```
during-power-on: 0x019e6 0x14eea 0x14edc 0x019fc 0x14ef8 0x055b4 0x01a02 0x14f08 0x019e6 0x14ef8
after-patch:     0x14f08 0x019d8 0x14f0e 0x019e6 0x055be 0x01a02 0x14ed0 0x14ee4 0x14f08 0x14f12
```

Набор адресов **тот же** (ROM-цикл `0x19d8…0x14f12`), к `0xa5800` не поднимается
⇒ патч **передан, но не применён/не стартовал**; `reset ack: no` — следствие
того же.

## 3. Полный `wlan`-лог прогона `t1100_probe=1 t1100_probe_stage=3`

```
[42.533] [wlan]HifAhbPltmProbe:(INIT INFO) HifAhbPltmProbe
[42.534] [wlan]t1100_wlan_probe: CONSYS already up (wmt_drv BTIF STP)
[42.534] [wlan]wlanNetCreate: net_device allocated
[42.534] [wlan]glLoadNvram: fgNvramAvailable = 0 / Nvram not available
[43.049] [wlan]nicpmSetDriverOwn:(NIC ERROR) LP fail, Timeout(516ms) Bus Error[0] Resetting[0] NoAck[0] Cnt[0]
[43.049] [wlan]wlanPollingCpupcr: i:0 00014f08; i:1 000055c2; i:2 000055ba; i:3 00014ee4
[43.097] [wlan]nicpmSetDriverOwn:(NIC INFO) DRIVER OWN, status=0 count=513
[43.097] [wlan]wlanAdapterStart:(INIT ERROR) nicpmSetDriverOwn() failed!
[43.097] [wlan]wlanProbe failed → t1100_wlan_probe returned -5
[48.197] [STP] mtk_wcn_stp_psm_disable: STP Not Ready, Dont do Sleep/Wakeup
```

То есть стек доходит до **MCIF-рукопожатия** (`nicpmSetDriverOwn`) — это уже
существенно дальше, чем в M22–M25: BTIF/STP живы, `driver own` отправлен
(`status=0 count=513`), но бит READY (`WCIR[21]`) не встаёт, и
`wlanAdapterStart` падает.

## 4. Итоговое состояние

| | |
|---|---|
| `reset ack` | **no** |
| `cpupcr` | `0x14eea`…`0x14f12` (ROM), без изменений от патча |
| `WCIR` / `WLAN_READY` | READY = 0 (по логу `nicpmSetDriverOwn`) |
| `ip -br link` | `lo`, `usb0` — **`wlan0` нет** |
| BTIF | `IIR=1`, `LSR=0x60`, IRQ 395 > 150 000 — здоров |

## 5. Один следующий шаг (по коду)

ROM подтверждает фрагменты 1…229 (`WMT_PATCH_EVT`), а **230-й (последний, 336 Б)
не подтверждает** и патч не применяет. Значит вопрос не в «start», а в
**последнем фрагменте**. По коду вендора последний фрагмент отличается только
флагом (`WMT_PATCH_CMD[4] = WMT_PATCH_FRAG_LAST = 0x3`) и длиной
(`cmdLen = 1 + fragSize`). Проверить по стоковому `wmt_launcher`/`wmt_loader`,
что именно вендор кладёт в «patch info» (в `wmt_launcher` есть
`patch info:0x%02x × 8` и `read patch info:0x%02x × 4`) — возможно, для ROMv4 в
ядро передаётся не только адрес (`0x00098022`), но и `u4PatchType`
(`0x0fe3ffff` из заголовка), без которого ROM отбрасывает хвост. Это
единственная зацепка, подтверждённая логом (229 ack → 230-й молчит).

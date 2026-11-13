# M40 — смещение тела не является причиной: 229 ack и молчание в обоих вариантах (13.11)

## 1. Что говорит код про смещение

```c
/* wmt_ic_soc.c:3388-3394 (generic / multi-patch) */
	if (patchSize < sizeof(WMT_PATCH)) { ... }
	patchSize -= sizeof(WMT_PATCH);      /* 28 байт */
	pPatchBuf += sizeof(WMT_PATCH);
	...
	/* только для 0x6765/0x3967/0x6761: */
	pPatchBuf += BCNT_PATCH_BUF_CHECKSUM; patchSize -= BCNT_PATCH_BUF_CHECKSUM;
```

`WMT_PATCH` (`wmt_core.h:419-425`) = `ucDateTime[16] + ucPLat[4] + u2HwVer +
u2SwVer + u4PatchVer` = **28 байт**. `struct wmt_rom_patch` (48) используется
только в **нашем** EMI-хелпере (`mt6771.c`, патч 0009), вендорский WMT-путь его
не знает.

То есть для `0x0788` вендор режет **28** байт, наш загрузчик резал **48** —
гипотеза проверяемая, и мы её проверили.

## 2. Оба варианта на железе

| вариант | hdr | `patchSize` | `fragNum` | ack | `hwcode` после патча | `patchmem[0x80098020]` |
|---|---|---|---|---|---|---|
| 1 (было) | 48 | 229 336 | 230 | 229/230 (230-й без EVT) | `ret -3` (молчит) | `ret -3` |
| 2 (новое) | 28 | 229 356 | 230 | 229/230 | `ret -3` (молчит) | `ret -3` |

Оба прогона: `stp reinit (no cycle) close=0 open=0 mode=0 en=0`, затем
`hwcode = ret -3`, `GEN_HCR = ret -2`.

⇒ **смещение тела не влияет**: поведение идентично, `fragNum` в обоих случаях
230, чип после патча одинаково перестаёт обслуживать STP.

## 3. Состояние

`cpupcr` = ROM, `WCIR`/READY = 0, `wlan0` нет; `wlanAdapterStart` по-прежнему
падает на `nicpmSetDriverOwn` (READY не встаёт).

## 4. Один следующий шаг (по коду)

Наш загрузчик **обходит** вендорский путь получения патча: он не вызывает
`WMT_CTRL_GET_PATCH_INFO` (отдаёт `addressByte` из заголовка), не выставляет
`patch_num` и не делает финальный `WMT_CTRL_FREE_PATCH`
(`mtk_wcn_soc_patch_dwn`, конец функции). Проверить это можно без гадания:
написать **минимальный ответчик `srh_rom_patch`** (аналог `wmt_launcher`: на
команду `srh_patch` отдать имя/адрес, на `get patch` — содержимое файла) и
прогнать **немодифицированный** вендорский multi-patch путь целиком, с
`WMT_CTRL_GET_PATCH_INFO`/`FREE_PATCH` и `patch_num` из userspace.

Если при этом ROM оживёт после последнего фрагмента — причина в нашей
«сокращённой» ветке (patch info/free-patch), и правка будет в ней; если нет —
причина в самом взаимодействии с ROM, и тогда единственный оставшийся источник —
`dmesg`/DTRACE рабочего стока.

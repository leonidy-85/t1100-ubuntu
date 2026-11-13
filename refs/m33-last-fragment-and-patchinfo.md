# M33 — последний фрагмент уходит целиком; patch info в ядре не используется (13.11)

## 1. Трассировка последнего фрагмента (п.1) — обрезки нет

Инструментирован `mtk_wcn_consys_stp_btif_tx()` (печать для кадров ≥256 Б) и
цикл патча (`last frag seq/fragSize/cmdLen/txRes`). Прогон (stage=3):

```
[36.214] [STP-BTIF] t1100: stp->btif len=366 written=366     <- предпоследний (336+5+4+2 = 347? нет: 366 = тело 355?)
[36.218] [STP-BTIF] t1100: stp->btif len=347 written=347     <- ПОСЛЕДНИЙ
[38.373] [WMT-IC]  t1100: reset ack: no
```

`347 = 4 (STP header) + 5 (WMT PATCH_CMD) + 336 (тело) + 2 (CRC)` — ровно
ожидаемое; `written=347` ⇒ **кадр целиком принят BTIF** (`mtk_wcn_btif_write`
вернул len, ветки `recovered`/`stp btif write fail` в логе отсутствуют).
Значит обрезки нет: STP-фрагментатор и буферы в порядке, ROM действительно не
отвечает на 230-й фрагмент.

Замечание: `wmt_core_tx` для последнего фрагмента вернул `fragSize+5 = 341`
(иначе код ушёл бы в `break` с ошибкой и мы не получили бы `patch dwn:0`).

## 2. Patch info (п.2) — kernel не использует `u4PatchType`

Структура файла (`common_main/core/include/wmt_core.h:428`):

```c
struct wmt_rom_patch {
	UINT8  ucDateTime[16];
	UINT8  ucPLat[4];
	UINT16 u2HwVer;
	UINT16 u2SwVer;
	UINT32 u4PatchAddr;      /* 0x00098022 */
	UINT32 u4PatchType;      /* 0x0fe3ffff */
	UINT32 u4CRC[4];
};
```

и то, что ядро реально берёт из userspace:

```c
/* wmt_ic_soc.c, mtk_wcn_soc_patch_dwn(index) */
ctrlData.ctrlId = WMT_CTRL_GET_PATCH_INFO;
ctrlData.au4CtrlData[0] = index + 1;
ctrlData.au4CtrlData[1] = (SIZE_T)&gFullPatchName;
ctrlData.au4CtrlData[2] = (SIZE_T)&addressByte;   /* только 4 байта адреса */
...
if (emiInfo->pda_dl_patch_flag)
	iRet = mtk_wcn_soc_pda_patch_dwn(pPatchBuf, patchSize, addressByte);
else
	iRet = mtk_wcn_soc_normal_patch_dwn(pPatchBuf, patchSize, addressByte);
```

`addressByte` попадает только в `WMT_PATCH_P_ADDRESS_CMD[12..15]`; `u4PatchType`
в ядре **не используется нигде** (это метаданные userspace `srh_rom_patch`,
которые он же и парсит). Наш загрузчик берёт из заголовка ровно то же, что взял
бы userspace: адрес `0x00098022`, тело с offset 48.

⇒ гипотеза «мы не передаём patch info» **закрыта**: передаём то же и туда же,
что вендор.

## 3. Что осталось

* Патч передан (230/230, последний кадр целый), ROM молчит на reset
  (`reset ack: no`), `cpupcr` остаётся в ROM-диапазоне (`0x19d8…0x14f12`) — что,
  как верно замечено, **нормально и для успешно пропатченного ROM** (ROM-патч
  правит ROM RAM, MCU продолжает исполнять ROM).
* `wlan_drv` (stage=3) доходит до `nicpmSetDriverOwn`: `DRIVER OWN, status=0
  count=513`, затем `wlanAdapterStart fail` (READY=0).
* `wlan0` нет.

## 4. Один следующий шаг (единственный, который даёт ответ)

Проверить, **лежит ли патч в памяти чипа**: прочитать через уже работающий
WMT `REG_READ` (opcode `0x08`, тот же, что в `hw_check`) несколько слов по
адресу патча `0x00098022` и сравнить с первыми байтами тела файла
`ROMv4_be_patch_1_0_hdr.bin` (смещение 48). Если совпало — патч применён, и
блокер дальше по цепочке (MCIF/`WIFI_START`/READY); если нет — ROM его
отбросил, и тогда искать причину в формате последнего фрагмента по вендорскому
`srh_rom_patch` (единственный оставшийся источник — стоковый лог/DTRACE
успешной загрузки Wi-Fi).

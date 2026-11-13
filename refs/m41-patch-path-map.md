# M41 — карта пути патча и состояние (13.11)

## 1. Полный путь ROMv4-патча: от userspace до `init_table_3`

```
wmt_launcher (userspace)                        ядро (wmt_drv)
─────────────────────────                       ────────────────────────────────────────
/dev/stpwmt  ← "srh_patch"  ────────────────►   wmt_ctrl_patch_search()
   │  ищет файл, отдаёт 8 байт patch info          └─ wmt_ctrl_ul_cmd(pDev, "srh_patch")
   │  (+4 байта адреса)                                ждёт ответа демона
   ▼
WMT_IOCTL_SET_PATCH_NAME ───────────────────►   wmt_lib_set_patch_name() → gDevWmt.cPatchName
WMT_IOCTL_SET_PATCH_NUM  ───────────────────►   gDevWmt.u4PatchNum
WMT_IOCTL_SET_PATCH_INFO ───────────────────►   gDevWmt.pWmtPatchInfo[seq-1] = {name, addr[4]}

                                                mtk_wcn_soc_sw_init() (icId 0x0788):
                                                6.2 patch_num = mtk_wcn_soc_get_patch_num()
                                                    └ если 0 → mtk_wcn_soc_patch_info_prepare()
                                                       → WMT_CTRL_PATCH_SEARCH (см. выше)
                                                6.3 for patch_index: mtk_wcn_soc_patch_dwn(index)
                                                      WMT_CTRL_GET_PATCH_INFO(seq)  ← name+addr
                                                      WMT_CTRL_GET_PATCH(name)      ← файл читает
                                                                                      само ядро
                                                                                      (wmt_dev_patch_get)
                                                      отрезать sizeof(WMT_PATCH)=28
                                                      (для 0x6765/3967/6761 ещё 2 байта CRC)
                                                      WMT_PATCH_ADDRESS_CMD  [8..9] = 0x18/0x05
                                                      WMT_PATCH_P_ADDRESS_CMD[12..15] = addr
                                                      230 фрагментов по 1000 Б + WMT_PATCH_EVT
                                                      WMT_CTRL_FREE_PATCH
                                                6.4 wmt_core_init_script(init_table_3)
                                                      = WMT_RESET_CMD {01 07 01 00 04}
```

## 2. Наши отклонения от этого пути

| шаг | вендор | у нас |
|---|---|---|
| поиск патча | демон отвечает на `srh_patch` | M29: обход — файл читаем сами (`t1100_rom_patch`), `patch_num=1` |
| patch info | `WMT_IOCTL_SET_PATCH_INFO` (name+addr) | обход: адрес берём из заголовка файла |
| резка заголовка | `sizeof(WMT_PATCH)` = **28** | было 48, проверено и 28 (`t1100_patch_hdr_len`) — **поведение идентично** |
| `WMT_CTRL_FREE_PATCH` | вызывается | в обходной ветке — нет |
| «старт» | `init_table_3` (`{01 07 01 00 04}`) | отправляем, `reset ack: no` |

## 3. Что проверено на железе (итог M29–M40)

* гейт BTIF на MT6771 **инвертирован** (`IFR0[31]=1` = клок закрыт) — починено;
* после этого ROM **отвечает** (`hwcode 0x788`), патч уходит (230 фрагментов,
  последний кадр 347 Б — целиком);
* после последнего фрагмента MCU перестаёт обслуживать STP: `REG_READ` → `ret -3`
  (включая контрольный `GEN_HCR`), STP-reinit без сброса домена не помогает,
  power-cycle чип оживляет, но **стирает патч** (`patchmem = 0`);
* смещение тела (48 vs 28) и хвостовой CRC исключены (расчёт + прогон).

## 4. Состояние сборки

**Важно:** `scripts/build-wifi-remote.sh` пересоздаёт `work/` из `vendor/` +
`wifi-patches/*.patch`, поэтому правки M33–M41, сделанные прямо в `work/`,
потеряны при очередном прогоне (это случилось в M41). На устройстве остаются
модули эпохи M40:

| модуль | sha256 |
|---|---|
| `wmt_drv.ko` | `1e10a898be02ccffdcd05cd49d97f90c063a09941272f306b9d4cc74605dca40` |
| `mtk_btif_drv.ko` | `e29eaecb70157b1c27ed190b7849c308cc5f6e5e8cae3341af6c2a896b40ef34` |
| `wlan_drv_gen3.ko` | `80dafe3d4a6b584d16c70cc2cf2bb17e3b8f7cfc18fd1925610e6a31f396ded1` |

Правки M33–M41 нужно переносить в `patches/wifi/*.patch`, иначе они не
воспроизводятся (сейчас воспроизводится только `0013`).

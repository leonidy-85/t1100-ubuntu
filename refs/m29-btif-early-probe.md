# M29 — когда теряются записи в BTIF: ответ и вылеченная причина (13.11)

## 1. Эксперимент в ядре (патч `0065-soc-mediatek-t1100-btif-early-probe.patch`)

Три пробы (early/device/late_initcall) пишут `IER ← 0xa5a5a5a5` и
`TRI_LVL ← 0xda`, читают обратно и дампят `0x10001080/84/90`, `0x100012a0`,
`0x10207f00`. Ядро `6.12.114-g400cb6f-touch-rot` собрано в `merge2-out`
(`LOCALVERSION=-g400cb6f-touch-rot`), boot перепакован **с ramdisk**
(`scripts/repack_boot.py --ref build/xfer/cur_boot.img`, ramdisk 1 033 291 Б),
DTB прошёл `tools/lk/verify-dtb.sh` c `LK_EXTRA_RES=0x70000000:0x10000:ibc-reserved`
(«RESULT: validator passed»), прошит в `p29` (`/dev/block/179:29`) через `dd`,
sha раздела после записи совпал.

В dmesg осталась только стадия `late_initcall` (лог начинается с 0.209 с,
ранние строки в кольце отсутствуют):

```
t1100-btif-early: stage=late_initcall IER=00000000->00000001(dropped-по-маркеру)
  TRI=0000005a->000000da(write-accepted)
  IFR0 set=00004800 clr=00004800 sta=00004800 PROT=00006098 APC_CON=00000000
```

Два вывода из этой строки:
* **`TRI_LVL` запись принята** (`0x5a → 0xda`) на чистой загрузке;
* `IFR0 = 0x4800` — бит31 (наш BTIF-гейт) = **0**.

## 2. Причина: полярность гейта на MT6771 инвертирована

Проверка на живом ядре (mempeek, без модулей):

| IFR0[31] | `TRI_LVL ← 0xda/0x18` | `IER ← 0xa5a5a5a5/0x1` |
|---|---|---|
| **1** (`0x9befff5d`) | `0x5a` — отброшено | `0x0` — отброшено |
| **0** (`0x1befff5d`, после `CLR 0x84 ← 0x80000000`) | **`0x18` — принято** | **`0x1` — принято** |

То есть на MT6771 бит «CG» = **1 закрывает клок**, а 0 — открывает; mt8183-драйвер,
который наследует порт, считает наоборот. **Наш `m23_clk_enable()` (SET бита31)
всё это время выключал BTIF** — отсюда «write-dead» с M23 по M28.

Исправлено в glue: `m23_clk_enable()` теперь пишет **CLR** (0x84) и проверяет,
что бит31 = 0; `clk_prepare_enable()` на `infra_btif` больше не вызывается
(CCF тоже пишет SET). После этого `hw_init` видит `IER readback 0x1 (RX=1)`,
`TRI_LVL=0x18` — записи идут.

## 3. Что это дало по цепочке

```
wmt_core_hw_check: get hwcode (chip id) (0x788)          <- ROM ответил по BTIF/STP
mtk_wcn_soc_ver_check: 0x788: ic info SOC_CONSYS.E1 (0x8a00/0x8a00)
t1100: patch ROMv4_be_patch_1_0_hdr.bin size=229384 plat=ALPS hw=0x008a sw=0x008a
        addr=0x00098022 type=0x0fe3ffff
mtk_wcn_soc_normal_patch_dwn: patch size(229336) fragNum(230)
t1100: no EVT for the last fragment (ROM jumps), continuing
wmt_core: patch dwn:0 frag(230, 336) ok
t1100: ROMv4 patch download -> 0                          <- ПАТЧ ДОСТАВЛЕН
```

Для этого понадобились две правки вендорского пути (патч
`patches/wifi/0013-common-rom-patch-from-firmware.patch`):
1. при `t1100_rom_patch` multi-patch-ветка берёт файл из `/lib/firmware` и не
   спрашивает userspace (`srh_patch`), `patch_num = 1`;
2. отсутствие `WMT_PATCH_EVT` на **последнем** фрагменте считается успехом
   (`++fragSeq` перед `break`), т.к. ROM после последнего фрагмента прыгает в
   патч и EVT не шлёт (наблюдение: 229/230 ack, 230-й — таймаут).

## 4. Текущий блокер

Сразу после успешного патча падает следующий шаг `sw_init` — «WMT reset»:

```
[WMT-CORE][E]wmt_core_init_script_retry(691): write (wmt reset) iRet(-2) cmd len err(-2, 5)
[WMT-IC][E]mtk_wcn_soc_sw_init(1274): init_table_3 fail(-1)
```

`cpupcr` остаётся в ROM (`0x19d8…0x14f12` < `0xa5800`), `WLAN_READY` = 0,
`wlan0` нет. Т.е. патч в памяти есть, но MCU не перезапущен в него.

## 5. Артефакты

| что | sha256/md5 |
|---|---|
| boot `build/xfer/boot_m29.img` (с ramdisk) | `3cb9080fe68994b34faf80296076ea52763317c24780beb6bc8983d0abcfaa8b` |
| readback `p29` после записи | совпал с образом |
| откат `build/xfer/cur_boot.img` (= boot_a до M29) | md5 `4f9c8525b44fc3ad4c7b0a817e368f61` |
| Image (M29) | `ad9ff3aa3ab789fda37f3f0e79fa7cddae8821f16893d2ac43d33dee7fa7edc1` |
| DTB | `741670baef6c976a9db9f1f11935b0388162a7fed3b1fadd39f28fa18a4be0d1` |
| `mtk_btif_drv.ko` (CLR-фикс) | `e29eaecb70157b1c27ed190b7849c308cc5f6e5e8cae3341af6c2a896b40ef34` |
| `wmt_drv.ko` (файл-патч + last-frag) | `6f78cc002c4932671d42608c345dcc04850c3097228282cf3425c9c4474e0da8` |

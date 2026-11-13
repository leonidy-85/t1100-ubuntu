# M27 — recovery как дискриминатор: невозможен, и почему (13.11)

Цель: загрузить recovery (тот же LK/ATF, другой kernel), прогнать write-тест BTIF
и три адреса, и понять, блокирует ли наш mainline-бут или LK/ATF.

## 1. Вход в recovery

`reboot recovery` из mainline **не работает**: в GPT этой платы **нет раздела
`misc`** (см. dump GPT: nvcfg, nvdata, md_udc, metadata, protect1/2, seccfg,
sec1, proinfo, nvram, logo, vbmeta_*, md1img_*, spmfw_*, scp_*, sspm_*, cam_vpu*,
gz_*, items, lk_*, boot_*, vendor_boot_*, dtbo_*, tee_*), а systemd аргумент
reboot игнорирует. Вход — только кнопками (владелец нажал; меню
«Jolla Recovery v2.0», USB `2931:0a06`, RNDIS `10.42.66.66`, telnet → `3` → `y`
без Enter → код `12345`).

## 2. Что в recovery есть и чего нет

```
uname -a : Linux (none) 4.14.186 #1 SMP PREEMPT Mon Jan 20 14:34:05 UTC 2025 aarch64
model    : MT6771V/C
```

| возможность | результат |
|---|---|
| `/dev/mem` | **нет**; `mknod /dev/mem c 1 1` → `dd`: `No such device or address` ⇒ `CONFIG_DEVMEM=n` |
| debugfs | `mount -t debugfs none /tmp/dbg` → `No such device`; `/sys` read-only |
| `/dev/kmem` | нет |
| `devmem` | нет (busybox без applet'а) |

⇒ **MMIO из userspace в recovery недоступен**, `mempeek`/`btif-probe.sh` там
бесполезны.

## 3. Вендорские драйверы в recovery

```
/sys/bus/platform/drivers/mtk_btif:  1100c000.btif        -> devices/platform/1100c000.btif
/sys/bus/platform/drivers/devapc :   10207000.devapc      -> devices/platform/10207000.devapc
/sys/bus/platform/devices       :    10015000.devapc_mpu_ao
/proc/vmallocinfo:
  0xffffff800882f000-...  phys=0x0000000010207000  ioremap   (devapc)
  0xffffff8008ef5000-...  phys=0x000000001100c000  ioremap   (mtk_btif)
```

То есть **в вендорском ядре оба драйвера живут** (и `devapc` при probe делает
`start_devapc()`: гейт `INFRA_DEVICE_APC` + `APC_CON ← 0x80000000`).

Но: `dmesg | grep -i btif` — **пусто**, в том числе после `unbind`/`bind`
(логи BTIF в сборке выключены, `BTIF_DBG_SUPPORT=0`); `flag`-атрибут читается
(`dbg level:4`), но запись `8 5` уровень не меняет, а `echo 1` (open-test) не
даёт ни строки в dmesg ⇒ self-test'ы не скомпилированы. WMT-стек в recovery не
запущен ⇒ BTIF-драйвер `open` не делает ⇒ **записей в BTIF в recovery не
происходит вообще**, тест нечего мерить.

## 4. Отмена плана «прочитать на стоке»

Стоковый конфиг (`refs/device/config-stock.gz`):

```
CONFIG_MTK_BTIF=y
CONFIG_MTK_DEVAPC=y
# CONFIG_DEVMEM is not set
```

⇒ **на стоковой Aurora `/dev/mem` тоже нет**, и запланированный в M26/M27
«прочитать/записать BTIF на стоке через mempeek» **невыполним**. Единственный
оставшийся вид доказательства — поведение стока (Wi-Fi/BT работают ⇒ BTIF
пишется) и инструментовка через модуль вендорского ядра (нужен исходник
4.14.186, которого у нас нет).

## 5. Что подтверждено по клокам (вендорский dt-bindings)

`include/dt-bindings/clock/mt6771-clk.h` (Hadenix, `4.4.146`):

```c
#define INFRACFG_AO_BTIF_CG       27     /* :199 */
#define INFRACFG_AO_AP_DMA_CG     43     /* :215 */
#define INFRACFG_AO_DEVICE_APC_CG 45     /* :217 */
```

и `clk-mt6771.c`: `BTIF` → IFR0 бит **31** (:1173), `AP_DMA` → IFR1 бит **18**
(:1206), `DEVICE_APC` → IFR1 бит **20** (:1210). Это ровно те ID, что в стоковом
DT (`0x1b`, `0x2b`, `0x2d`), и наша раскладка верна.

## 6. mainline после возврата (тот же день)

```
$ uname -r
6.12.114-g400cb6f-touch-rot
$ clk_summary | grep -E "infra_btif|infra_device_apc|infra_uart0"
infra_uart0          0  0  0  26000000   ... N   11002000.serial  bus
infra_device_apc     0  0  0  156000000  ... Y   deviceless     
infra_btif           0  0  0  156000000  ... N   deviceless     
```

`infra_btif` и `infra_device_apc` **никем не запрошены** (enable_cnt=0): в
mainline нет драйверов, которые их держат, — в отличие от вендорского ядра, где
их держат `mtk_btif` и `devapc`. Наш glue включает гейт BTIF «сырой» записью в
SET-регистр, а не через CCF, поэтому **родительские клоки (axi_sel/PLL) никто не
включает**.

Регистры/запись (mainline):

```
0x10001090 = 0x9befff5d      (IFR0; бит31 = 1 — гейт стоит)
0x10001094 = 0xc78f7db2      (IFR1; бит20 = 0 — DEVICE_APC не включается)
0x10207f00 = 0x00000000      (APC_CON, запись 0x80000000 не держится)
0x10207000 = 0xffffffff      (VIO_MASK0 — блок жив, нарушений по BTIF нет)
IER ← 0xa5a5a5a5  → 0x00000000   (запись в BTIF по-прежнему отбрасывается)
```

## 7. Вывод

* Дискриминатор «recovery vs mainline» на этой прошивке **не выполним**: в
  recovery нет ни MMIO, ни пользователя BTIF; на стоке тоже нет `CONFIG_DEVMEM`.
* Данных «в recovery записи проходят» **нет** — тест не состоялся (это не
  отрицательный результат).
* Что осталось доказанным: в вендорском ядре `devapc` и `mtk_btif` реально
  работают (оба ioremap'ят свои окна), а в mainline их клоки (`infra_btif`,
  `infra_device_apc`) не запрошены никем, и APC_CON не пишется.

## 8. Следующий шаг (без прошивки)

Идти по нашей стороне: включить BTIF по-настоящему через CCF (чтобы включились
родители), а не сырой записью в гейт. Минимальный вариант без правки DTB —
получить `struct clk` из `of_clk_get()` по узлу `infracfg_ao` и ID 27/43/45
(вендорские номера!) — но в mainline-драйвере mt8183 нумерация другая
(`CLK_INFRA_BTIF = 26`), поэтому корректно это делается только через DT
(`clocks = <&infracfg CLK_INFRA_BTIF>`) — а это правка DTS + перепаковка boot,
т.е. требует согласования с lead.
Альтернатива без DTS: проверить, не отключил ли `clk_disable_unused()` родителя
`axi_sel` (mainline-CCF), и включить цепочку вручную (topckgen/apmixed) — с
проверкой по `clk_summary` до/после.

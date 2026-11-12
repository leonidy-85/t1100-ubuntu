# CONNSYS register dumps, 12.11.2026 (рубеж M7, фаза 5 Wi-Fi)

Снято на планшете (`10.42.66.66`, `6.12.114-g400cb6f-touch-rot`) утилитой
`tools/mempeek` через `mmap(/dev/mem)` (в этом ядре `CONFIG_STRICT_DEVMEM` не
включён; `pread` на MMIO даёт `EFAULT`, поэтому нужен именно `mmap`).

Состояние на момент снятия: `wmt_drv`/`wlan_drv_gen3` загружены, power-on
драйвером «прошёл» (`CONSYS-HW-PWR-ON, finish(0)`), но `wlanProbe` упал на
`-ETIME`/`cpupcr:00000000`.

## 1. До вмешательства (окно «мёртвое»)

```
T1   0x1000632c = 0x00000112   bit1 iso_en=1, bit4 clk_dis=1, bit8 sram_conn_pd=1, bit2/3 pwr_on=0
ACK  0x10006180 = 0x008fff4c   bit1 (conn_top1_pwr_on_ack) = 0
ACKS 0x10006184 = 0x00807f4c   bit1 = 0
PROT 0x100012a0 = 0x18606098   запись-чтение (RW)
PROT 0x100012a4 = 0x18606098   write-1-to-clear зеркало
       bits 13/14 = 0x6000 -> CONN AXI bus protect ВКЛЮЧЕН
RGU  0x10007018 = 0x00000000   CONN CPU SW reset не выставлен
CHIPID 0x18070008 = 0x00000000
CPUPCR 0x18070160 = 0x00000000
WFDMA  0x180f0000 = 0x00000000
SPM  0x10006000 = 0x00000003
```

## 2. После SPM-последовательности (как в вендорском `#if
CONSYS_PWR_ON_OFF_API_AVAILABLE == 0`): `0x1000632c |= 0x0c`

```
T1   0x1000632c = 0x0000011e   bit2 pwr_on=1, bit3 pwr_on_s=1
ACK  0x10006180 = 0x008fff4e   bit1 = 1  <- SPM подтвердил power on
ACKS 0x10006184 = 0x00807f4e   bit1 = 1
CHIPID 0x18070008 = 0x00000000   (окно всё ещё мёртвое: AXI protect)
```

Далее: `T1 &= ~0x10` (clk_dis=0), `T1 &= ~0x2` (iso release), `T1 |= 0x1`
(rst release) →

```
T1   0x1000632c = 0x0000010d
ACK  0x10006180 = 0x408fff4e   bit30 (conn_top2_pwr_on_ack) = 1
PROT 0x100012a4 = 0x00606000   после вендорской записи `read & ~0x6000' -- биты 13/14 ОСТАЛИСЬ
```

## 3. Ключевая находка: `0x100012a4` — write-1-to-clear, `0x100012a0` — RW

```
write 0x100012a4 = 0x00006000   (записать маску, а не «read & ~mask»)
  -> 0x100012a0 = 0x00600000, 0x100012a4 = 0x00600000   bits 13/14 сняты
  -> CHIPID 0x18070008 = 0x00000788   <- CONNSYS отвечает!
write 0x100012a0 = 0x00606000   (обратно, простая RW-запись)
  -> 0x100012a0 = 0x00606000, 0x100012a4 = 0x00606000   protect снова включён
write 0x100012a4 = 0x00006000   -> снова 0x00600000
```

## 4. Живое окно (protect снят, домен включён)

```
0x18070000 = 0x00008a00
0x18070004 = 0x00008a00
0x18070008 = 0x00000788   chip id CONNSYS (ожидание драйвера — 0x0788)
0x18070600 = 0x001702a4   ROM deselect: запись ПРОХОДИТ (readback совпал)
0x180f0000 = 0x00000000   WFDMA
0x180f0004 = 0x00000043
0x180f0008 = 0x00010000
0x180f000c = 0xa07f0000   <- WFDMA отвечает
0x10006180 = 0x408fff4e
0x1000632c = 0x0000010d
```

## 5. Запись в защищённое окно вешает AXI

Пока биты 13/14 в `0x100012a0` выставлены, `mempeek --write 0x18070600 0x1702a4`
**не возвращается** (скрипт снят по `timeout 60`), чтения при этом отдают 0.
То есть «нули» — это не «нет устройства», а дефолтный ответ защищённой шины.

## 6. Инцидент 18:52 UTC

С патчем `patches/wifi/0005` (SPM power-on) `modprobe wlan_drv_gen3 t1100_probe=1`
при **реально включённом** домене CONN повесил ядро наглухо: ping пропал, sshd
не отвечает, USB-gadget (`usb0`, через него идёт сеть) умер, автоматического
ребута нет (`panic=10` не срабатывает — это не panic). Лечится только Power
10 с. Лог прогона остался на устройстве (`/root/wifi-test.log`), снять его
можно после включения.

Что успело отработать до зависания (из предыдущего, «мёртвого» прогона) и что
осталось непроверенным — см. `docs/wifi-port-log.md` §27.

## 7. Живое окно после патча 0005/0006, stage=1 (без `wlanProbe`)

Прогон: `modprobe wlan_drv_gen3 t1100_probe=1 t1100_probe_stage=1 t1100_no_reset=1`
(питание через SPM, `wlanProbe` не вызывается; плата осталась жива).

```
0x1000632c = 0x0000010d    SPM: rst_b=1, iso=0, clk_dis=0, pwr_on=1, sram_pd=1
0x10006180 = 0x408fff4e    top1 ack (bit1) и top2 ack (bit30) — оба есть
0x100012a0 = 0x18600098    CONN AXI protect снят (bits 13/14 = 0)
0x18070008 = 0x00000788    CONNSYS chip id
0x18070038 = 0x00000000    WCIR (ready-бит прошивки) — не выставлен
0x18070078 = 0x000055aa    D2H mailbox 0
0x18070160 = 0x00001170    cpupcr (MCU исполняет код)
0x180f0000 = 0x00000000    WFDMA
0x180f000c = 0xa07f0000    WFDMA отвечает
```

### 7.1 Регуляторы (`/sys/kernel/debug/regulator/regulator_summary`)

```
vcn18   1 use  18070000.consys-vcn18      1800mV
vcn28   1 use  18070000.consys-vcn28      2800mV
vcn33   1 use  18070000.consys-vcn33_bt   3500mV
               18070000.consys-vcn33_wifi    0mV   <- выключен (paldo под #if 0)
```

### 7.2 Клоки (`/sys/kernel/debug/clk/clk_summary`)

```
infra_cqdma       enable=0 prepare=0 156000000 Hz  deviceless
infra_cqdma_fpc   enable=0           156000000 Hz  deviceless
```

Гейт `CLK_INFRA_CQ_DMA` (DTS: `wifi@180f0000.clocks`) не взят никем, а WFDMA
при этом отвечает: для доступа к окну WFDMA он не нужен.

### 7.3 Oops в `wlanNetCreate` (stage=2)

```
wlanNetCreate: net_device prDev(0x…) allocated
Unable to handle kernel write to read-only memory at virtual address ffffff80d83cd008
pc : netif_tx_stop_all_queues+0x2c/0x80
lr : wlanProbe+0x138/0xeb0 [wlan_drv_gen3]
```

`modprobe` получил SIGSEGV (`rc=139`), ядро ушло в oops и перезагрузилось
(`journalctl -k -b -1`).

# M28 — BTIF через CCF, XO_WCN и домен CONNSYS: записи всё равно теряются (13.11)

Проверка гипотезы «гейт открыт сырым битом, а цепочку родителей никто не
включает» — и заодно XO_WCN/`DCXO_CONN_ENABLE` и живой домен CONNSYS.

## 1. CCF: `infra_btif` / `infra_device_apc` по-настоящему

В glue добавлен `m23_ccf` (`of_clk_get_from_provider` от узла
`mediatek,mt8183-infracfg` по ID mt8183-нумерации: `CLK_INFRA_BTIF = 26`,
`CLK_INFRA_DEVICE_APC = 44`, `include/dt-bindings/clock/mt8183-clk.h`) +
`clk_prepare_enable`. DT не правился, boot не прошивался.

`clk_summary` до/после (один прогон, `m23_ccf=1`):

```
ДО:
  axi_sel             enable 4  prepare 6   156000000  hw=Y
  infra_device_apc    enable 0  prepare 0   156000000  hw=Y   deviceless
  infra_btif          enable 0  prepare 0   156000000  hw=N   deviceless

ПОСЛЕ:
  axi_sel             enable 6  prepare 8   156000000  hw=Y
  infra_device_apc    enable 1  prepare 1   156000000  hw=Y   con_id=of_clk_get_from_provider
  infra_btif          enable 1  prepare 1   156000000  hw=N   con_id=of_clk_get_from_provider

dmesg:
  m23-ccf: infra_btif (id 26) before: rate=156000000 parent=axi_sel rate=156000000
  m23-ccf: infra_btif clk_prepare_enable -> 0, rate=156000000
  m23-ccf: infra_device_apc (id 44) ... same
```

То есть **CCF-путь работает** (enable_cnt стал 1, родитель `axi_sel` = 156 МГц,
enable_cnt 6/8) — но `infra_btif` в `clk_summary` так и остаётся `hw=N`, хотя
сырое чтение `0x10001090` даёт бит31 = 1 (`0x9befff5d`), а `0x10001080` (SET)
читается тем же значением. Расхождение «CCF hw=N vs бит31=1» — открытый вопрос
(см. §5).

## 2. XO_WCN и домен CONNSYS

```
pwrap+0x184 = 0x00000003      (бит1 DCXO_CONN_ENABLE уже стоит)
после modprobe wlan_drv_gen3 t1100_probe=1 t1100_probe_stage=1:
  cpupcr 0x18070160 = 0x00001170     (MCU жив, ROM крутится)
  chipid 0x18070008 = 0x00000788
```

`0x1000d44e` (TOP_SPI_CON1) читать через `/dev/mem` нельзя — SIGBUS (это pwrap-
командное окно, доступ идёт через `pwrap+0x188`-интерфейс).

## 3. BTIF before -> after `hal_btif_hw_init()` (CCF вкл., CONSYS вкл.)

```
RBR/THR   0x00: 0x00000000 -> 0x00000000
IER       0x04: 0x00000000 -> 0x00000000     <- hw_init пишет RX-IER=1, не легло
IIR/FCR   0x08: 0x00000001 -> 0x00000001
LCR       0x0c: 0x00000000 -> 0x00000000
LSR       0x14: 0x00000060 -> 0x00000060
SLEEP_EN  0x48: 0x00000000 -> 0x00000000
DMA_EN    0x4c: 0x00000000 -> 0x00000000     <- hw_init пишет AUTORST(bit2), не легло
RTOCNT    0x54: 0x00000040 -> 0x00000040
TRI_LVL   0x60: 0x0000005a -> 0x0000005a     <- должно стать 0x18/0x5a по уровням
WAK       0x64: 0x00000001 -> 0x00000001
WAT_TIME  0x68: 0x00000012 -> 0x00000012
HANDSHAKE 0x6c: 0x00000003 -> 0x00000003
```

Прямые записи после этого (CONSYS включён, CCF включён):

```
0x1100c004 <- 0xa5a5a5a5  -> 0x00000000
0x1100c060 <- 0xda        -> 0x0000005a
```

## 4. Вывод

Ни CCF-цепочка (`axi_sel` 156 МГц, `infra_btif` enable=1), ни `DCXO_CONN_ENABLE`,
ни включённый домен CONNSYS (`cpupcr=0x1170`, `chipid=0x788`) **не делают
регистры BTIF записываемыми**. Критерий «`TRI_LVL` стал 0x18» не достигнут,
значит STP-цепочку запускать нельзя: байты по-прежнему не покидают SoC.

## 5. Что осталось подозревать (по коду, без правок)

1. **Расхождение CCF `hw=N` при бите31=1.** В mainline mt8183-таблица для
   `CLK_INFRA_BTIF` — IFR0 бит31 (`clk-mt8183.c:725`), статус — `sta_ofs=0x90`
   (`:649-653`); ровно этот бит мы читаем как 1. Значит либо `is_enabled` для
   этого гейта считает иначе (`mtk_clk_gate_ops_setclr`), либо регистр статуса на
   MT6771 другой. Если гейт всё-таки закрыт — это и есть причина write-dead.
2. **Третья частота BTIF.** В DT есть только `btifc`/`apdmac`; возможно,
   функциональный клок блока идёт из CONNSYS-домена (гейт, который включает MCU
   при инициализации BT), — тогда запись не пройдёт до того, как чип сам
   разрешит BTIF (замкнутый круг с патчем).
3. **Write-protect на уровне APB-слейва** (DMPU/ATF), не оставляющий VIO:
   `APC_CON` не пишется, VIO_MASK включён (0xffffffff), но VIO_STA/DBG = 0.
4. **Наша модель блока**: `IER`/`DMA_EN`/`TRI_LVL` могут быть write-only/RO на
   MT6771 — тогда «записи не легли» надо проверять по поведению (IRQ, FIFO), а
   не по readback. Но 40 записей в THR не заполняют FIFO (`LSR=0x60`) — это
   поведенческое доказательство, что записи действительно не доходят.

## 6. Артефакты

`mtk_btif_drv.ko` (CCF-сборка) sha256
`75be5e4f1dda61ca47ee790809ddf339d043d2884cee818cebf94aba6f1f6e3c`; прогон —
`/root/m28.log`, `/root/m28-regs.txt` на планшете.

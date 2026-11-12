# M23 — BTIF как транспорт STP (13.11)

Справочник по рубежу M23: что за блок, какие регистры/клоки, чем подтверждено,
где остановились. Основной отчёт — `docs/wifi-port-log.md` §44.

## 1. Блок: BTIF @ 0x1100c000 (UART-подобный контроллер + AP-DMA)

Стоковый DT, `refs/stock-mt6771.dts:2198`:

```dts
btif@1100c000 {
	compatible = "mediatek,btif";
	reg = <0x00 0x1100c000 0x00 0x1000 0x00 0x11000a80 0x00 0x80 0x00 0x11000b00 0x00 0x80>;
	interrupts = <0x00 0x72 0x08 0x00 0x8b 0x08 0x00 0x8c 0x08>;
	clocks = <0x15 0x1b 0x15 0x2b>;
	clock-names = "btifc", "apdmac";
};
```

Т.е. три окна (`btif`, TX AP-DMA, RX AP-DMA) и три SPI: 0x72=114 (btif),
0x8b=139 (tx dma), 0x8c=140 (rx dma). Адресный порядок «reg[1] = TX,
reg[2] = RX» — из публичного порта (`btif_dma_plat.c`: `of_iomap(node, 1)` в
ветке `DMA_DIR_TX`, `of_iomap(node, 2)` в ветке `DMA_DIR_RX`).

Регистры (публичный порт, `btif/plat_inc/btif_priv.h:31-58`):

| смещ. | имя | смысл |
|---|---|---|
| 0x00 | RBR/THR | приём/передача (PIO) |
| 0x04 | IER | enable: bit0 RX, bit1 TX |
| 0x08 | IIR / FCR | read: IIR (`0x1` = нет прерывания), write: сброс FIFO |
| 0x0c | FAKELCR | 0 = normal mode |
| 0x14 | LSR | bit0 DR, bit5 THRE, bit6 TEMT |
| 0x48 | SLEEP_EN | |
| 0x4c | DMA_EN | bit0 RX DMA, bit1 TX DMA, bit2 autorst |
| 0x54 | RTOCNT | Rx timeout count |
| 0x60 | TRI_LVL | tx/rx trigger level + loopback (bit7) |
| 0x64 | WAK | write-only, импульс wake к CONNSYS |
| 0x68 | WAT_TIME | async wait time |
| 0x6c | HANDSHAKE | bit0 = new handshake |

## 2. Read-only проверка на железе (до первого TX)

`tools/mempeek --mmap`, загрузка mainline `6.12.114-g400cb6f-touch-rot`,
CONNSYS в ROM после штатного probe `wlan_drv`:

```
0x1100c000=0x00000000   0x1100c008=0x00000001   0x1100c014=0x00000060
0x1100c04c=0x00000000   0x1100c054=0x00000040   0x1100c060=0x0000005a
0x1100c064=0x00000001   0x1100c068=0x00000012   0x1100c06c=0x00000003
0x11000a80..0x11000a8c = 0
0x11000b00..0x11000b0c = 0
```

`LSR = 0x60` (THRE|TEMT) и `IIR = 0x1` — блок отвечает, т.е. **`btifc`
включён**. Клоки подтверждены статусными регистрами INFRACFG_AO:

```
0x10001090 = 0x9befff5d   bit31 = 1  -> IFR2 btif  on
0x10001094 = 0xc78f7db2   bit18 = 1  -> IFR3 ap_dma on
```

Раскладка гейтов — семейная mt6765/6771 (`drivers/clk/mediatek/clk-mt6765.c:522-544`:
IFR2 set/clr/sta = 0x80/0x84/0x90, IFR3 = 0x88/0x8c/0x94; `CLK_IFR_BTIF` — бит
31 IFR2, `CLK_IFR_AP_DMA` — бит 18 IFR3). В mainline для MT6771 клок-драйвера
нет (порт наследует `mediatek,mt8183-*`), поэтому гейты пишутся напрямую из
нашего glue (`m23_clk_enable()`); запись идемпотентна.

## 3. IRQ: номер SPI нельзя скармливать request_irq(2)

`request_irq(114)` на этой плате попадает в домен `mt-eint`:

```
gpio gpiochip0: (pinctrl_paris): gpiochip_lock_as_irq: tried to flag a GPIO set as output for IRQ
mt8183-pinctrl 10005000.pinctrl: unable to lock HW IRQ 88 for IRQ
genirq: Failed to request resources for mtk btif irq (irq 114) on irqchip mt-eint
MTK-BTIF[E]_btif_controller_setup(1516):_btif_irq_reg failed, i_ret(-5)
```

Устройства на этом SoC — дети домена `sysirq` (`mediatek,mt8183-sysirq`,
`mt8183.dtsi:21` `interrupt-parent = <&sysirq>`), у которого hwirq = номер SPI.
Без DT-узла правильный путь — `irq_create_fwspec_mapping()` с ячейками
`<GIC_SPI n IRQ_TYPE_LEVEL_LOW>` (`m23_irq_map()`): SPI 114 → virq 395,
139 → 396, 140 → 397; `/proc/interrupts` показывает их как
`MT_SYSIRQ 114 Level  mtk btif irq`.

## 4. Код и артефакты

- Публичный порт: `/home/l/wifi-src/rb/drivers/staging/mtk-connectivity/btif`
  (mt6765 Rabbit, mainline-стиль) — компилируется под 6.12 без правок
  (`mtk_btif_drv.ko`, GPL).
- Наш glue: `scripts/remote/m23-btif/` (`m23_board.c/.h`, `Makefile`,
  `0010-btif-mt6771-glue.patch`), сборка — `scripts/build-btif-remote.sh`.
- wmt/wlan: `patches/wifi/0010-common-btif-stp.patch`,
  `patches/wifi/0010-wlan-pwr-on-done.patch`,
  `scripts/remote/wifi-kbuild/common.Kbuild` (+`stp_btif.o`).
- WMT-вызовы (`wmt_ic_soc.c`): `WMT_PATCH_ADDRESS_CMD` (ROMv4 base
  `[8..9] = 0x18/0x05`), `mtk_wcn_soc_normal_patch_dwn()`,
  заголовок файла `struct wmt_rom_patch` = 48 Б (`wmt_core.h:428`):
  `ucDateTime[16] ucPLat[4] u2HwVer u2SwVer u4PatchAddr u4PatchType u4CRC[4]`.

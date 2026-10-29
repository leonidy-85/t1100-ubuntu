# refs/ — референсные артефакты

Файлы здесь — **факты с устройства/из публичных источников**, нужные для порта.
Не редактировать вручную без пометки источника.

| Файл | Что это | Источник |
|---|---|---|
| `stock-mt6771.dts` | полный DTS стокового DTB (Aurora 5.1.6.110), снят из `boot_a` | `scripts/bootimg_extract.py` из `../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img`, DTB = 111095 B (внутри 64-байтный MTK-заголовок, срезан) |
| `es6311_anx6585_zigzag_wxga.c` | LCM-драйвер **другого** продукта (Unplugged, «zigzag_wxga», 800x1280). Использовать только как образец структуры LCM/DSI-параметров | `os.unplugged.com/werunplugged/unplugged-kernel` @ `d30235b0` |
| `it6112/panel-it6112-boe-tv110xum-lb2.c` | **WIP-драйвер нашей панели** (BOE TV110XUM-LB2 через мост ITE IT6112), 515 строк: init моста, DCS, тайминги 1600×2176 | `linux-mediatek/linux` @ `935fe30b25b0e261235c838ca08f409ceff87b1a` (ветка `adomerle/mt6771-next`), автор Arseniy Velikanov — см. `it6112/README.md` |
| `mt6771-next/mt6771.dtsi` | `#include "mt8183.dtsi"` + `compatible = "mediatek,mt6771"` и удаление cpufreq/idle — доказательство, что MT8183-драйверы используются для MT6771 | `linux-mediatek/linux` @ ветка `adomerle/mt6771-next` — см. `mt6771-next/README.md` |
| `mt6771-next/mt8788-fplus-t1100.dts` | **полный board DTS нашего планшета** (868 строк): тач, HDMI IT66121, MT6370, MMC, USB, PWM, панель, `simple-framebuffer` | там же |
| `mt6771-next/patches/` | 12 патчей ветки (DTS, панель, тач HX83102E, cpufreq, svs, regulator-coupler, звук, USB role-switch) | там же, `<sha>-<slug>.patch` |

## Как пересоздать stock DTS

```sh
python3 scripts/bootimg_extract.py \
  --image ../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img \
  --outdir build/stock
dtc -I dtb -O dts -o build/stock/stock.dts build/stock/dtb
```

Стоковый DTB содержит `compatible = "mediatek,mt6771"` и полную карту
MMSYS/DISPSYS (см. `docs/hardware.md`) — это основной регистровый референс
вместе с downstream-исходниками.

Если `../t1100/backup_5.1.6.110/` нет, годится любой стоковый образ планшета,
например `../1100/boot_a.bin` (Aurora 5.1.6.110, sha256 `92875f51…492c`);
его DTB совпадает с `stock-mt6771.dts` побайтово после декомпиляции.

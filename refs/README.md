# refs/ — референсные артефакты

Файлы здесь — **факты с устройства/из публичных источников**, нужные для порта.
Не редактировать вручную без пометки источника.

| Файл | Что это | Источник |
|---|---|---|
| `stock-mt6771.dts` | полный DTS стокового DTB (Aurora 5.1.6.110), снят из `boot_a` | `scripts/bootimg_extract.py` из `../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img`, DTB = 111095 B (внутри 64-байтный MTK-заголовок, срезан) |
| `es6311_anx6585_zigzag_wxga.c` | LCM-драйвер **другого** продукта (Unplugged, «zigzag_wxga», 800x1280). Использовать только как образец структуры LCM/DSI-параметров | `os.unplugged.com/werunplugged/unplugged-kernel` @ `d30235b0` |

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

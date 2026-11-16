# HDMI на T1100 (DPI0 → ITE IT66121)

Планшет выводит картинку на HDMI через мост **ITE IT66121**, подключённый к
**DPI0** (12-битная шина DBPI), i2c3 (`i2c@1100f000`) по адресу `0x4c`,
reset — GPIO79. Факты взяты из стока
(`refs/mt6771-next/mt8788-fplus-t1100.dts`).

## Что было не так

В нашем DTS не хватало двух board-переключателей питания HDMI:

| регулятор | GPIO | назначение |
|---|---|---|
| `hdmi_vdd` | 53 | 5 В на HDMI |
| `hdmi_gate` | 52 | гейт 5 В, `hdmi-pwr-supply` коннектора |

Без них мост обесточен: I2C-скан не видел ACK на `0x4c`, `it66121_probe`
возвращал `-ENODEV` (не совпал vendor id), `mediatek-dpi` уходил в
`deferred probe: Failed to get bridge`.

## Что добавлено (патч 0078)

- `hdmi-connector` (`type = "d"`) c `hdmi-pwr-supply = <&hdmi_gate>`;
- `dpi_func_pins` / `dpi_idle_pins` (GPIO13..28, DBPI D0..D11/HSYNC/VSYNC/DE/CK);
- `ite_pins` (GPIO79) и узел `dpi0` со `status = "okay"`;
- `&dpi_out` → `it66121_in` (bus-width 12);
- `hdmitx@4c` на `i2c3` с `vcn33/vcn18/vrf12`, `reset-gpios`, `ports`;
- `regulator-fixed` `hdmi_vdd` (GPIO53, 5 В) и `hdmi_gate` (GPIO52, vin `hdmi_vdd`).

## Результат

`build/hdmi/boot_hdmi2.img` (sha256 `ad15946b…`, p29):

```
it66121 3-004c: IT66121 revision 1 probed
mediatek-dpi 14015000.dpi: Found bridge node: /soc/i2c@1100f000/hdmitx@4c
mediatek-drm: bound 14015000.dpi (ops mtk_dpi_component_ops)
```

`/sys/class/drm/card1-HDMI-A-1`: `connected`, `enabled`, режим 1280x720@60.
`kscreen-doctor -o` показывает второй выход (`geometry 1451,0 1280x720`) —
рабочий стол расширяется на телевизор/монитор.

## Ограничения и откат

- Звук по HDMI не подключён: в dmesg `No "#sound-dai-cells", no audio`;
  для звука нужен ASoC-линк `mt_soc_hdmi_pcm` и правка DAI.
- Откат: `build/wifi-image2/boot_wifi2.img` (`d9a1f402…`) через
  `tools/host/recovery.py` или `dd` в `p29`.
- DTB собирать только с абсолютным `O=`:
  `make -C src-nonwifi O=/home/l/t1100-ubuntu-build/out-wifi ARCH=arm64 \
   CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION= mediatek/mt6771-fplus-t1100.dtb`

# refs/mt6771-next — WIP-порт MT6771/FPlus T1100 в linux-mediatek

## Источник

| Поле | Значение |
|---|---|
| Репозиторий | `github.com/linux-mediatek/linux` |
| Ветка | `adomerle/mt6771-next` (base **6.16.0**) |
| Автор | Arseniy Velikanov `<me@adomerle.pw>`, 2025 |
| Статус | **WIP**, не отправлено в mainline |

Скопированы без изменений:

| Файл | Строк | sha256 |
|---|---|---|
| `mt6771.dtsi` | 41 | `231d99bc…542e6` |
| `mt8788-fplus-t1100.dts` | 868 | `aece7f99…71152` |

## Главное

Это **тот же продукт** (FPlus T1100), поэтому board DTS — самый ценный
референс: в нём есть всё, чего нет у нас (тач, HDMI, PMIC, зарядка, USB,
MMC, регуляторы, PWM, панель).

### `mt6771.dtsi` — 41 строка, и это ответ на вопрос про драйверы

```dts
#include "mt8183.dtsi"
/ {
        compatible = "mediatek,mt6771";
        cpus { ... /* удалены cpu-idle-states и operating-points-v2 */ };
};
```

То есть в ветке **нет** `clk-mt6771`/`pinctrl-mt6771`/`mt6771-mmsys`: весь
MT8183-инфраструктурный слой (`topckgen`, `infracfg_ao`, `pericfg`,
`apmixedsys`, `mfgcfg`, `mmsys`, `pio`, `mt6358`, DISPSYS, GPU) взят из
`mt8183.dtsi` как есть, а `mt6771.dtsi` лишь переопределяет `compatible` и
убирает cpufreq/idle («cpuidle & cpufreq are broken with android firmware»).

Вывод для нас: переиспользование MT8183-драйверов — не гипотеза, а подход,
на котором уже собран рабочий (по заявлению автора) порт. Наш отдельный
`clk-mt6771` может не понадобиться на первом этапе: достаточно подключить
`mt8183.dtsi` и проверить на железе.

### `mt8788-fplus-t1100.dts` — что в нём есть

- `compatible = "fplus,t1100", "mediatek,mt8788"`, `chassis-type = "tablet"`.
- `/chosen/framebuffer@7cb80000` — `simple-framebuffer` 1600×2176, a8r8g8b8,
  ссылка на `&panel` (важно: **0x7cb80000**, а не 0x7cd80000 из стокового
  резерва; см. ниже).
- `backlight`: `pwm-backlight`, `pwms = <&pwm0 0 500000>`,
  `enable-gpios = <&pio 56>`, 1023 уровня, default 576.
- `panel@56` на `i2c3`: `boe,tv110xum-lb2-it6112`, `reset-gpios = <&pio 45>`,
  `dvdd/vpos/vneg` = `panel_dvdd` (GPIO55) / `mt6370_dsvpos` / `mt6370_dsvneg`,
  `port/panel_in -> dsi_out`; `status = "disabled"` (WIP).
- `i2c0`: тач `himax,hx83102e` @0x48, `interrupts-extended = <&pio 1
  IRQ_TYPE_LEVEL_LOW>`, `reset-gpios = <&pio 0>`, `vdd = mt6358_vldo28`.
  (В стоковом overlay reset был GPIO158 — здесь GPIO0: расхождение, проверить
  на железе.)
- `i2c3`: `ite,it66121` HDMI-мост @0x4c, вход с `&dpi0` (12 бит), `reset GPIO79`,
  питание `vcn33/vcn18/vrf12`; `hdmi-connector` + `hdmi_vdd`/`hdmi_gate`
  (GPIO53/52).
- `i2c5`: PMIC **MT6370** @0x34 — зарядник, TCPC/USB-C, DSV-регуляторы
  (`dsvpos`/`dsvneg`), LED/flashlight, ADC.
- `i2c6`: `sgmicro,sgm41513`; `i2c1`: датчики (закомментированы);
  `i2c4`: камера `galaxycore,gc08a3` + `nxp,pn544` (disabled).
- `mmc0` (eMMC, HS400, `hs400-ds-delay = <0x12814>`) и `mmc1` (SD, `cd-gpios =
  <&pio 3>`), регуляторы MT6358.
- `usb`: `ssusb` в `peripheral`, USB2 only; `usb_host`; TCPC через MT6370.
- `gpio-keys`: Volume Down на `&pio 93`; `mt6358keys` — Volume Up.
- Удалены `&scp`, `&vcodec_dec`, `&vcodec_enc` (Android SCP firmware
  несовместима с upstream; LK ставит EMIMPU на регион SCP).
- `&iommu { status = "disabled"; }` — «IOMMU breaks simple-framebuffer on latest
  linux-next».

## Расхождения с нашим DTS (учитывать при переносе)

| Что | У нас (`patches/0001`) | adomerle |
|---|---|---|
| Framebuffer | резерв `0x7cd80000` (из live FDT) | `simple-framebuffer` @ `0x7cb80000` |
| PSCI | добавлен патчем 0003 (`arm,psci-1.0`, smc) | наследуется из `mt8183.dtsi` |
| Часы/pinctrl | отсутствуют (пишем `clk-mt6771`) | целиком MT8183 |
| PMIC | только узлы в stock DTS | `mt6358.dtsi` + `mt6370` |
| Bootargs | `maxcpus=1 panic=10 pstore...` | не задаёт (грузит дистрибутив) |

## Полный набор патчей ветки (`patches/`)

База ветки — **linux-next 20250808** (`b1549501…`), не чистый 6.16. Помимо двух
DTS и панели там есть ещё девять вещей по нашему планшету (скачаны как
`<sha>-<slug>.patch`):

| Патч | Что содержит | Зачем нам |
|---|---|---|
| `1ef72e97b1-add-mt6771-dtsi` | `mt6771.dtsi` = `#include "mt8183.dtsi"` + `compatible` | подтверждает переиспользование MT8183 |
| `2aee822a91-add-fplus-t1100-dts` | полный board DTS | тач, HDMI, PMIC, MMC, USB, PWM |
| `083d4e7fa2-panel-it6112` | драйвер панели IT6112 (WIP) | панель без RE |
| `0f649f913f-touchscreen-hx83102e` | HX83102E в `himax_hx83112b.c` | **тач** (mainline-драйвер знает только hx83112b) |
| `41dd7e6871-touchscreen-vdd-supply` | `vdd`-регулятор для тача | питание тача |
| `5aaf4f5475` / `6a9a887e29` | dt-bindings: compatible `hx83102e`, `vdd-supply` | биндинги к тачу |
| `4bc5483278-cpufreq-mt6771-compat` | `mediatek,mt6771` в `mediatek-cpufreq` | cpufreq (в dtsi отключён: «broken with android firmware») |
| `86c0a60f75-svs-mt6771` | MT6771 в `mtk-svs` | Smart Voltage Scaling |
| `ee51e22b85-regulator-coupler-mt6771` | MT6771/MT8788 в `mtk-regulator-coupler` | связка GPU/proc-регуляторов |
| `f8bbc91fcf-sound-es7210` | `mt8183-mt6358-es7210` | звук (не-цель v1, но есть) |
| `96fe48bed8-tphy-role-switch` | role switching в `phy-mtk-tphy` | USB host/device, нужен для RNDIS/сети в ядре |

Плюс `2bca98ef53` «firmware: efi: earlycon: Use ARGB» — earlycon на
EFI-framebuffer; для нас не применимо (мы грузимся не через EFI), поэтому
патч не скачан.

## Ограничения

- Ветка **linux-next 20250808** (Makefile 6.16.0), мы на **6.12.114**: часть
  биндингов/хелперов может отсутствовать; переносить по частям, а не
  копированием.
- Код WIP: не принимать как эталон качества, только как источник фактов и
  проверенных на устройстве решений.
- Утверждение «работает» — со слов автора/ветки, нами не проверено.

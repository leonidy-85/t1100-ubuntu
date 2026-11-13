# MT6370: инвентарь управления зарядом (офлайн, по исходникам)

Источник — `drivers/power/supply/mt6370-charger.c`,
`drivers/usb/typec/tcpm/tcpci_mt6370.c`,
`drivers/iio/adc/mt6370-adc.c`, `drivers/usb/typec/tcpm/tcpm.c` из дерева
`t1100-merge3-src` на build-хосте; файлы `mt6370-charger.c`,
`tcpci_mt6370.c`, `mt6370-adc.c` в merge2 и merge3 **идентичны** (проверено
`cmp`), поэтому цитаты и номера строк одинаковы для прошитого ядра
(`6.12.114-g400cb6f-touch-rot`) и для ещё не прошитого merge3.

Дата: 13.11.2026. Плата в момент написания недоступна (ping — 1 пакет, 0
ответов), поэтому всё ниже — из кода, не с железа.

## 1. Что реально можно записать через sysfs

`mt6370_chg_set_property()` (`mt6370-charger.c:655`) принимает **семь**
свойств, и это всё:

```c
case POWER_SUPPLY_PROP_ONLINE:                    /* set_online, см. §2 */
case POWER_SUPPLY_PROP_CONSTANT_CHARGE_CURRENT:   /* F_ICHG, 0x117[7:2] */
case POWER_SUPPLY_PROP_CONSTANT_CHARGE_VOLTAGE:   /* F_VOREG, 0x114[7:1] */
case POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT:       /* F_IAICR, 0x113[7:2] */
case POWER_SUPPLY_PROP_INPUT_VOLTAGE_LIMIT:       /* F_VMIVR, 0x116[7:1] */
case POWER_SUPPLY_PROP_PRECHARGE_CURRENT:         /* F_IPREC, 0x118[3:0] */
case POWER_SUPPLY_PROP_CHARGE_TERM_CURRENT:       /* F_IEOC,  0x119[7:4] */
default:
	return -EINVAL;
```

В задаче упомянуты сеттеры `CHARGE_TYPE` и `USB_TYPE` — **их нет**:
`get_charge_type()`/`get_property(USB_TYPE)` только читают (`F_CHG_STAT` +
`F_VBAT_LVL` для `charge_type`, `priv->psy_usb_type` для `usb_type`),
в `set_property()` этих case нет, а `property_is_writeable()` для них
возвращает 0. То есть «поставить Fast вместо Trickle» нельзя — это следствие
состояния чипа (`CHG_STAT` + флаг `VBAT_LVL`), а `USB_TYPE` — результат BC1.2,
а не наша запись.

## 2. Лимиты IAICR и ICHG (главное)

Диапазоны объявлены как `linear_range`
(`mt6370-charger.c:133-139`):

```c
LINEAR_RANGE_IDX(MT6370_RANGE_F_IAICR, 100000, 0x0, 0x3F, 50000),
LINEAR_RANGE_IDX(MT6370_RANGE_F_VOREG, 3900000, 0x0, 0x51, 10000),
LINEAR_RANGE_IDX(MT6370_RANGE_F_VMIVR, 3900000, 0x0, 0x5F, 100000),
LINEAR_RANGE_IDX(MT6370_RANGE_F_ICHG,  900000, 0x08, 0x31, 100000),
LINEAR_RANGE_IDX(MT6370_RANGE_F_IPREC, 100000, 0x0, 0x0F, 50000),
LINEAR_RANGE_IDX(MT6370_RANGE_F_IEOC,  100000, 0x0, 0x0F, 50000),
```

`value = min + (sel - min_sel) * step`, максимум = значение при `max_sel`
(`lib/linear_ranges.c: linear_range_get_max_value`):

| Поле | Регистр | Биты | Мин | Шаг | Макс | Макс по коду |
|---|---|---|---|---|---|---|
| `IAICR` (input_current_limit) | `CHG_CTRL3` 0x113 | [7:2] | 100 мА | 50 мА | `0x3F` | **3 250 000 мкА = 3.25 А** |
| `ICHG` (constant_charge_current) | `CHG_CTRL7` 0x117 | [7:2] | 900 мА | 100 мА | `0x31` | **5 000 000 мкА = 5 А** |
| `VOREG` (constant_charge_voltage) | `CHG_CTRL4` 0x114 | [7:1] | 3.90 В | 10 мВ | `0x51` | 4.71 В |
| `VMIVR` (input_voltage_limit) | `CHG_CTRL6` 0x116 | [7:1] | 3.90 В | 100 мВ | `0x5F` | 13.4 В |
| `IPREC` | `CHG_CTRL8` 0x118 | [3:0] | 100 мА | 50 мА | `0x0F` | 850 мА |
| `IEOC` | `CHG_CTRL9` 0x119 | [7:4] | 100 мА | 50 мА | `0x0F` | 850 мА |

То есть ответ на «4 А? 2 А?»: **чип позволяет 5 А заряда и 3.25 А входа**, но
это пределы регистров, а не батареи. Вендор (стоковый DTB) ставил 2 А заряда
и 500 мА входа — см. §5.

### Как драйвер округляет (важно для «sysfs принял»)

`mt6370_chg_field_set()` (`:203`) для всех полей, кроме `VMIVR`, зовёт
`linear_range_get_selector_within()`, которая **не возвращает ошибку**:
значение вне диапазона зажимается к краю, а внутри диапазона — **округление
вниз** к шагу:

```c
if (r->min > val) { *selector = r->min_sel; return; }
if (linear_range_get_max_value(r) < val) { *selector = r->max_sel; return; }
*selector = (val - r->min) / r->step + r->min_sel;
```

Следствия:

- запись `input_current_limit=5000` (мкА) молча даст 100 мА, а
  `constant_charge_current=4000000` — 4 А, без ошибки;
- писать надо кратными: IAICR — 50 мА, ICHG — 100 мА; иначе получится
  меньше заказанного (например, 950 мА → 900 мА);
- **проверка факта обязательна**: перечитать `input_current_limit` /
  `constant_charge_current` и, главное, `ibus`/`vbat`/`ibat` из IIO.

## 3. Что драйвер делает сам при probe

`mt6370_chg_init_setting()` (`:781`):

```c
mt6370_chg_field_set(priv, F_USBCHGEN, 0);   /* USB CHG EN выключен до attach */
mt6370_chg_field_set(priv, F_ILIM_EN, 0);    /* ILIM выключен ... */
mt6370_chg_field_set(priv, F_ICHG, 900000);  /* ICHG/IEOC workaround: <900 мА нельзя */
mt6370_chg_field_set(priv, F_IINLMTSEL, 2);  /* лимит входа берётся из IAICR */
```

И всё. **CV (`VOREG`), IEOC, IPREC, MIVR драйвер не трогает** — они остаются
такими, какими их оставили preloader/LK/заводской Android (на практике
`constant_charge_voltage` читается 4 350 000 мкА, см. §6).

`F_AICR_EN` драйвер тоже не пишет; аппаратный дефолт = 1, поэтому запись
`IAICR` действует (подтверждено на железе: 900 мА → `ibus` ≈ 750 мА).

DT-свойств `mediatek,chg-*` **нет**: макрос `MT6370_CHG_DT_PROP_DECL`
(`:816`) объявлен, но не используется ни в одной таблице и ни одним вызовом
`of_property_*` — единственный `of_parse_cb` в файле относится к
OTG-регулятору. Лимиты в DTS для charger'а задать нельзя, только
userspace/юнитом.

## 4. `online`, BC1.2 и `usb_type`

- `online` — **записываемое** свойство (`mt6370_chg_set_online`, `:511`).
  `echo 1 > online` заново запускает attach → `F_USBCHGEN=1` → прерывание
  `attach_i` → `bc12_work` → чтение `USB_STATUS1[6:4]`. Это единственный
  способ «переопросить» BC1.2, если состояние залипло. Писать `0` нельзя без
  причины: это детач, заряд встанет.
- `usb_type` (`:288-306`): `SDP`/`SDP_NSTD` → `POWER_SUPPLY_USB_TYPE_SDP`,
  `DCP` → `DCP`, `CDP` → `CDP`, иначе `UNKNOWN`. BC1.2-класс **не меняет
  IAICR** — драйвер лимит входа по классу порта не выставляет (это делает
  вендорская зарядная политика, которой в mainline нет). Поэтому «SDP 500 мА»
  — это просто дефолт регистра, а не следствие детекта.
- `charge_type` (`:477`): `CHG_STAT == CHARGE_IN_PROGRESS` и `VBAT_LVL=1` →
  `Fast`, `VBAT_LVL=0` → `Trickle`; при `READY`/`DONE`/`FAULT` → `None`.
  То есть `charge_type=Fast` — просто «идёт заряд, vbat выше порога
  precharge-to-fast», а не «быстрый заряд по PD».

## 5. Вендорские значения (стоковый DTB — `refs/stock-mt6771.dts:4371`)

```
charger { compatible = "mediatek,mt6370_pmu_charger";
	ichg = <0x1e8480>;   /* 2 000 000 мкА = 2 А   */
	aicr = <0x7a120>;    /*   500 000 мкА = 500 мА */
	mivr = <0x432380>;   /* 4 400 000 мкВ = 4.4 В  */
	cv   = <0x426030>;   /* 4 350 000 мкВ = 4.35 В */
	ieoc = <0x249f0>;    /*   150 000 мкА = 150 мА */
	safety_timer = <0x14>; enable_te; enable_wdt; ... };
```

Полезно как «заводская база»: 2 А заряда, 500 мА входа, 4.35 В CV,
150 мА терминации. Наш mainline-драйвер из этого воспроизводит только
`ICHG=900 мА` (workaround) и оставляет CV/IEOC от прошивальщика.

## 6. Состояние на прошитом ядре (из `docs/STATUS.md`, факты с железа)

```
mt6370-charger: online=1 status=Charging charge_type=Fast
                constant_charge_current=900000  constant_charge_voltage=4350000
                input_current_limit=500000      (после power-guard — 900000)
                vbus 4940 мВ, vbat 3645 мВ, ibus 400 мА
```

`docs/STATUS.md:863` — те же значения; `13.11 (18)` — при `IAICR=900000`
вход ≈750 мА / 3.5 Вт, в батарею ≈400 мА. Это и есть текущий потолок:
**вход ограничен не чипом (3.25 А), а источником (USB-порт ноутбука, SDP) и
нашим IAICR**.

## 7. ADC (IIO): чем измерять «факт»

`drivers/iio/adc/mt6370-adc.c`, каналы и метки:

| # | метка | что | scale |
|---|---|---|---|
| 0 | `vbusdiv5` | VBUS/5 | 25 → мВ |
| 1 | `vbusdiv2` | VBUS/2 | 10 → мВ |
| 2 | `vsys` | VSYS | 5 → мВ |
| 3 | `vbat` | VBAT | 5 → мВ |
| 4 | `ts_bat` | NTC-делитель | 25/10000 (не температура) |
| 5 | `ibus` | входной ток | 5000/100 = **50 мА/ед** при AICR ≥ 400 мА; 3350/100 = 33.5 мА/ед при AICR ≤ 350 мА |
| 6 | `ibat` | ток батареи | 50 мА/ед при ICHG ≥ 900 мА; 26.8 мА/ед при 500–800 мА; 23.75 мА/ед при 100–400 мА |

Тонкость: `mt6370_adc_read_scale()` для `IBUS`/`IBAT` **читает текущее
значение IAICR/ICHG** (`CTRL3`/`CTRL7`) и на малых пределах отдаёт другой
масштаб:

```c
case MT6370_CHAN_IBUS:
	reg_val = FIELD_GET(MT6370_AICR_ICHG_MASK, CTRL3);
	case MT6370_AICR_100_mA ... MT6370_AICR_350_mA:
		*val1 = mt6370_adc_get_ibus_scale(priv);  /* MT6370: 3350/100 */
	default: *val1 = 5000;                            /* 50 мА/ед */
...
case MT6370_CHAN_IBAT:
	case MT6370_ICHG_100_mA ... MT6370_ICHG_400_mA: *val1 = 2375;
	case MT6370_ICHG_500_mA ... MT6370_ICHG_800_mA: *val1 = 2680;
	default: *val1 = 5000;
```

Поэтому масштаб надо читать **вместе** с raw и каждый раз, а не помнить
«×50»: при `IAICR` ≤ 350 мА тот же `raw` даёт в 1.49 раза больший ток.
Разрешение `ibat` при 2 А — 50 мА, то есть 400 мА в логе — это «≈400 мА».

`vbat` — 5 мВ/ед, точность достаточная, чтобы увидеть рост на 10 мВ за
минуту.

## 8. Быстрый заряд (PD): чего не хватает

### 8.1 Состояние в наших деревьях

В **обоих** деревьях (`t1100-merge2-src`, `t1100-merge3-src`) и в локальном
`../linux-t1100` узел `tcpc` в `mt6771-fplus-t1100.dts`:

```dts
tcpc { compatible = "mediatek,mt6370-tcpc";
       interrupts-extended = <&pio 41 IRQ_TYPE_LEVEL_LOW>;
       status = "disabled";            /* <<< */
       connector { ... power-role = "sink"; data-role = "device";
                        pd-disable;    /* <<< */
                        op-sink-microwatt = <15000000>;
                        sink-pdos = <PDO_FIXED(5000, 3000, PDO_FIXED_USB_COMM)>; }; };
```

`typec-power-opmode` (фикс `c1c0a897d`, описанный в STATUS `13.11 (18)`)
в этих деревьях **отсутствует** — значит прошитый DTB собран из дерева, где
этот фикс был применён, но в текущие исходники он не попал, а узел там, судя
по STATUS, был `status = "okay"`. Расхождение зафиксировано здесь; патч 0066
закрывает его целиком (узел включён, `pd-disable` снят,
`typec-power-opmode` оставлен как страховка для non-PD-ветки).

### 8.2 Что требует tcpm

`drivers/usb/typec/tcpm/tcpm.c:7219`:

```c
port->pd_supported = !fwnode_property_read_bool(fwnode, "pd-disable");
...
if (!port->pd_supported) {
	ret = fwnode_property_read_string(fwnode, "typec-power-opmode", &opmode_str);
	if (ret)
		return ret;      /* -EINVAL -> probe -22, это и был баг 13.11 (18) */
```

`pd-disable` снят → `pd_supported = 1` → `typec-power-opmode` больше **не**
читается (и не обязателен), а вместо этого для sink-порта обязательны
`capabilities`-ветка с `sink-pdos` и `op-sink-microwatt` (`:7322-7350`):
`sink-pdos` уже есть, `op-sink-microwatt` есть (15 Вт), т.е. **для того,
чтобы PD просто заработал, достаточно снять `pd-disable` и включить узел**.

Выбор контракта (`tcpm_pd_select_pdo`, `:3938`): среди PDO источника
выбирается **максимальная мощность**, для которой есть подходящий sink-PDO
(`min_src_mv >= min_snk_mv && max_src_mv <= max_snk_mv`). С одним PDO 5 В в
`sink-pdos` мы навсегда останемся на 5 В — **9 В не появятся, пока 9-вольтовый
PDO не будет объявлен в sink-pdos** и `op-sink-microwatt` не станет ≥ 18 Вт.
Отсюда патч 0066: `PDO_FIXED(5000,3000)` + `PDO_FIXED(9000,2000)` и
`op-sink-microwatt = <18000000>`.

### 8.3 PD **не** поднимает IAICR сам

`tcpm` применяет лимит тока контракта только если TCPC умеет это:

```c
static int tcpm_set_current_limit(struct tcpm_port *port, u32 max_ma, u32 mv)
{
	...
	if (port->tcpc->set_current_limit)
		ret = port->tcpc->set_current_limit(port->tcpc, max_ma, mv);
```

`tcpci_mt6370.c` заполняет только `init`, `set_vconn`, `set_vbus`
(`:153-157`), `set_current_limit` — **NULL**. Значит после контракта 9 В
`mt6370-charger` останется с прежним `IAICR` (500/900 мА), и 18 Вт не будет:
нужно отдельно поднять `input_current_limit`. Ток контракта доступен
userspace через `tcpm-source-psy-mt6370-tcpc.N` (`current_max`,
`voltage_now`) — на этом построена подкоманда `pd` в `t1100-charge.sh`.

### 8.4 Data role и RNDIS/SSH

`tcpm` ищет role switch двумя способами (`:7752`):
`fwnode_usb_role_switch_get(tcpc->fwnode)` (graph-линк от `connector` к
`&ssusb`) и затем `usb_role_switch_get(port->dev)` (device links). В нашем
DTS **graph-линка нет** — поэтому `role_sw = NULL`, tcpm никого не
переключает, `mtu3` остаётся в своей роли. `data_role = "device"` из
`connector` — это заявленная возможность порта (sink/device), а не команда
переключения: без `role_sw` и без DR_Swap от партнёра роль данных не меняется.
RNDIS-гаджет и SSH от включения PD не страдают.

Важно не добавлять в `connector` `port`/`endpoint` на `&ssusb`: тогда
появится `role_sw` и tcpm начнёт дёргать роль `mtu3` (см. STATUS `13.11 (18)`),
а `role-switch-default-mode` в merge3 — `"peripheral"`, но host-переключение
при power role source всё равно ломает xHCI (проверено 13.11 (5)).

### 8.5 Конфиг

В `t1100-merge2-out/.config` (то, что прошито) есть всё нужное, менять нечего:

```
CONFIG_POWER_SUPPLY=y  CONFIG_CHARGER_MT6370=y  CONFIG_MEDIATEK_MT6370_ADC=y
CONFIG_TYPEC=y  CONFIG_TYPEC_TCPM=y  CONFIG_TYPEC_TCPCI=y
CONFIG_TYPEC_TCPCI_MT6370=y  CONFIG_USB_ROLE_SWITCH=y
```

`CONFIG_TYPEC_MUX_*`/`CONFIG_TYPEC_DP_ALTMODE` **не нужны**: на плате только
USB2-пары (SuperSpeed нет), mux'а нет, DP-altmode нет.

### 8.6 Риски PD (что писать в отчёт, если включим)

1. **Потеря USB-сети при смене data role** — исключена, пока нет
   graph-линка и мы не добавим `usb-role-switch` к `connector`; но если
   кто-то добавит endpoint, роль уедет и SSH пропадёт (проверено 13.11 (5):
   host→device ломает xHCI).
2. **Нагрев.** 18 Вт на 8 А·ч 1S = ≈2.2 А в батарею (≈0.28C). При 5 В кпд
   buck'а ~85–90 %, потери ~2 Вт в MT6370 — приемлемо, но при `IAICR=2000`
   на 5 В (10 Вт) ток батареи будет ~1.9 А; без PD (5 В, порт ноутбука)
   ставить 2000 мА бессмысленно и опасно для слабого источника — MIVR
   (4.4 В) начнёт «складывать» вход, и заряд просто встанет.
3. **PD-зарядник, который не любит sink без battery-handshake** — на MT6370
   роль батареи играет сам чип, для tcpm это прозрачно; риск только в
   источнике (некоторые PD-хабы отдают 5 В 0.5 А без SOP'а — тогда просто
   останется 5 В, ничего не сломается).
4. **MIVR 4.4 В**: при просадке VBUS ниже него чип уходит в MIVR-loop
   (`F_CHG_MIVR_STAT` → toggle CFO, `:384`). Для 9 В это не проблема; для
   5 В и 2 А — реально, поэтому `set` проверяет `vbus` после записи.

Всё перечисленное реализовано патчем `patches/0066-arm64-dts-t1100-enable-typec-pd.patch`
(узел `tcpc` → `status = "okay"`, без `pd-disable`, `typec-power-opmode`
оставлен, `sink-pdos` 5 В/3 А + 9 В/2 А, `op-sink-microwatt = 18 Вт`).
Патч собран и проверен `cpp`+`dtc` офлайн: результирующий DTB содержит
`status = "okay"`, `op-sink-microwatt = 0x112a880`, `sink-pdos = <0x401912c 0x402d0c8>`
(расшифровка: 5000 мВ/3000 мА и 9000 мВ/2000 мА), `pd-disable` отсутствует.
Плата на момент написания недоступна, на железе PD ещё не проверялся.
**Текущая цель — заряд через powered hub на 5 В, PD для неё не нужен.**

## 9. Заряд через powered hub (5 В) — что делает драйвер, а что нет

Сценарий владельца: планшет подключён к **даунстрим-порту self-powered хаба**,
хост (ПК) — к тому же хабу; RNDIS/SSH идёт через этот же порт, т.е. заряд и
данные одновременно. PD при этом не нужен.

### 9.1 `usb_type` и `charge_type` при подключении к хабу

Ничего особенного: порт хаба ведёт себя как обычный SDP (или отдаёт
`Unknown`, если D+/D- не распознаны). BC1.2-результат только публикуется:

```c
switch (usb_stat) {                      /* mt6370-charger.c:289 */
case MT6370_USB_STAT_SDP:
case MT6370_USB_STAT_SDP_NSTD: priv->psy_usb_type = POWER_SUPPLY_USB_TYPE_SDP; break;
case MT6370_USB_STAT_DCP:      priv->psy_usb_type = POWER_SUPPLY_USB_TYPE_DCP; break;
case MT6370_USB_STAT_CDP:      priv->psy_usb_type = POWER_SUPPLY_USB_TYPE_CDP; break;
default:                       priv->psy_usb_type = POWER_SUPPLY_USB_TYPE_UNKNOWN; break;
}
```

и всё — **ни одна ветка не трогает IAICR**. `charge_type` (`:477`) вообще не
зависит от порта: `CHG_STAT` = «идёт заряд» + `VBAT_LVL` = «выше порога
precharge». Поэтому «хаб дал SDP» не занижает лимит: лимит остаётся ровно тем,
что лежит в регистре `CHG_CTRL3` (после сброса 500 мА — вендорский `aicr`,
после probe никто не перезаписывает; наш юнит ставит 900 мА).

### 9.2 Переопределение из userspace

- `input_current_limit` — **можно**, без всякой привязки к детекту:
  `set_property(INPUT_CURRENT_LIMIT)` → `mt6370_chg_field_set(F_IAICR, ...)`
  (`:669`), диапазон 100..3250 мА шагом 50, вне диапазона — clamp без ошибки
  (§2). Никакой проверки «не больше, чем выдал BC1.2» в драйвере нет.
- `constant_charge_current` — можно, 900..5000 мА шагом 100.
- `usb_type` и `charge_type` — **нельзя**: их нет в `set_property()`, а
  `mt6370_chg_property_is_writeable()` (`:682`) перечисляет только
  `ONLINE`, `CONSTANT_CHARGE_*`, `INPUT_*_LIMIT`, `PRECHARGE_CURRENT`,
  `CHARGE_TERM_CURRENT`; для остальных `return 0` → атрибут в sysfs
  read-only. «Притвориться DCP», чтобы драйвер сам поднял ток, невозможно —
  и не нужно: ток задаём напрямую.
- `online` — можно, но это лишь перезапуск детекта (`mt6370_chg_set_online`,
  `:511` → `bc12_work`), заряд от него не включается/выключается.

Вывод: **через хаб заряд ограничивает только наш IAICR и то, что реально
отдаёт порт хаба**. Всё управление — снаружи, из `t1100-charge.sh`.

### 9.3 Профили (`rootfs-overlay/usr/local/bin/t1100-charge.sh`)

| профиль | IAICR | ICHG | когда |
|---|---|---|---|
| `auto` (== безопасный дефолт для хаба) | 900 мА | 2000 мА | юнит на загрузке и udev-replug; проверено на железе: вход ≈750 мА / 3.5 Вт, в батарею ≈400 мА |
| `hub` | 900 мА (`HUB_IAICR_UA`) | 2000 мА | явный профиль для порта powered hub; найденный замерами максимум вписывается в `HUB_IAICR_UA` |
| `wall` | 2000 мА | 2000 мА | обычный зарядный адаптер (DCP); вендорские 2 А |
| `off` | 500 мА | 900 мА | значения после probe (диагностика) |
| `pd` | из контракта, ≤2000 мА | 2000 мА | только при PD-контракте (патч 0066), сейчас не цель |

Обоснование `auto = hub = 900 мА`: это единственный режим, проверенный на
железе с положительным балансом (3.5 Вт вход, 400 мА в батарею при работающей
Ubuntu). Порт self-powered хаба по спецификации USB2 отдаёт 500 мА, дешёвые
хабы — «500 мА на порт» с просадкой VBUS под нагрузкой; 900 мА уже
превышение SDP, поэтому:
- ступени выше 900 мА проверяются **только** `charge-sweep.sh` с контролем
  VBUS (>4.6 В) и живости SSH;
- `set` сам откатывает IAICR, если после записи VBUS < 4.6 В (MIVR), и
  предупреждает, если `ibus` не вырос;
- 2 А на 5 В (10 Вт) от хаба — не гарантия: многие хабы столько не отдают на
  порт, тогда получим просадку и откат.

### 9.4 Что ещё нужно, чтобы «не пропадал заряд»

- **USB autosuspend.** Если хост/ядро усыпят USB-устройство, RNDIS может
  отвалиться (SSH умрёт), а VBUS на порту хаба — остаться. Юнит
  `t1100-usb-keepalive.service` (`t1100-charge.sh keepalive`) ставит
  `power/control=on` всем USB-устройствам и `usbcore.autosuspend=-1`.
- **Переподключение хаба.** Регистры IAICR/ICHG переживают detach, но после
  повторного attach драйвер ничего не восстанавливает. Правило
  `90-t1100-charge.rules` на `power_supply`/`ATTR{online}=="1"` стартует
  `t1100-charge-replug.service` → снова применяется политика `auto`.
- **Перезагрузка планшета.** `t1100-charge.service` (oneshot,
  `RemainAfterExit=yes`) выполняет `auto` после udev-settle, до
  `t1100-power-guard`.
- **Хост уснул (S3).** Отдельный случай: часть хабов снимает VBUS с
  даунстрим-портов при уходе в suspend — software-обхода нет, проверяется
  замером (п. 3 методики). Если VBUS остаётся, заряд продолжается: MT6370
  следит только за VBUS.

### 9.5 Методика замера (когда плата оживёт) и таблица

`tools/host/charge-sweep.sh [host] --steps "100 250 500 750 900 1200 1500"
--hold 60` — на каждой ступени пишет IAICR, ждёт 60 с, снимает
`t1100-charge.sh sample` и проверяет ping+ssh; при потере RNDIS ступень
помечается LOST и замер останавливается, в конце возвращается профиль.

Перед прогоном: RNDIS/SSH идут через хаб, `t1100-charge.sh status` снят,
по возможности закрыты тяжёлые процессы (баланс считается при работающей
Ubuntu — это и есть целевой сценарий).

Таблица (заполняется на железе, сейчас пусто — плата недоступна):

| IAICR, мА | ibus, мА | vbus, мВ | vbat, мВ | ibat, мА | Tmax, °C | RNDIS/SSH | примечание |
|---|---|---|---|---|---|---|---|
| 100 | | | | | | | |
| 250 | | | | | | | |
| 500 | | | | | | | |
| 750 | | | | | | | |
| 900 | | | | | | | (проверено ранее: 750/4940/3645/400 — вне таблицы) |
| 1200 | | | | | | | |
| 1500 | | | | | | | |

Критерий максимума: VBUS ≥ 4.6 В, `ibus` растёт вместе с IAICR, SSH жив,
`vbat` не падает. Найденное значение → `HUB_IAICR_UA`, затем 10-минутный
прогон на нагрев.

## 10. Готовые команды (для железа)


```sh
PS=/sys/class/power_supply/mt6370-charger
echo 2000000 > $PS/constant_charge_current     # 2 А в батарею (вендор)
echo 1500000 > $PS/input_current_limit         # 1.5 А вход (шаг 50 мА)
cat $PS/input_current_limit $PS/constant_charge_current
iio=/sys/bus/iio/devices/iio:device0
cat $iio/in_current5_raw $iio/in_current5_scale   # ibus
cat $iio/in_voltage3_raw $iio/in_voltage3_scale   # vbat
cat /sys/class/power_supply/tcpm-source-psy-*/current_max  # ток контракта PD
```

Всё это инкапсулировано в `rootfs-overlay/usr/local/bin/t1100-charge.sh`
(см. `docs/handover.md`, раздел про зарядку).

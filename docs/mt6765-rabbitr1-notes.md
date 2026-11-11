# MT6765 / Rabbit R1: разбор дерева `haretic/android-kernel-mt6765-rabbitr1`

Клон: `/tmp/opencode/rabbitr1`. Задача — оценить, что отсюда переносимо в наш
mainline-порт MT6771/MT8788 (Fplus T1100, `docs/STATUS.md`, `patches/`).
Ничего не коммитилось.

## 0. Главное: это НЕ downstream 4.19

| Ожидалось | Фактически |
|---|---|
| `drivers/misc/mediatek/video/mt6771/dispsys/`, `mtkfb`, `lcm/` | `drivers/misc/mediatek/` содержит **только `include/`**; нет ни `video/`, ни `lcm/`, ни `mtkfb` |
| `drivers/gpu/drm/mediatek` = старый `mtk_drm` 4.19 | **mainline-драйверы** (`mtk_drm_drv.c`, `mtk_dsi.c`, `mtk_disp_ovl.c`, DDP_COMPONENT, `mmsys` как `drivers/soc/mediatek/mtk-mmsys.c`) |
| версия 4.19 | `Makefile:2-4` — `VERSION=7 PATCHLEVEL=3 SUBLEVEL=3` (mainline-ветка, форк с mainline-стилем) |

Практический вывод: дерево — «mainline + поддержка MT6765/MT6762G + staging
вендорщина». Оно ценно не как источник регистров «из downstreама», а как
**готовый mainline-прецедент для 12-нм famiglia MTK (MT6765/MT6771)**: видно,
какие квирки нужны для этого класса IP и чем он отличается от MT8183, на
котором стоит наш порт (`patches/0008`).

## 1. Дисплей: карта адресов MT6765 ≠ MT6771

Из `arch/arm64/boot/dts/mediatek/mt6765.dtsi` (все номера строк — в этом файле):

| узел | MT6765 (это дерево) | MT6771 (наш сток, `refs/stock-mt6771.dts`) | MT8183 (наш шаблон) |
|---|---|---|---|
| mmsys | `1271: clock-controller@14000000`, `compatible="mediatek,mt6765-mmsys","syscon"` | `2388: mmsys_config@14000000`, `"mediatek,mmsys_config"` | `mmsys@14000000` |
| mutex | `1282: mutex@14001000`, IRQ 210 | `2629: disp_mutex@14016000` | `mutex@14016000` |
| smi_common | `1294: 0x14002000` | — | `smi_common@14002000` (совпадает) |
| larb0 | `1305: 0x14003000` | `2636: smi_larb0@14017000` | `smi_larb0@14017000` |
| OVL0 | `1316: ovl@1400b000`, IRQ 217 | нет узла (downstream `mtkfb`) | `ovl@14008000` |
| OVL0_2L | `1327: ovl@1400c000`, IRQ 229 | — | `ovl@14009000` |
| RDMA0 | `1338: rdma@1400d000`, IRQ 218 | — | `rdma@1400b000` |
| WDMA0/COLOR/CCORR/AAL/GAMMA/DITHER | `1349/1360/1371/1382/1393/1404` = `0x1400e000…0x14013000` | `mdp_aal@1401b000`, `mdp_ccorr@1401c000` | `0x1400f000…0x14013000` |
| DSI0 | `1415: dsi@14014000`, IRQ 225 | `0x14014000` | `dsi0@14014000` (совпадает) |
| DPI | **отсутствует** (grep `dpi` пусто) | `0x14015000` есть | `dpi@14015000` |
| DSI PHY | `1219: dsi-phy@11c80000`, `"mediatek,mt6765-mipi-tx"` | `1697: mipi_tx0@11e50000` | `mipi_tx0@11e50000` |
| M4U | `779: m4u@10205000`, IRQ 158, larbs 0..3 | `0x10205000` (SPI 166) | 0x10205000 |
| GCE | `789: mailbox@10238000`, IRQ 154/155 | `0x10238000` | `gce@10300000` |

**Вердикт: не копировать.** У MT6765 другой bio dispsys: mutex в начале блока
(`0x14001000` против `0x14016000`), OVL/RDMA на «старых» адресах
(`0x1400b000/0x1400d000`), свой D-PHY по `0x11c80000` вместо `0x11e50000`, нет
DPI. Наш MT6771 по факту совпадает с MT8183-раскладкой — дисплей уже работает
(`kmscube` 56.4 fps), подтверждение не требуется. Список **полезен как
чек-лист** «что должно быть в DT для полного пути» (gce-client-reg, iommus,
resets, power-domains на каждом компоненте).

### 1.1 mmsys-маршруты

- `drivers/gpu/drm/mediatek/mtk_drm_drv.c:262-266` — `mt6765_mmsys_driver_data`:
  `main_path = mt8183_mtk_ddp_main`, `mmsys_dev_num = 1`, **ext-пути нет**.
  Это прямое подтверждение нашей архитектуры: у 6765/6771 один главный путь
  OVL0 → OVL_2L0 → RDMA0 → COLOR0 → CCORR → AAL0 → GAMMA → DITHER0 → DSI0.
- `drivers/soc/mediatek/mt6765-mmsys.h:8-14,16-60` — таблица маршрутов
  `mmsys_mt6765_routing_table`, регистры `0xf30..0xf68` (`DISP_OVL0_MOUT_EN`
  `0xf3c`, `DISP_OVL0_2L_MOUT_EN` `0xf40`, `DISP_DITHER0_MOUT_EN` `0xf50`,
  `DISP_DSI0_SEL_IN` `0xf68`), с обходом RSZ0 (`RDMA0_RSZ0_IN_SOUT_SEL`);
  в таблице есть и `MDP_COLOR0_OUT_SEL_IN`, и `DISP_COLOR0_OUT_SEL_IN`.
  **Не наше**: у MT8183 эти регистры `0xf00..0xf54`
  (`mt8183-mmsys.h:6-14`), и у нас они работают. Полезно только как образец,
  если придётся добавлять RSZ/DPI-ветку.
- `drivers/soc/mediatek/mtk-mmsys.c:41-45` — `clk_driver = "clk-mt6765-mm"`,
  т.е. mmsys-узел сам регистрирует clk-драйвер. У нас его нет вообще
  (нет `clk-mt6771`), поэтому MM-гейты в нашем порте обслуживает
  `clk-mt8183-mm` через mt8183.dtsi — эта схема отсюда не переносится.

### 1.2 mutex

- `drivers/soc/mediatek/mtk-mutex.c:403-415` — `mt6765_mutex_mod`:
  OVL0=7, OVL_2L0=8, RDMA0=9, WDMA0=10, COLOR0=11, CCORR=12, AAL0=13,
  GAMMA=14, DITHER0=15, DSI0=16, PWM0=19 (сырые биты, не именованные
  константы как у MT8183).
- `mtk-mutex.c:766-772` — `mt6765_mutex_driver_data`: `no_clk = true`,
  `has_dsi0_mod = true`, SOF/MOD-регистры от MT8183
  (`MT8183_MUTEX0_MOD0/SOF0`).
- `mt6765.dtsi:1282-1292` — клиент GCE: `gce-events = <CMDQ_EVENT_MUTEX0_STREAM_EOF>,
  <CMDQ_EVENT_MUTEX1_STREAM_EOF>`; в `include/dt-bindings/gce/mediatek,mt6765-gce.h:92`
  это **130/131** (у mt8183 — свои номера).
  **Вердикт:** таблицу модулей не переносить (наш порт работает на mt8183-битах),
  но `has_dsi0_mod` и имена GCE-событий — полезная сверка, если CMDQ/mutex
  начнёт ругаться на DSI-модуль.

### 1.3 Клоки: MT6765 ≠ MT8183 по битам

- `drivers/clk/mediatek/clk-mt6765-mm.c:14-19` — **один** CG-регистр:
  `sta 0x100, set 0x104, clr 0x108`, ops `mtk_clk_gate_ops_setclr`.
- `clk-mt6765-mm.c:24-55` — биты: OVL0 **7**, OVL0_2L **8**, RDMA0 **10**,
  WDMA0 11, COLOR0 12, CCORR0 13, AAL0 14, GAMMA0 15, DITHER0 16, DSI0 **17**,
  SMI_COMMON 19, SMI_LARB0 20, SMI_COMM0/1 21/22, DIG_DSI **28**, F26M_HRTWT 29.
- `drivers/clk/mediatek/clk-mt8183-mm.c:36-78` — два банка MM0/MM1 и совсем
  другие смещения: OVL0 **20**, RDMA0 **23**, DSI0 → `MM1 bit0/1`
  (`mm_dsi0_mm`, `mm_dsi0_if`), SMI_COMMON 0, LARB0 1.
- `clk-mt6765.c:177-186` — `mm_parents[]` (8 родителей), `clk-mt6765.c:376-378`
  — `CLK_TOP_MM_SEL` по `CLK_CFG_0[18:16]`; у нас `mm_sel` из mt8183-таблиц.

**Вердикт:** переносить нельзя (наши MM-гейты уже проверены железом), но это
важный факт для `docs/`: **у 12-нм MTK (6765) и у MT8183 раскладка MM-гейтов
принципиально разная**, т.е. «взяли mt8183 и всё совпало» — совпадение именно с
MT6771, а не свойство семейства. Если однажды DSI/OVL-гейт не включится —
второй кандидат лежит здесь, в `clk-mt6765-mm.c`.

### 1.4 DSI host: единственный публичный источник D-PHY-таймингов

`drivers/gpu/drm/mediatek/mtk_dsi.c`:

- `1857-1864` — `mt6765_dsi_driver_data`: те же смещения, что у MT8183
  (`reg_cmdq_off 0x200`, `reg_vm_cmd_off 0x130`, `reg_shadow_dbg_off 0x190`),
  но флаг `mt6765_regs = true`, гейтящий ~20 правок.
- `296-320` — `mt6765_dsi_phy_timing()`: **формулы** D-PHY (lpx, da_hs_prepare,
  da_hs_zero/trail, ta_go/sure/get, clk_hs_*) из вендорского драйвера MT6765,
  с сохранением точности на дробных МГц. У MT8183 — статическая таблица
  `mtk_dsi_phy_timing()`. Для наших 1534.8 Мбит/с/лейн это готовый
  альтернативный расчёт, если появятся проблемы HS/LP.
- `646-664` — `mt6765_dsi_config_vdo_timing()`: blanking в байтах считается с
  вычитанием overhead пакета (`*bpp - 10` для HSA/HBP в pulse-режиме, `-4`/`-10`
  в burst, `-12` для HFP, `BLLP_WC = 0`) — у MT8183 путь другой
  (`*_per_line_lp`).
- `354-366` — «CON_CTRL bit 1 (`DSI_EN`) reserved on MT6765»: enable/disable
  не пишутся вообще. `484-500` — `DSI_PS_SEL`: у 6765 **другие** кодировки для
  RGB666 (`MT6765_LOOSELY_PS_RGB666`, `MT6765_PACKED_PS_RGB666`);
  `HSTX_CKL_WC` не программируется (`507`).
- `809-830` — `mt6765_dsi_enter_cmd_mode()` / `mt6765_dsi_ulps()`; `1166-1185` —
  `mt6765_dsi_mode_valid()` (свой расчёт per-lane rate).

**Вердикт: условно полезно.** Наш DSI0 уже выводит картинку через mt8183-путь
(`patches/0022`), поэтому квирки 6765 включать не нужно. Ценность: (а) это
единственное публичное место с формульными D-PHY-таймингами для MTK 6765/6771;
(б) если на 1.5348 Гбит/с появятся артефакты HS/LP — сравнить
`mt6765_dsi_phy_timing()` с нашим `mtk_dsi_phy_timing()`.

### 1.5 MIPI TX PHY: другой инстанс — не переносить

`drivers/phy/mediatek/phy-mtk-mipi-dsi-mt6765.c`:

- `35` — `mt6765_lane_order[] = { 1, 3, 0, 4, 2 }` («физический порядок банков:
  D2, D0, CK, D1, D3»), база лейна `0x100 * (n+1)` (`28`).
  У MT8183 (`phy-mtk-mipi-dsi-mt8183.c:37-45`) лейны разнесены на `0x144`
  (`MIPITX_D2P_RTCODE 0x0100`, `D0 0x0244`, `CK 0x0328`, …).
- `37-75` — последовательность PLL (SDM_PWR_ON → ISO_EN off → PCW по posdiv
  2.5G/1G/500M/250M → PLL_EN → SW_ANA_CK_EN), `88-100` — `determine_rate`.
- `113-131` — `mt6765_mipi_tx_lanes_off()` (LP00 до перевода падов в SW-режим,
  `LANE_CON 0x3fff0180/0x3fff0100`).
- `134-189` — `mt6765_mipi_tx_prepare_signal()`: **снимает и сохраняет
  rt_code-калибровку, запрограммированную LK** (`rt_code_saved`,
  `preserve_fw_calibration = true`), гасит унаследованный от прошивки линк,
  затем восстанавливает калибровку по битам.

**Вердикт:** сам драйвер не наш (адрес/раскладка лейнов MT6765 другой, у нас
`0x11e50000` и работает mt8183-драйвер). **Но идея `preserve_fw_calibration` /
`rt_code` из LK напрямую релевантна**: у нас LK тоже инициализирует DSI
(`patches/0022`, `docs/it6112-vendor-init.md`), и это готовый рецепт, как не
сломать его калибровку при переинициализации PHY ядром.

### 1.6 OVL: набор квирков для нашего класса IP

`drivers/gpu/drm/mediatek/mtk_disp_ovl.c`:

- `1060-1072` — `mt6765_ovl_driver_data`: 4 слоя, `gmc_bits = 10`,
  `fmt_rgb565_is_0`, `smi_id_en`, `addr = DISP_REG_OVL_ADDR_MT8173`, форматы
  mt8173, `mt6765 = true`. `1074-1092` — то же для OVL_2L.
- Квирки: `213-243` (`mt6765_ovl_error_mask`/`ovl_irq` — своя маска ошибок,
  иначе IRQ считается spurious), `275-300` (vblank INTSTA пишется `~OVL_FME_CPL_INT`),
  `331-360` (`mt6765_ovl_reset` — reset-while-busy с повтором, `399`),
  `484-530` (`mt6765_ovl_config`, `greq = 0x7777`, ограничение 4095×4095,
  `ROI_BGCLR = OVL_COLOR_ALPHA`), `565-630` (`mt6765_ovl_plane_check`),
  `789` (alpha `>> 8`), `823-835` (flip и clip для YUYV).

**Вердикт: «пока не нужно, но записать».** Наш OVL работает на mt8183-данных,
значит MT6771 ближе к 8183. Список квирков — готовая шпаргалка, если появятся
spurious OVL IRQ / reset-timeout / неверный цвет при alpha или RGB565.

## 2. IOMMU / SMI / CMDQ

- `drivers/iommu/mtk_iommu.c:1702-1712` — `mt6765_data`:
  `flags = MTK_IOMMU_TYPE_MM | RESET_AXI | WR_THROT_EN`, `banks_num = 1`,
  `larbid_remap = {{0},{1},{2},{3}}` (**identity**), GEN1 inv_sel.
  У нас в порте — `mt8183_data` (`:1800-1809`) с remap
  `{{0},{4},{5},{6},{7},{2},{3},{1}}`. Разница существенна: если на MT6771
  larb'ы нумеруются как у 6765, наш remap «сдвигает» порты. Пока дисплей
  работает (только larb0/OVL-RDMA), это не проявляется — **проверить при
  подключении камеры/видео**.
- `:484-500` (`mt6765_iommu_isr`) и `:1190` (`mt6765_iommu_config`) — отдельный
  ISR и настройка «tlb/…» для 6765; `1259`, `1685` — вызовы.
- `drivers/memory/mtk-smi.c:494-496` — `mtk_smi_larb_mt6765` (gen2 general),
  `:771-775` — `mtk_smi_common_mt6765` (`has_gals`, `bus_sel = LARB(1)|LARB(3)`);
  у mt8183 `bus_sel` включает LARB 1,2,5,7 (`:mtk_smi_common_mt8183`).
  **Полезно:** `bus_sel` — частая причина «SMI hang» на дисплее; если у нас
  повиснет SMI при обращении к 4-му ларбу — сверить с этой строкой.
- `drivers/mailbox/mtk-cmdq-mailbox.c:896-905` — `gce_plat_mt6765`
  (`thread_nr`, `ctrl_num` и т.п.), `:964` — `"mediatek,mt6765-gce"`.
  Плюс `include/dt-bindings/gce/mediatek,mt6765-gce.h` — номера событий:
  `DISP_OVL0_SOF 7`, `DISP_RDMA0_EOF 30`, `MUTEX0_STREAM_EOF 130`,
  `DSI0_TE 141`, `DSI0_IRQ_EVENT 142`, `DSI0_DONE_EVENT 143`.
  **Вердикт:** у нас CMDQ уже включён через mt8183.dtsi (mmsys `mboxes`);
  числа 6765 — только сверка, если GCE-события не сойдутся.

## 3. Панель: `panel-himax-hx83102.c` — самый ценный файл для нас

`drivers/gpu/drm/panel/panel-himax-hx83102.c` (1382 строки) — mainline-драйвер
BOE-панелей на **Himax TDDI** (DDIC+тач в одном чипе), с командами
`0xb1 SETPOWER … 0xe9 SETSPCCMD` (`:26-57`), включая
`HX83102_SETEXTC 0xb9` = `0x83 0x10 0x21 0x55 0x00` (`:31`, `:95-101`) —
это тот самый «вход в расширенные команды», без которого панель не примет
`0xb1..`.

Ключевое: `:200-303` — `boe_nv110wum_init()` (**BOE NV110WUM / TV110WUM**),
`:900-916` — `boe_tv110wum_default_mode` (1200×1920, `clock = 167700`),
`:913-916` — `boe_nv110wum_desc`. В дереве ещё 7 других панелей
(`starry_himax83102_j02_init:103`, `csot_pna957qt1_1:305`, `ivo_t109nw41:402`,
`kingdisplay_kd110n11_51ie:507`, `starry_2082109qfh040022_50e:597`,
`holitech_htf065h045:712`, `waveshare_12_3_a:774`).

**Почему это важно для нас.** Наш дигитайзер — **HX83102E** (ICID
`0x900000d0 = 0x2e108300`, `docs/STATUS.md` 10.11 (9)), т.е. **TDDI**: тот же
чип управляет и матрицей BOE TV110XUM-LB0. Публичного init-тейбла BOE
TV110XUM нет (`docs/STATUS.md:733`), а здесь лежит полная DCS-последовательность
**BOE-панели на Himax 83102** — тот же командный словарь (`0xb1`,`0xb2`,`0xb9`,
`0xbd` банки, `0xd3`/`0xd5`/`0xd8` GIP, `0xe0` GMA, `0xe7` TP1).

**Вердикт: полезно (шаблон, не готовая последовательность).** GIP/GMA/PWM/
CLOCK значения — под 1200×1920 и другую матрицу, их надо пересчитать/сверить с
тем, что LK делает на нашем стекле. Но структура, порядок банков, набор
команд и `SETEXTC` — прямое попадание; это первое, что стоит сравнить с
вендорской инициализацией панели.

Остальное по панелям — мимо:
- `drivers/gpu/drm/panel/panel-rabbit-r1.c` (`rabbit,r1-panel`, 480×640) —
  ST7701-подобные банки (`:42-45`), это панель Rabbit R1, к нам не относится.
- `panel-boe-tv101wum-nl6.c:68` (`boe_tv110c9m_init`) — BOE TV110C9M
  (Chromebook), другой контроллер, максимум как второй образец.

## 4. Тач: `himax_hx83112b.c` — отстаёт от нашего патча

`drivers/input/touchscreen/himax_hx83112b.c` (437 строк) — это **стоковый
mainline** (Job Noorman, 2022 + hx83100a, 2024). Слово `83102` в файле
**не встречается**.

Что подтверждает нашему RE (`docs/touch-hx83102e.md`):
- `:33` `HIMAX_AHB_ADDR_EVENT_STACK 0x30`, `:37` `HIMAX_AHB_CMD_CONTI 0x31`,
  `:35-36` `INCR4 0x0d/0x10`, `:34` `CONTI 0x13` — тот же протокол burst.
- `:84-118` `himax_bus_enable_burst()`/`himax_bus_read()`: перед чтением >4
  байт пишутся `0x13 = 0x31`, `0x0d = 0x10`, затем `noinc_read` с `0x08`;
  адрес пишется **одним байтом** в `0x00` (`:101`) — это ровно то, чего не
  хватало нашему первому подходу (`regmap_raw_read(0x30, 56)` слал 4-байтный
  адрес).
- `:260-277` `himax_verify_checksum()` — сумма всех 56 байт, `& 0xff == 0`.
  Вендор для HX83102E считает 16-битную сумму до первого `0x00` — **здесь
  этого нет**, т.е. починка checksum остаётся нашей.
- `:279+` `himax_read_events()` — фиксированный `struct himax_event` 56 байт;
  никакого handshake `sense_off → flash check → reload_disable → sense_on`
  перед sensing нет; `:380-395` suspend/resume = только `disable_irq`.

**Вердикт: не полезно (мы уже впереди, `patches/0040`).** Ценность
отрицательная только в одном смысле — это независимое подтверждение, что
mainline-драйвер без вендорского handshake кадров не даст, и что наши выводы
про 0x30/0x31/0x0d/0x13 верны.

## 5. pinctrl / clk: что брать нельзя

- `drivers/pinctrl/mediatek/pinctrl-mt6765.c` (1106 строк) +
  `pinctrl-mtk-mt6765.h` (1820 строк, `MTK_PIN` GPIO0…**GPIO190**, EINT-маппинг
  вида `GPIO190 → EINT 147`).
- **Не переносить**: у нас pinctrl-mt6771 нет, и порт живёт на
  `pinctrl-mt8183` (patch 0008); нумерация EINT у 6765 своя (наш тач — GPIO163/
  GPIO158/EINT 1, `docs/touch-hx83102e.md`). Файл полезен только если решим
  завести отдельный pinctrl-mt6771.
- `drivers/clk/mediatek/clk-mt6765*.c` (7 файлов: top, mm, img, cam, vcodec,
  audio, mipi0a) — полный набор тактов 6765. Для нас это **образец объёма
  работы** «если делать clk-mt6771 честно», плюс `clk-mt6765.c:117-118`
  (`MMPLL/MMPLL_D2`) и `:376` (mux `mm_sel`) — сверка частот MM на 12-нм MTK.

## 6. DTS: чем ещё полезен board-DTS

`arch/arm64/boot/dts/mediatek/mt6765-rabbit-r1.dts` (1572 строки):

| что | строки | нам |
|---|---|---|
| `chosen/bootargs` | `206-216` | набор `earlycon console clk_ignore_unused regulator_ignore_unused mem_sleep_default=deep fbcon=…` — у нас то же самое (`patches/0003`), подтверждение практики |
| `panel@0` на `&dsi` | `721-742` | эталон, как описывать DSI-панель без bridge (`reset-gpios`, `backlight`, `rabbit,max-refresh-hz`) |
| `touchscreen@1a` (hynitron CST340, I2C4, 100 кГц) | `944-962` | **не наше**, но хороший образец DTS тача (reset-gpios, interrupts, `touchscreen-size-*`) |
| `r1_backlight` = `mediatek,mt6370-backlight` | `1124-1126` | у нас тот же MT6370 (`patches/0024/0025`); драйвер в mainline есть (`drivers/video/backlight/mt6370-backlight.c` в этом дереве тоже) — нового нет |
| `reserved-memory`: sspm_share, scp_share, **consys**, **wifi** | `478-517` | **полезно для фазы 5**: точные размеры/выравнивания (`consys 0x400000`, `wifi 0x300000`, `alloc-ranges 0x40000000+`) |
| connectivity-узлы (CONSYS «soc1_0») | `517+` | см. §7 |

`mt6765.dtsi` как образец «правильного» описания: `1219` dsi-phy
(`clock-output-names = "dsi_mppll"`), `1415-1430` dsi (`clocks = <&mmsys CLK_MM_DSI0>,
<&mmsys CLK_MM_DIG_DSI>, <&dsi_phy>`, `clock-names = "engine","digital","hs"`),
`1271-1281` mmsys с `mediatek,gce-client-reg`, `1316-1341` OVL/OVL_2L с
`iommus = <&iommu M4U_PORT_DISP_OVL0>`.

`include/dt-bindings/memory/mt6765-larb-port.h:14-21` — порты M4U larb0:
`DISP_OVL0 0`, `DISP_OVL0_2L 1`, `DISP_RDMA0 2`, `DISP_WDMA0 3`,
`DISP_FAKE0 7`. У нас используется mt8183-larb-port.h — сверить при
подключении WDMA (screenshot/self-refresh).

## 7. Бонус: `drivers/staging/mtk-connectivity` (14 МБ) — фаза 5

`drivers/staging/mtk-connectivity/` — вендорский стек WMT/BTIF/gen4m/gps
(adapter, bt, btif, gen4m, gps, wlan_adaptor, wmt). В
`wmt/common_main/platform/mtk_wcn_consys_hw.c:115-120` объявлены **weak**
`consys_ic_ops_mt6771` и `consys_ic_ops_mt6765` — т.е. MT6771 в этой
инфраструктуре предусмотрен.

**Вердикт: изучить при Wi-Fi/BT (фаза 5), не сейчас.** Оговорка: наш планшет
в стоке на `wlan_drv_gen3`, а здесь упор на gen4m/connac — проверить
совместимость чипа (MT6631? MT7668?) до того, как радоваться. Один файл в
14 МБ стека — не наш сегодняшний скоуп.

## 8. Упоминания MT6771/MT8788 в дереве

`grep -rli "mt6771\|mt8788"` даёт всего 4 файла, и ни одного драйвера
дисплея/клока:
`sound/soc/mediatek/mt6765/mt6765-afe-common.h`,
`drivers/staging/mtk-connectivity/wmt/common_main/platform/mtk_wcn_consys_hw.c`,
`drivers/staging/mtk-connectivity/gps/gps_emi.c`,
`drivers/misc/mediatek/include/mt-plat/mtk_cpufreq_common_api.h`.
**Вердикт:** поддержки MT6771 как SoC в дереве нет; всё, что мы можем взять, —
это mainline-опыт MT6765 (тот же 12-нм класс) и вендорский staging.

## 9. Итог: top-5 по полезности

| # | Находка | Файл:строки | Вердикт |
|---|---|---|---|
| 1 | Полный mainline-описанный MT6765: mmsys/mutex/OVL/RDMA/DSI/PHY/M4U/GCE как **чек-лист** узлов и свойств; отдельно — `mt6765_mmsys_driver_data` = mt8183 main path без ext (подтверждает нашу одно-путевую схему) | `mt6765.dtsi:779,1219,1271,1282,1294,1316-1430`; `mtk_drm_drv.c:262-266` | полезно (структура), адреса **не** наши |
| 2 | `mt6765_dsi_phy_timing()` + `mt6765_dsi_config_vdo_timing()` + `mt6765_regs`-квирки (DSI_EN reserved, PS_SEL для RGB666, ULPS/cmd-mode) | `mtk_dsi.c:296-320,354-366,484-507,646-664,809-830,1166-1185,1857-1864` | резерв, если будут артефакты на 1534.8 Мбит/с |
| 3 | Init BOE-панели на Himax TDDI (`boe_nv110wum_init`, `SETEXTC 0xb9`) — единственный публичный шаблон DCS для нашего класса (наш DDIC = HX83102E TDDI, панель BOE TV110XUM) | `panel-himax-hx83102.c:26-57,95-101,200-303,900-916` | **самое ценное** (шаблон под пересчёт) |
| 4 | `preserve_fw_calibration`/`rt_code`: как не убить калибровку D-PHY, оставленную LK | `phy-mtk-mipi-dsi-mt6765.c:113-189` | полезно как приём (сам драйвер — другой инстанс PHY) |
| 5 | IOMMU/SMI/CMDQ-параметры 6765: `RESET_AXI|WR_THROT_EN`, identity larb-remap, `bus_sel = LARB1|LARB3`, GCE-события `MUTEX0_STREAM_EOF=130`, `DSI0_DONE=143` | `mtk_iommu.c:1702-1712`; `mtk-smi.c:494,771`; `mtk-cmdq-mailbox.c:896`; `mediatek,mt6765-gce.h:61,92,141-143` | сверка при SMI hang / GCE timeouts |

Не полезно: `himax_hx83112b.c` (сток, наш `patches/0040` впереди),
`panel-rabbit-r1.c` (ST7701, 480×640), clk-таблицы и mmsys-маршруты 6765
(другая раскладка), `pinctrl-mt6765` (другая нумерация EINT).

Границы доверия: выводы сделаны **чтением исходников**, на железе ничего из
этого не проверялось (Rabbit R1 нет). Всё, что помечено «наш порт работает»,
опирается на `docs/STATUS.md` (kmscube 56.4 fps, `modetest -M mediatek`).

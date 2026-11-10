# План порта

Цель: **Ubuntu + Wayland/GNOME** с **DRM/KMS** и **GPU (panfrost)** на
Fplus T1100 (MT6771). План итеративный; каждая фаза заканчивается проверяемым
результатом.

## Фаза 0 — выбор базового дерева ✅ (решение 28.10.2026)

- **База: mainline LTS 6.12.y**, MT6771 добавляем в дерево как новый SoC.
- Обоснование — `docs/research.md`: DISPSYS/GPU/PMIC MT6771 совпадают с
  mainline **MT8183** (адреса блоков, IRQ, MT6358), GPU — тот же Mali-G72 MP3.
- Downstream 4.14/4.4 MTK (Hadenix, Nokia, Realme) — **не база**, а референс
  регистров/панели: DRM в них нет (`mtkfb`), плюс они вне mainline-подсистем.
- Downstream 4.19/5.x с `mtk_drm` для MT6771 публично отсутствует.
- **Готово:** решение записано в `docs/STATUS.md`; критерий фазы 1 — ниже.

## Фаза 1 — SoC bring-up (DTS + подсистемы) ✅ закрыта 05.11.2026

Работа (по возрастанию сложности):
1. **DTS `mt6771.dtsi` + `mt6771-t1100.dts`** — клон структуры `mt8183.dtsi`
   с адресами/IRQ из `refs/stock-mt6771.dts`.
2. **`clk-mt6771`** (`topckgen`, `infracfg_ao`, `pericfg`, `apmixedsys`, `mfgcfg`,
   `mmsys`) — самая большая новая работа; за основу `clk-mt8183*.c`, сверить
   gate-биты по downstream `clk-mt6771.c`. **Сначала проверить гипотезу
   «обойтись MT8183»**: в `adomerle/mt6771-next` отдельного clk-драйвера нет
   (`refs/mt6771-next/`).
3. **`pinctrl-mt6771`** — на базе `pinctrl-mt8183.c`, сверить IO-конфиг/EINT.
   В том же WIP-порте используется `pio` из `mt8183.dtsi`; проверить на железе.
4. **pwrap + MT6358** (`mt6358-regulator`, `mt6358-keys`, `mt6358-rtc`) —
   переиспользовать mainline-драйверы, нужен корректный `pwrap` для MT6771.
5. **watchdog (`mtk-wdt`), `mt6577-uart` (console), MMC (`mtk-sd`), USB
   (`mtu3`/`xhci-mtk`), `mtk-smi`/IOMMU (`mtk-iommu`)**.
6. **ramoops/pstore** — единственный канал логов без UART (см. риски).

**Принято 05.11.2026:** ядро загружается до `systemd running`, видны RAM и eMMC
(`free`, `lsblk`: `mmcblk0` 57.6 ГиБ), работает USB-RNDIS + SSH, заряжается
батарея и корректно работает `poweroff`. Гипотеза «обойтись MT8183» подтверждена:
отдельные `clk-mt6771`/`pinctrl-mt6771` не понадобились (гейты совпадают побитно,
`docs/STATUS.md`).

## Фаза 2 — DRM/KMS дисплей — **закрыта (10.11)**

1. `mmsys`-route-таблица MT6771 для `drivers/soc/mediatek/mtk-mmsys.c`
   (по `mt8183_mmsys_routing_table`).
2. DRM-компоненты: OVL0/2L, RDMA0/1, COLOR, CCORR, AAL, GAMMA, DITHER, DSI,
   MUTEX, PWM (compatible `mediatek,mt6771-*` → `mt8183-*` fallback, где совпадает).
3. `mtk_dsi` + `mtk_mipi_tx`: сверить DSI PHY-тайминги (downstream `ddp_dsi.c`).
4. DRM panel-драйвер **BOE TV110XUM-LB2 через ITE IT6112** (1600×2176, 4 lane,
   video mode): исходник есть — `refs/it6112/panel-it6112-boe-tv110xum-lb2.c`
   (WIP, 6.16 → бэкпорт на 6.12). RE не требуется.
5. Backlight: `pwm-backlight` / `mtk-pwm` + GPIO питания.

**Готово:** панель показывает консоль на дефолтном пути драйвера
(`boot_ubuntu27`), `modetest` выставляет режим `1600x2176` на `DSI-1` (`rc=0`),
`kmscube` крутит куб на панели 56.4 fps, `glmark2-es2-drm` — **Score 452**
(Mesa 25.0.7, GLES 3.1, panfrost).

## Фаза 3 — GPU (panfrost)

- `CONFIG_DRM_PANFROST`, GPU-node (`mediatek,mt6771-mali` → `arm,mali-bifrost`),
  MFG power-domain (`spm`), `mfgcfg`-клок.
- Mesa panfrost; проверка `glmark2`/`es2gears`.
- **Готово:** Mesa 25.0.7, GLES 3.1, `kmscube` 56.4 fps, `glmark2` Score 452
  (всё в `/usr/local`, rootfs не тронут).

## Фаза 4 — в работе: Weston на панели (10.11)

- Ubuntu-base arm64 rootfs (systemd), root на ext4 — **сделано**: p54, метка
  `ubuntu` (Ubuntu 24.04.3).
- Wayland: **Weston 13** с DRM/atomic-бэкендом работает на панели; EGL/GLES
  через panfrost, `weston-simple-egl` 56.4 fps (kiosk-shell, `card1`).
- **Осталось:** ввод с тача (Himax, evdev/libinput), десктоп KDE Plasma/GNOME.
- **Готово:** рабочий стол на дисплее, ввод с тача.

## Фаза 5 — периферия

- Wi-Fi/BT (CONSYS_6771 = MT6630/MT6631): в mainline не поддержано — ни
  драйвера, ни DTS-узлов; `mt76` этот чип не покрывает. Реалистичный путь —
  порт вендорского стека `wlan_drv_gen3` + `wmt_drv` (+ conninfra) и прошивок
  из `/vendor/firmware`; BT идёт через тот же WMT (HCI UART H4). Это отдельный
  крупный проект. USB-донгл требует host/OTG, которого сейчас нет.
- Тач Himax (`i2c@11007000`, 0x48), evdev/libinput.
- **Готово:** сеть (RNDIS или Wi-Fi/BT после порта) и ввод стабильны.

## Фаза 6 — прошивка/откат

- Перепаковка boot: `scripts/repack_boot.py --ref <сток> --kernel Image.gz
  --dtb mt6771.dtb --ramdisk <initramfs>` (заголовок и адреса наследуются от
  стокового образа, DTB заворачивается в MTK-контейнер; round-trip проверен).
- Прошивка через recovery/`dd`.
- Бэкапы `boot_a`/`vbmeta`/`seccfg`; тест откатов.
- **Готово:** воспроизводимая прошивка и возврат на сток.

## Риски

- **Clock-драйвер MT6771** — основной объём новой работы (gate-биты сверять
  по downstream `clk-mt6771.c`).
- **Логи при загрузке**: UART-доступ к плате не подтверждён; ставка на
  `ramoops`/pstore + «тихий» boot (см. STATUS, блокеры).
- **Панель/мост IT6112**: исходник WIP-драйвера есть (`refs/it6112/`), но он
  не проверен на нашем ядре; RE больше не основной путь, а fallback.
- **Периферия**: вендорные блобы/прошивки (Wi-Fi/BT).
- **Кирпич при прошивке** — только через recovery/с бэкапом.

## Критерии успеха v1
1. `kmscube` на панели (KMS).
2. `glmark2`/`es2gears` с GPU (panfrost).
3. GNOME/Wayland на дисплее.
4. SSH/сеть, стабильный ввод.

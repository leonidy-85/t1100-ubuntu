# Передача проекта (обновлено 12.11.2026, конец сессии)

Кратко: **mainline 6.12 грузится на T1100 до Ubuntu 26.04 LTS с KDE Plasma
6.6.4; панель 1600×2176@58.93 (сдвиг убран 0046+0052), тач HX83102E работает,
8 ядер, panfrost/Mesa 26.0.3; Wi-Fi/BT — фаза 5.**

## История: состояние на 11.11 (устарело — актуальное ниже, «Состояние на конец 12.11»)

1. **Тач HX83102E — снова в проекте (11.11).** Состояние: `sense_on`
   работает (патч 0043), кадры идут по IRQ, но все 56 байт одинаковы
   (`14 × 00 03 00 00`) — точек нет; следующий шаг — добрать init из
   `docs/touch-hx83102e.md` §2.2 (`0x10007f04=0`, `reload_disable`,
   `reg_re_init`/`func_re_init`), `touch_avdd` → `always-on`, pull-up на GPIO1.
   Прежнее описание (оставлено для контекста): Контроллер отвечает по I2C, питание аналоговой части
   (GPIO163 `ts-avdd`) починено, драйвер привязан (`/dev/input/event1`), **но
   кадров не отдаёт**. Причина найдена RE (`docs/touch-hx83102e.md`):
   читаем не тот адрес (AHB `0x30` вместо регистра `0x30` восьмибитного
   пространства), нет burst (`0x13=0x31`, `0x0D=0x10`), checksum вендора —
   16 бит по байтам до первого `0x00`. Команда `bringup` начала реализацию
   (образ с драйвером — `build/boot_ubuntu33.img`, sha256 `64864160…`).
2. **Порядок на завтра:** §7 в `docs/touch-hx83102e.md` (burst on → `write
   0x11=0` → чтение регистра `0x30`, 56 Б) → правка драйвера → проверка
   касаниями (**сначала** `tools/host/screen-msg.sh --touch`: сообщение на
   панель латиницей, кириллица в консольном шрифте не рисуется) → затем
   libinput/`libinput-data`, десктоп (KDE/GNOME), DVFS GPU (только вместе с
   управлением VSRAM).
3. **Wi-Fi/BT — фаза 5, текущая задача.** Combo MT6630/MT6631 (CONNSYS),
   вендорский `wlan_drv_gen3` только для 4.14, прошивки в `/vendor/firmware`
   (`WIFI_RAM_CODE_6759`, `WMT_SOC.cfg`, `soc3_0_ram_*.bin`), в mainline
   драйвера нет. Сначала идентификация чипа/шины и выбор пути (порт вендорского
   или mainline-аналог), только потом правки железа. Без USB доступа к планшету
   нет.

## Состояние на конец 12.11 (продолжать отсюда)

- **Rootfs/десктоп:** p54 — Ubuntu 26.04 LTS + KDE Plasma 6.6.4 + SDDM
  autologin root; Konsole, Dolphin, Kate, Ark, Gwenview, Okular, KCalc,
  Spectacle, Plasma Keyboard, Mesa 26.0.3. Старый 24.04 —
  `/home/l/t1100-rootfs2404-backup.tar.gz` (sha256 `29f440bd…`), 26.04
  desktop tar — `/home/l/t1100-rootfs2604-desktop.tar.gz` (sha256 `b75a40c4…`).
- **Ядра:** `maxcpus=8`, `nproc=8`.
- **Сдвиг кадра: убран** (0046 + **0052**): `vbp 284`, `vfp 8`, `vtotal 2476`,
  refresh 58.93 Hz; проверено на `build/boot_touch8.img` (sha256 `757f7e03…`,
  md5 p29 `75aff08106e36c5ba207081c8cfc77ad`), пользователь подтвердил.
- **Тач: работает** (`boot_touch8`). Кадр читается через 1-байтный
  суб-адрес `0x30`; init: `sense_off`, burst, `0x100072EC=0`,
  `0x10007F04=0`, `0x9000005C=0`, reset 20/50 мс, **без**
  `reload_to_active`, poll `A8==0x05`. Отладочные чтения `A8` убраны — они
  read-clear и «съедали» флаг. Ориентация: KWin сам поворачивает портретные
  координаты 1600×2176, поэтому патч 0051 убрал `inverted-x`/`swapped-x-y`.
  Осталась задержка выделения в приложениях (evdev ~112 Гц, kernel не тормозит).
- **Plasma Keyboard:** добавлен ряд цифр 1–0 в
  `/usr/share/plasma/keyboard/layouts/fallback/main.qml` и `en_US/main.qml`
  (настройка rootfs, не патч ядра).
- **Wi-Fi (фаза 5, путь A):** M1/M2 закрыты (`wmt_drv.ko` `0b4a2bfa…`,
  `wlan_drv_gen3.ko` `cfd182c5…`), M3 подготовлен (DT, `boot_ubuntu41`,
  `tools/host/wifi-deploy.sh`) — на железе **не проверялся**. Главный риск —
  STP-HIF для MT6631.
- **Нельзя одновременно** прошивать образ тача и Wi-Fi: по одному шагу за раз,
  после каждого проверять дисплей/GPU и оставлять точку отката.

## Текущее состояние платы (14.11)

- `boot_a` = `build/boot_nonwifi_amp.img` (md5 p29
  `61e08a8b698a0bb8e2a4601f6303808e`): Ubuntu 26.04 + KDE 6.6.4, 8 ядер,
  панель 1600×2176@58.93 (0046+0052), рабочий тач (0051), GPU DVFS
  (0058/0059), CPU DVFS (0062/0063: `mtk-cpufreq`, 793…1989 МГц,
  `schedutil`) и CPU thermal zone (0064: 80/90/115 °C, throttling
  проверен). Wi-Fi в этот образ не включён. Type-C dual-role (0066/0067):
  host с флешкой работает, VBUS 5.05 В / 2.4 А, возврат host→device через
  helper `t1100-usb-role` без перезагрузки. Батарея: ёмкость по OCV
  (0069). Гарнитура: jack работает вручную (`HPL/HPR Mux=2`,
  `Speaker Switch=off`, патчи 0070/0071); авто-ACCDET не сделан. SVS пока выключен;
  efuse-калибровка MT6771 не декодируется, thermal использует дефолтные
  коэффициенты (см. STATUS 13.11 (10), 14.11 (1)).
- **Suspend:** `systemctl suspend` работает через s2idle (`SuspendState=freeze`).
  Перед сном systemd-хук отцепляет UDC, после пробуждения возвращает его;
  `t1100-suspend-default.service` держит `mem_sleep` в `s2idle`.
  Deep `mem` (PSCI deep) на этой прошивке не восстанавливается — после него
  нужен power-cycle, поэтому deep не используем (см. STATUS 13.11 (11)).
- **Микрофон работает:** причина прежнего `EINVAL` — выключенный DAPM-маршрут
  `UL1_CH1/CH2 ADDA_UL`, а не формат. Маршрут и муксы (`PGA L/R = AIN0`)
  применяет `t1100-audio-mixer.service`; PipeWire source `alsa_mic` (node 33)
  — по умолчанию, `arecord` и `parecord` дают ненулевой сигнал. `PGA Volume`
  после закрытия потока сбрасывается в 0 dB (`mt6358_amic_disable`), но захват
  от этого не страдает.
- На планшете стоит `t1100-power-guard` (гасит при `vbat < 3.6 В`, поднимает
  `ICHG` до 2 А); в recovery он не работает — там заряд ведёт LK.
- Откат USB-эксперимента: `/tmp/opencode/boot_a_before_usb_role.img`
  (md5 `d4cdc9ef…`, boot_gpudvfs10); старый рабочий backup
  `/tmp/opencode/boot_a_backup.img` (`781d18eb…`).

## Что проверено на железе

| Что | Доказательство |
|---|---|
| LK принимает наш DTB | `tools/lk/verify-dtb.sh` 10/10 + фактическая загрузка; DTB `e11c39df…`/`f8d935da…`/`481905ed…` в разных образах |
| Ядро 6.12 → userspace | `systemctl is-system-running` = `running`, `Startup finished in 3.5s + 2.3s` |
| eMMC HS400 | `mmcblk0 57.6 GiB`, 56 разделов |
| USB-RNDIS + SSH | гаджет `1d6b:0104`, `usb0 = 10.42.66.66`, `ssh root@10.42.66.66` по ключу |
| **Зарядка** | `mt6370-charger`: `online=1 status=Charging charge_type=Fast`, `vbus 4940 мВ`, `vbat 3645 мВ`, `ibus 400 мА` |
| **Выключение** | `systemctl poweroff` → USB-гаджет исчезает через ~3 с, `/sys/fs/pstore` после включения **пуст** (DRAM обесточена) |
| KMS: компоненты/режим | `mediatek-drm` bound (ovl×3, rdma×2, color/ccorr/aal/gamma, dsi), CRTC `active=1`, режим `1600x2176@60, 248356 кГц` |
| DSI стартует | трасса `T1100DSI: started, start=0x1, mode=0x1, ps=0x312c0, txrx=0x3c` |
| Мост IT6112 | id `0x6112`, настройка совпадает с вендором побайтно (RX 17 + TX 24 записи проверены через `i2cpeek`), RX видит video (`0x5e 0x21 bit3=1`) |
| **Экран** | **чёрный** — единственная незакрытая проблема |

## Артефакты

- Ядро: дерево на build-хосте `/home/l/t1100-ubuntu-build/src` (6.12.114 +
  коммиты), локально — только патчи `patches/0001…0039` (0035 отключён, лежит
  как `wip-0035-*.disabled`); сборка — `scripts/build-kernel-remote.sh`.
- Образы: `build/boot_ubuntu14.img` (md5 `38fe9c1f…`, зарядка+выключение, экран
  чёрный), `build/boot_ubuntu17.img` (md5 `36397256…`, + трасса DSI).
- Rootfs-оверлей: `rootfs-overlay/` (страховка от разряда `t1100-power-guard`),
  ставится `tools/host/install-power-guard.sh [host|--rootfs DIR]`.
- Rootfs: на планшете — `p54` (ext4, метка `ubuntu`, Ubuntu 24.04.3 + systemd +
  sshd + root authorized_keys этого хоста + `t1100-power-guard`). Исторические
  архивы `build/rootfs/*.tar.gz` в локальном дереве сейчас отсутствуют
  (`build/` нет); живая копия на p54 — единственная, при пересборке не потерять.
- Инструменты: `tools/host/{recovery.py,flash-ssh.sh,usb-net.sh,check-power.sh,
  diag-drm.sh,watch-usb.sh,vendor-it6112.sh}`, `tools/lk/{extract-boot-dtb.py,
  verify-dtb.sh}`, `tools/i2cpeek`, `tools/mempeek`, `tools/fbtest`.
- Логи: `refs/device/dmesg-ubuntu4-boot.txt.gz`, `journal-ubuntu4-first-boot.txt.gz`,
  `dmesg-ubuntu6-ssh.txt.gz`; `refs/device/last_kmsg-*`.

## Что не работает и почему (главное)

**Экран: РАБОТАЕТ на дефолтном пути драйвера** (`boot_ubuntu27`, 10.11):
причина чёрного экрана — запись `TX 0x06` bit2 в «TX on» (в LK эта ветка не
вызывается). Фаза 2 закрыта: `modetest` выставляет `1600x2176` на `DSI-1`,
`kmscube` (фаза 3, panfrost) — 56.4 fps, `glmark2` — Score 452.
Ниже — история до этого открытия (эксперимент A с `skip_init`).

Доказано, что SoC гонит поток: CRTC активен, `DSI_START=1`, режим
sync-pulse, 4 линии, `ps=0x312c0`; мост видит видео и настроен как у вендора;
питание (DVDD/DSV 5500 мВ) и подсветка (100 %) включены — но панель чёрная.
Публичного референса нет: в порту **этой же** платы (`refs/mt6771-next`) узел
панели `status = "disabled"`, то есть он никогда не работал; PennyOS — другая
панель без моста. Вендор инициализирует панель **в LK** (`lcm_init`,
per-panel конфиг по смещению `0x90ea8`), а вендорское ядро потом только
дописывает 9 регистров и стримит.

Проверенные и отвергнутые гипотезы:
- клоки/гейты MT6771 ≠ MT8183 — **неверно**, совпадают побитно;
- IPPC/`IP version 0x0` — вторично, на картинку не влияет;
- T-PHY не выходит в device-сессию — **верно для USB** (патч 0020 заменён
  на 0060, software role switch), к дисплею не относится;
- неверные тайминги/порядок питания панели — исправлено (0030), не помогло;
- неверная формула TX-PLL моста — исправлено (0029), не помогло;
- полный побайтный повтор вендорской последовательности на живом мосте — **не помогло**;
- порядок `mipi_dsi_attach` → `drm_panel_add` (панель видна DRM раньше attach) —
  правка **ломает загрузку**, откачена.

## Как продолжить (следующая сессия)

0. **Сначала вернуть картинку:** на плате остался `boot_ubuntu22` (нормальный
   init, экран **чёрный** — это ожидаемо, не поломка). Прошить
   `build/boot_ubuntu24.img` (`skip_init=1`, sha256 `6df4ab28…`) тем же
   `tools/host/flash-ssh.sh`, что вернёт консоль на панели.
1. **Доступ.** Подключить планшет кабелем к ноутбуку:
   - наша Ubuntu → интерфейс `t1100usb`, `10.42.66.67/29` настраивается сам
     (udev по `1d6b:0104` + профиль NetworkManager), затем `ssh root@10.42.66.66`;
   - recovery → `telnet 10.42.66.66`, меню `3` → `y` (root-шелл без пароля);
     в recovery зарядка работает всегда.
   Прошивка: `tools/host/flash-ssh.sh <img> /dev/mmcblk0p29 [--reboot]` (по SSH)
   или `tools/host/recovery.py put <img> /dev/mmcblk0p29` (в recovery).
   **Без кабеля к ноутбуку доступа нет** — Wi-Fi в mainline не поддержан.
1a. **Страховка от разряда работает** (проверено на железе 06.11): юнит
   `t1100-power-guard.timer` тикает раз в минуту, поднимает
   `constant_charge_current` до 2 А, ругается в journal на SDP-порт, а при
   `vbat < 3.6 В` гасит плату через 0034 (проверено тестом: рельсы снимаются,
   `pstore` пуст). Пороги — `/etc/default/t1100-power-guard`, баланс —
   `tools/host/watch-power.sh`, переустановка — `tools/host/install-power-guard.sh
   [host|--rootfs DIR]`.
2. **Дисплей — по порядку:**
   a. снять **безопасный** дамп: только DSI/PHY (`0x14014000…`, `0x11e50000…`),
      без `mmsys/ovl/rdma` (их чтение при выключенных PD вешает interconnect —
      так погиб 0035); проверить, что `start`, `mode`, `ps`, `txrx`, тайминги и
      `PLL_CON0/1`, `CK_CKMODE_EN` соответствуют ожидаемым;
   b. `grep 14014000.dsi /proc/interrupts` — в video-режиме IRQ может быть
      выключен, поэтому «0» ничего не доказывает (уже проверено);
   c. если SoC-сторона в порядке — единственный оставшийся путь **RE инициализации
      панели в LK** (`rtc_power_off`/`lcm_init`, `0x5601ef24`, конфиг `0x90ea8`):
      что именно LK пишет в мост/DSI и в каком порядке, и чем это отличается от
      нашего драйвера;
   d. альтернатива: проверить гипотезу «LK инициализирует панель при любой
      загрузке» — образ, где наш драйвер **не трогает** мост в `prepare()`
      (только DSI + DCS), и посмотреть, появится ли картинка.
3. **Сделано:** GPU (panfrost; патч 0039 включает `&gpu`) **прошит**:
   panfrost 1.2.0, Mesa 26.0.3, GLES 3.1, `kmscube` 56.4 fps, Weston 13.
   **DVFS включён** (0058 — coupler MT6771/MT8788, 0059 — DTS: OPP
   698/743/800 МГц, VGPU/VSRAM spread 100 мВ, VSRAM без `always-on`);
   `boot_gpudvfs10.img` sha256 `68c74d1e…`, p29 md5 `d4cdc9ef…`;
   devfreq `13040000.gpu` `simple_ondemand`, 698/743/800 МГц.
   `glmark2` Score 1409/1583; в сценах `conditionals`/`function`/`loop`/`logic`
   есть `panfrost gpu sched timeout` и при 698, и при 800 — это отдельный
   shader-баг panfrost, не DVFS. Откат — `/tmp/opencode/boot_a_before_gpudvfs.img`
   md5 `886c86cb…`. **USB host/OTG (0060/0061):** `boot_usb_host.img`
   (md5 p29 `d0d9bca9…`) — T-PHY software role switch, `dr_mode=otg`,
   MT6370 OTG VBUS; флешка определяется (`sda`, 62.9 GB), VBUS 5050 мВ.
   Динамический возврат host→device ломает xHCI, поэтому host — до
   перезагрузки. **Дальше:** panfrost shader timeout, Wi-Fi/BT, безопасный
   возврат USB-роли, suspend, задержка выделения тача.
4. **Мелочи:** `constant_charge_current` = 2 А теперь поднимает
   `t1100-power-guard` (драйвер сам ставит 900 мА); вернуть `tcpc`, когда
   понадобится OTG/host (сейчас отключён, `tcpci` не находит узел `connector`);
   топливомера (проценты заряда) в mainline нет — только `status`/`current`.

## Wi-Fi / BT (фаза 5 — в работе)

В mainline 6.12 поддержки нет: ни драйвера, ни DTS-узлов.
Вендорский стек уже портирован и **собирается** под 6.12 (`wmt_drv.ko`,
`wlan_drv_gen3.ko`, M2 закрыт), DT для CONSYS/MT6631 — патч 0049,
M3 подготовлен build-only (`tools/host/wifi-deploy.sh`); на железе ещё
не запускался. Хронология — `docs/STATUS.md`, записи «11.11 (5)…(7)»
и «12.11».

Combo CONSYS_6771
(MT6630/MT6631), Wi-Fi — вендорский `wlan_drv_gen3` через WMT/CONNSYS, BT —
HCI UART H4 через тот же WMT; прошивки — в `/vendor/firmware`, в rootfs их нет.
`mt76` этот чип не покрывает, USB-донгл требует host/OTG (сейчас нет).
Подробности — `docs/hardware.md`. Сеть пока только RNDIS.

## Грабли (не наступать снова)

- `reserved-memory` в нашем DTB должен существовать, но без статических детей
  (кроме своей `ramoops@70000000`, не пересекающейся с `mblock-*`).
- `regulator-coupled-with` mainline не поддерживает; без `always-on` на
  VDRAM2/VBIF28 `regulator_late_cleanup()` гасит DRAM → зависание до printk.
- **DCS в мост не уходит при взведённом `HOLD_TX`**: LK (`0x56031714`) не шлёт
  пакет, пока `TX 0x05` bit5 = 1. Наш драйвер снимал hold **после** DCS →
  `exit sleep`/`display on` терялись (это и был чёрный экран).
- **`0x560318a0` в LK — это power-off моста**, а не включение: наш
  `it6112_mipi_power_on()` повторял именно его.
- **GPIO моста в «пассивном» режиме — только `GPIOD_ASIS`**: запрос
  `stby`/`ext-pwr` как `GPIOD_OUT_LOW` снимает EXT_PWR (GPIO175) и убивает мост
  (PID `0x0000`, все регистры `0x00`). Перепроверено 07.11.
- **Чтение MM-регистров** (`mmsys/ovl/rdma`) при выключенных power-domain вешает
  плату (проверено: 0035). Только DSI/PHY или при гарантированно включённых блоках.
- `mipi_dsi_attach()` в I2C-probe до `drm_panel_add()` — дедлок/незагрузка.
- В Ubuntu-rootfs не было пользователя `sshd` (из-за этого sshd не стартовал) и
  `sshd_config` — теперь добавлены; при пересборке rootfs не потерять.
- `TCG/NetworkManager`: статический адрес на USB-интерфейсе сбрасывается, если
  NM управляет устройством — снимать с управления (`tools/host/usb-net.sh`).
- RNDIS требует отцеплять UDC перед suspend: это делает
  `t1100-usb-gadget.sh`; sleep-таргеты размаскированы. Deep `mem` не
  восстанавливается, используется только s2idle.
- Зарядка от USB-порта ноутбука = 500 мА (SDP): при работе Ubuntu это
  отрицательный баланс. Больше не разряжается в ноль только благодаря
  `t1100-power-guard` (гасит ниже 3.6 В), но работать так нельзя — нужен 2 А
  зарядник, либо зарядка выключенным/в recovery.
- Калибровка батареи (06.11): 3.693 В ≈ 10 % на вендорском gauge, 4.12 В ≈ 82 %;
  проценты нелинейны, а от порта ноутбука в recovery в батарею идёт 0 мА
  (`IBAT=0`). Заряжать только от 2 А адаптера: 3.697 → 4.12 В за ~2 ч.
- **«boot on charger»**: после `poweroff` с воткнутым кабелем плата сама
  включается от VBUS. Выключать и выдёргивать кабель, иначе цикл «включилась →
  садится».

## Прочее по инфраструктуре

- **Build-хост**: `172.17.141.172`, `l` / `0` (sudo тот же пароль), 12 ядер,
  15 ГБ RAM, Ubuntu 26.04, кросс-тулчейн `aarch64-linux-gnu-gcc` установлен.
  Сборка ядра — только там: `scripts/build-kernel-remote.sh`
  (rsync в `/home/l/t1100-ubuntu-build/{src,out}`, артефакты в `build/remote/`).
  Локальная сборка (`scripts/build_kernel.sh`) осталась как резерв.

- MCP `web-search` починен (Brave через `curl`, фильтр релевантности, fallback
  Bing→Marginalia) и включён в `opencode.json`; встроенный `websearch` в этой
  сети отдаёт 403, Google/Яндекс/DDG — блок/капча.
- Публичного mainline-порта дисплея для MT6771/MT8788 нет (подтверждено поиском).

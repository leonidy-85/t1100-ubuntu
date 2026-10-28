# План порта

Цель: **Ubuntu + Wayland/GNOME** с **DRM/KMS** и **GPU (panfrost)** на
Fplus T1100 (MT6771). План — итеративный; каждая фаза заканчивается проверяемым
результатом.

## Фаза 0 — выбор базового дерева
- Вариант A: mainline 6.x + патчи из `Helio-P22/linux-mainline` (MT6765) как
  референс.
- Вариант B: downstream 4.19/5.x MTK (если найдётся с `mtk_drm`).
- Критерий: грузится до консоли/ramdisk, видны CPU/RAM/uart.
- **Готово:** ядро стартует, есть serial/SSH.

## Фаза 1 — SoC bring-up (DTS)
- DTS: clock, pinctrl, regulator, `mmsys`, `disp`, `dsi`, `mali`, `smi`/`iommu`.
- Источник: downstream DTS MT6771 + mainline MT6765.
- **Готово:** `clk_summary`, питание, uart, USB-gadget.

## Фаза 2 — DRM/KMS дисплей
- Порт `dispsys` → `mediatek-drm`: DSI host, CRTC (OVL/RDMA), MMSYS/mutex/CMDQ.
- DRM panel-драйвер для DSI-панели (init из LCM).
- **Готово:** `modetest`/`kmscube` выводят картинку на панель.

## Фаза 3 — GPU (panfrost)
- `CONFIG_DRM_PANFROST`, GPU-node в DTS (clock/regulator/power).
- Mesa panfrost; проверка `glmark2`/`es2gears`.
- **Готово:** GLES-рендер на экране.

## Фаза 4 — Ubuntu userspace
- Ubuntu-base arm64 rootfs (systemd), root на ext4 (p54 или LV).
- Wayland + GNOME (или Weston для первых тестов).
- **Готово:** рабочий стол на дисплее, ввод с тача.

## Фаза 5 — периферия
- Wi-Fi: вендорный `wlan_drv_gen3` + `/vendor/firmware`, либо mainline `mt76`.
- Тач/evdev, USB, (опционально) звук.
- **Готово:** сеть и ввод стабильны.

## Фаза 6 — прошивка/откат
- Перепаковка boot (kernel+DTB+initramfs), прошивка через recovery/`dd`.
- Бэкапы `boot_a`/`vbmeta`/`seccfg`; тест откатов.
- **Готово:** воспроизводимая прошивка и возврат на сток.

## Риски
- **Дисплей — главный риск**: нет TRM, только исходники; объём работы велик.
- Панель: init/тайминги; тач-калибровка.
- GPU: panfrost на G72 — ок, но нужен рабочий KMS/драйвер платформы.
- Периферия: вендорные блобы/прошивки.
- Кирпич при прошивке — только через recovery/с бэкапом.

## Критерии успеха v1
1. `kmscube` на панели (KMS).
2. `glmark2`/`es2gears` с GPU (panfrost).
3. GNOME/Wayland на дисплее.
4. SSH/сеть, стабильный ввод.

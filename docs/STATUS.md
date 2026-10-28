# STATUS — t1100-ubuntu

## Фаза

**0 — scaffold.** Порт не начат: ничего не собиралось и не прошивалось.

## Сделано

- [x] Проект создан: `README.md`, `AGENTS.md`, `opencode.json`, `docs/`.
- [x] `docs/hardware.md`, `docs/research.md`, `docs/porting-plan.md`.
- [x] Агенты: `lead`, `bringup`, `kernel-drm`, `gpu-mesa`, `distro-userspace`,
      `reverse-engineer`.
- [x] Скил `mt6771-port` + локальный `scripts/boot_patch.py`.

## Следующий шаг

1. `lead`: выбрать базовое дерево (mainline 6.x + патчи `Helio-P22/linux-mainline`
   **или** downstream 4.19/5.x MTK с `mtk_drm`) и записать решение ниже.
2. Передать `bringup`: минимальный DTS MT6771 + загрузка до консоли/USB.

## Решения (decision log)

| Дата | Решение | Обоснование |
|---|---|---|
| — | — | — |

## Блокеры

- Нет.

## Риски

- Дисплей: нет TRM, только исходники; объём работы по `mediatek-drm`.
- Панель/тач: init и калибровка.
- Wi-Fi: вендорный `wlan_drv_gen3` + `/vendor/firmware` либо mainline `mt76`.
- Прошивка: только через recovery/`dd` с бэкапом.

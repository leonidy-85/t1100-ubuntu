# AGENTS.md — проект t1100-ubuntu (порт Linux с KMS на MT6771)

Правила для агентов opencode. Читать в начале сессии.

## Что это

Проект порта Linux (mainline) на планшет **Fplus T1100**
(SoC **MT6771 / MT8788 = Helio P60/P70**, GPU **Mali-G72 MP3 Bifrost**) с целью
**рабочий стол + DRM/KMS + panfrost**. Фазы 0–3 закрыты: mainline 6.12
(патчи `patches/` 0001–0082) доходит до systemd, панель работает, KMS
закрыт `modetest`, panfrost даёт GLES 3.1 (`kmscube` 56.4 fps, `glmark2`
Score 452). Userspace — **ALT Mobile + Phosh** (до 21.11 был Ubuntu+KDE,
есть бэкап старого rootfs): тач, Waydroid с Android 13, Wi-Fi и GPS
работают. В работе: BT (свой HCI-драйвер `t1100_bt` поверх STP/BTIF,
был рабочий прогон 16.11), аппаратный видеодекод (развилка — ADR `0004`),
DVFS GPU. FM заблокирован firmware (`docs/fm-port-log.md`). Актуальное
состояние — `docs/STATUS.md`.

## Обязательный контекст

1. `docs/hardware.md` — железо, разделы, текущее состояние.
2. `docs/research.md` — публичные исходники/ссылки и что не публично.
3. `docs/porting-plan.md` — фазы и точки рисков.
4. Соседний проект `../t1100` — доступ к планшету, recovery, перепаковка boot.

## Правила работы

1. **Не прошивать без бэкапа**: `boot_a`, `vbmeta_a`, `seccfg` (см. `../t1100`).
   Бэкапы и инструмент — в `../t1100/backup_5.1.6.110/`.
2. **Прошивка только через recovery или `dd` с проверкой sha**, как в
   `../t1100/.opencode/skills/aurora-mediatek-security-off`.
3. **Дисплей — отдельная сложная задача**: не считать «ядро загрузилось»
   готовностью десктопа. KMS проверяется `kmscube`/`modetest`, GPU — `glmark2`.
4. **Не выдумывать регистры**: брать их из публичных исходников MT6771
   (`Hadenix/android_kernel_alps-4.4`, `dispsys`) и mainline `mediatek-drm`.
5. **SoC-прошивки MTK не трогать** (`preloader`, `lk`, `tee`, `md1img`, `nvram`,
   `nvdata`, `protect*`) без явной необходимости — риск потерять устройство.
6. **Сообщать фактический результат** команд (прошло/не прошло, точный вывод),
   а не предположения.
7. TRM MT6771 **не публичен** — референс = исходники ядра; дизассемблирование —
   только как fallback (см. агента `reverse-engineer`).
8. **Коммиты атомарные**: один коммит = одна законченная мысль (док, проба,
   скрипт, патч). Формат сообщения — `area: что сделано` (например
   `probe: root по SSH и дамп с платы`, `phase0: база = mainline 6.12`).
   Не смешивать в одном коммите несвязанные правки; сборки/дампы не коммитить
   (`/build/` в `.gitignore`, факты — в `refs/`).
9. **Пуш периодический**: после каждого законченного шага и в конце сессии —
   `git push origin master` (gitflic `py6on/t1100-ubuntu`). Не копить коммиты
   локально.

## Сборка и тяжёлые вычисления — на build-хосте

**Правило: компиляция ядра, Mesa и любые тяжёлые вычисления выполняются не на
локальной машине.** Локальный ноутбук (4 ядра) постоянно занят другими
проектами: полная сборка ядра там занимала ~4 часа и мешала всему остальному.

| | |
|---|---|
| хост | `172.17.141.124` (hostname `ai1`; до 23.11.2026 был `172.17.141.172`) |
| пользователь | `l` (пароль `0`, `sudo` — тот же пароль; вход по ключу `id_ed25519`) |
| ресурсы | 12 ядер, 30 ГБ RAM, Ubuntu 26.04 |
| тулчейн | `aarch64-linux-gnu-gcc` (установлен), `rsync`, `bison`, `flex`, `libelf-dev`, `libssl-dev` |

Рабочий процесс:

```sh
scripts/build-kernel-remote.sh              # rsync дерева -> defconfig+fragment -> Image dtbs -> build/remote/
scripts/build-kernel-remote.sh --clean      # снести out/ на хосте
scripts/build-kernel-remote.sh --config     # только конфиг
```

Дерево синхронизируется по rsync (без `.git`) в `/home/l/t1100-ubuntu-build/src`,
выход — в `.../out`, артефакты затягиваются в `build/remote/`. Инкрементальные
сборки после правки пары файлов — минуты, `ccache` на хосте включён
(masquerade `~/.ccache-bin`, `CCACHE_DIR=~/.ccache-t1100`).

Userspace-утилиты для планшета (в его rootfs нет ни apt, ни libdrm) собираются
там же статически:

```sh
scripts/build-tools-aarch64.sh            # modetest (libdrm 2.4.131, static)
tools/host/kms-test.sh [--dump|--hold N]  # залить на планшет и проверить KMS
```

Подробности (каталоги на хосте, meson cross-file для arm64-sysroot, как добавить
пакет в sysroot без apt-мультиарха) — `docs/cross-build.md`.

Если на хосте нет тулчейна: `sudo apt-get install -y --no-install-recommends
gcc-aarch64-linux-gnu libssl-dev bison flex libelf-dev rsync`.

Прочее (ssh к планшету, recovery, git, документация, перепаковка boot.img) —
локально, это лёгкие операции.

## Устройство — эксклюзивный ресурс

Планшет один. Параллельные исполнители на нём конфликтуют: `kmscube`/`glmark2`/
`modetest` держат DRM master, и второй прогон падает с `Failed to become DRM
master` (проверено 10.11). Правило: тяжёлые прогоны на устройстве — по одному,
с явным согласованием у `lead`; фоновые сборки (build-хост, sysroot) — сколько
угодно, они устройство не трогают.

## Коммиты при параллельной работе

`git add -A` в этом репозитории захватывает и правки, которые в этот момент
пишут субагенты (так изменения `scripts/remote/build-mesa-aarch64.sh` попали в
коммит про Weston, 10.11). Правило: при работе агентов с параллельными сессиями
коммитить **явные пути** (`git add docs/STATUS.md …`), а не всё дерево; перед
коммитом смотреть `git status`.

## Оркестрация

- **Входная точка — агент `lead`** (tech lead/архитектор): ведёт `docs/STATUS.md`,
  выбирает базовое дерево, выстраивает фазы и принимает результат.
- Специалисты — рабочие; `lead` делегирует им через `subagent` или ты
  переключаешься (Tab) на нужного.
- Порядок: `bringup` → `kernel-drm` → `gpu-mesa` → `distro-userspace`;
  `reverse-engineer` — только по конкретной блокировке.
- Специалист отдаёт **фактический вывод**, `lead` обновляет `STATUS.md` и
  принимает/возвращает.

## Роли (агенты)

| Агент | Роль |
|---|---|
| `lead` | оркестратор: roadmap, STATUS, выбор базы, приёмка |
| `bringup` | DTS, clock/pinctrl/regulator, SMI/IOMMU, загрузка |
| `kernel-drm` | DRM/KMS-драйвер дисплея MT6771 |
| `gpu-mesa` | panfrost, GPU-node, Mesa, GLES |
| `distro-userspace` | Ubuntu rootfs, systemd, Wayland/GNOME, Wi-Fi/ввод |
| `reverse-engineer` | опционально: дизассембл недостающих блобов |

## Не-цели v1

Модем, камера, HEVC-декод, Ubuntu Touch — вне скоупа, если не заработают
«сами». Звук базово работает (динамик/наушники через UCM, приложения
выбора выхода); автодетект гарнитуры (ACCDET) не сделан. Android — только
контейнером Waydroid (работает), hybris не нужен.

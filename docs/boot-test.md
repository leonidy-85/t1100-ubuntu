# Первая загрузка mainline: протокол (без UART)

UART-подключения нет. Логи — **только через pstore** (ramoops в RAM), читаются
после возврата на Aurora. Поэтому каждая тестовая загрузка — это «выстрелил и
смотри в pstore».

## Что нужно

1. Наше ядро: `Image.gz` (gzip от `arch/arm64/boot/Image`).
2. Наш DTB: `mt6771-fplus-t1100.dtb` (обязательно с узлом `ramoops`, см. ниже).
3. initramfs: `scripts/make_initramfs.sh` (busybox + маркеры
   `T1100-INITRAMFS-START/OK`).
4. Образ: `scripts/make_test_boot.sh --dtb <board.dtb>` — собирает всё одной
   командой (`scripts/repack_boot.py` внутри; заголовок/адреса — от стокового
   `boot_a`, DTB заворачивается в MTK-контейнер), печатает sha256 и проверяет
   образ обратным разбором.
5. Бэкап **текущего** стокового `boot_a`: `build/backup/boot_a_stock_2026.img`
   (32 МиБ, sha256 `9601bcd6…b864f`, снят с платы по USB-telnet 29.10.2026).
   План отката — recovery, `p29`. Старый `../t1100/backup_5.1.6.110/` на этом
   хосте отсутствует.

## Размеры (проверено 29.10.2026)

DTB `mt6771-fplus-t1100.dtb` = **4941 B** (не «~48 КБ») — с патчем 0003.
`Image.gz` (defconfig + фрагмент, `DEBUG_INFO_NONE`) ≈ 13,4 МБ, initramfs
≈ 1,0 МБ: суммарно **≈ 14,4 МБ** при разделе `boot_a` 32 МиБ — влезает с
запасом. Точные размеры/хеши этой сборки — в `docs/provenance.md`.

## Обязательные узлы/параметры для логов

- `chosen/bootargs`: **без** `console=`/`earlycon=`/`stdout-path` —
  `maxcpus=1 panic=10 pstore.backend=ramoops`. UART-гейт до появления
  `clk-mt6771` закрыт LK, и первый printk в gated-периферию опасен; console-логи
  пишет `pstore`-консоль (`CONFIG_PSTORE_CONSOLE`). Для UART позже добавить
  `earlycon=mtk8250,0x11002000 console=ttyS0,921600n8`.
- DTS `reserved-memory`: `ramoops@54410000` (0xe0000) с `record-size=0x10000`,
  `console-size=0x40000`, `pmsg-size=0x10000` — параметры берутся из DT, не из
  cmdline. Регион вырезан из System RAM и в стоковом FDT, и у нас.
- PSCI (`arm,psci-1.0`, smc) + `mediatek,mt8183-wdt` — чтобы `panic=10`
  действительно перезагружал плату (патч 0003).
- `CONFIG_PSTORE=y`, `CONFIG_PSTORE_CONSOLE=y`, `CONFIG_PSTORE_RAM=y`,
  `CONFIG_PSTORE_PMSG=y`, `CONFIG_MEDIATEK_WATCHDOG=y`, `CONFIG_ARM_PSCI_FW=y`.

## Цикл теста

1. Собрать образ, сверить sha256, положить в `build/boot_a_test.img`.
2. **Только с подтверждением владельца**: прошить в `p29` через recovery
   (`dd bs=1M conv=fsync`) или `dd` из Aurora; сверить sha на устройстве.
3. Перезагрузка. С патчем 0003 panic (`panic=10`) вызывает PSCI SYSTEM_RESET
   или TOPRGU-сброс, и lk снова грузит `boot_a` (наш образ). Если PSCI на этом
   ATF не отдаёт `SYSTEM_RESET`, плата останется в `System halted` — тогда
   ребут кнопкой питания (это проверяется именно этой загрузкой).
4. **Вход в recovery** (кнопки), прошить стоковый `boot_a` из
   `build/backup/boot_a_stock_2026.img` (p29). RAM не обнуляется, pstore
   остаётся.
5. Прочитать лог **сразу в recovery** (там есть `/sys/fs/pstore`):
   `python3 /tmp/opencode/rec.py 'ls -l /sys/fs/pstore; cat /sys/fs/pstore/console-ramoops*'`
   либо, вернувшись в Aurora, `scripts/t1100_root.sh 'cat /sys/fs/pstore/console-ramoops'`.

### Доступ к recovery по USB (проверено)

`telnet 10.42.66.66:23` → меню Aurora Recovery v2.0 → `3` → `y` **без Enter** →
код `12345`. Раздел: `/dev/mmcblk0p29`. Меню требует код блокировки: если
отправить `y\n`, пустая строка уйдёт как код («Wrong code»).

## Риск зацикливания (принять осознанно)

Если наше ядро падает до инициализации `ramoops`, логов не будет, а устройство
будет циклически перезагружаться (lk всегда грузит `boot_a`). Выход — recovery
по кнопкам + `dd` стокового образа (инструкция в
`../t1100/.opencode/skills/aurora-mediatek-security-off/SKILL.md`,
`manual_flash_instructions.txt`). Поэтому:
- первый тест — **минимальный** DTB (CPU/GIC/timer/uart/memory/ramoops),
- `panic=10`, никаких экспериментов с `misc`/слотами A/B на этом этапе.

## Порядок «сначала безопасное»

1. Проверить образ **без прошивки**: `repack_boot.py` → `bootimg_extract.py`
   обратно → сверить kernel/ramdisk/dtb (round-trip уже подтверждён).
2. Первая прошивка — когда есть осознанный минимум: ядро и DTB, которые с
   высокой вероятностью дойдут хотя бы до `start_kernel` (CPU/GIC/timer/uart —
   клоны mt8183/MT8365).

## Быстрая прошивка без recovery (Aurora + SSH)

```sh
ssh defaultuser@<ip> 'cat > /tmp/test.img' < build/boot_a_loadfix.img
T1100_HOST=<ip> T1100_SSH_PASS=... T1100_PASS=... \
  scripts/t1100_root.sh 'sha256sum /tmp/test.img; \
  dd if=/tmp/test.img of=/dev/mmcblk0p29 bs=1M conv=fsync; sync; \
  sha256sum /dev/mmcblk0p29'
```

`devel-su` берёт пароль из `T1100_PASS`, SSH — из `T1100_SSH_PASS`
(скрипт отключает `SSH_ASKPASS`: keyring отдаёт пароль по имени хоста и
ломается при смене IP).

## Важно: адрес загрузки ядра

Стоковый `Image` собран с `text_offset=0x80000`, mainline — с `0x0`. По
протоколу ARM64 образ с `text_offset=0` требует загрузки по 2 МиБ-выровненному
адресу, а LK грузит по адресу из заголовка boot.img (`0x40080000`, не
выровнен). `make_test_boot.sh` теперь ставит `KERNEL_ADDR=0x40200000`; если LK
игнорирует `kernel_addr` из заголовка, это не поможет — проверять отдельно.
Пока запуск mainline не подтверждён, `boot_a` после каждого теста
возвращается из `build/backup/boot_a_stock_2026.img`.


## Диагностика: payload, который рисует адрес загрузки (29.10)

Все варианты ядра дают «ни одного printk»: смерть до первых сообщений. Чтобы
отделить проблемы загрузчика от проблем ядра и узнать фактический адрес,
собран минимальный payload `tools/payload/addr_bars.S` (328 B):

- валидный arm64 `Image` (`text_offset=0x80000`, `image_size`);
- очищает экран в тёмно-серый;
- рисует 36 блоков 16×16 (шаг 20 px) — биты `(runtime_addr >> 12)` LSB-first
  (белый = 1), плюс контрольную строку `0xAA`;
- рисует **по обоим кандидатам** базового адреса fb: `0x7cd80000`
  (стоковый `mblock-11-framebuffer`) и `0x7cb80000` (board DTS из
  `linux-mediatek`), затем `wfi`.

Фото экрана даёт сразу: (1) прыгнул ли `lk` в наш образ, (2) какой fb-base
живой, (3) точный адрес загрузки — выровнен ли он на 2 МиБ.

```sh
tools/payload/build.sh --out build/payload_boot.img
# прошить в p29 и перезагрузить (см. выше); сфотографировать экран
```

Дальше по результату:
- адрес **не** выровнен на 2 МиБ → нужен shim-загрузчик (копирует несжатый
  `Image` на выровненный адрес) либо правка `text_offset`/`head.S`;
- адрес выровнен → причина не в выравнивании: смотреть DTB (PSCI/GIC/memory),
  пробовать DTS на базе `mt8183.dtsi` из `refs/mt6771-next/`.

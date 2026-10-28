# Первая загрузка mainline: протокол (без UART)

UART-подключения нет. Логи — **только через pstore** (ramoops в RAM), читаются
после возврата на Aurora. Поэтому каждая тестовая загрузка — это «выстрелил и
смотри в pstore».

## Что нужно

1. Наше ядро: `Image.gz` (gzip от `arch/arm64/boot/Image`).
2. Наш DTB: `mt6771-fplus-t1100.dtb` (обязательно с узлом `ramoops`, см. ниже).
3. initramfs: `scripts/make_initramfs.sh` (busybox + маркеры
   `T1100-INITRAMFS-START/OK`).
4. Образ: `scripts/repack_boot.py` (заголовок/адреса — от стокового `boot_a`,
   DTB заворачивается в MTK-контейнер).
5. Бэкап: `../t1100/backup_5.1.6.110/boot_a_5.1.6.110.img` (sha256
   `bd2c2758…73a9`), план отката через recovery (p29).

## Обязательные узлы/параметры для логов

- `chosen/bootargs`: `console=ttyS0,921600n8` (на будущее), `panic=10`,
  `ramoops.mem_address=0x54410000 ramoops.mem_size=0xe0000
  ramoops.console_size=0x40000 ramoops.pmsg_size=0x10000
  pstore.backend=ramoops`.
- DTS `reserved-memory`: `ramoops@54410000` (0xe0000) — регион вырезан из
  System RAM и в стоковом FDT, и должен остаться вырезанным у нас.
- `CONFIG_PSTORE=y`, `CONFIG_PSTORE_CONSOLE=y`, `CONFIG_PSTORE_RAM=y`,
  `CONFIG_PSTORE_PMSG=y`.

## Цикл теста

1. Собрать образ, сверить sha256, положить в `build/boot_a_test.img`.
2. **Только с подтверждением владельца**: прошить в `p29` через recovery
   (`dd bs=1M conv=fsync`) или `dd` из Aurora; сверить sha на устройстве.
3. Перезагрузка. Что бы ни случилось — ядро само уйдёт в панику/перезагрузку
   (`panic=10`), lk снова загрузит `boot_a` (наш образ).
4. **Возврат в Aurora**: прошить стоковый `boot_a` через recovery (p29).
   RAM при этом не обнуляется, поэтому pstore остаётся.
5. Прочитать лог: `scripts/t1100_root.sh 'cat /sys/fs/pstore/console-ramoops'`.

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

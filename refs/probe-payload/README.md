# probe-payload — минимальная arm64-«заглушка» для проверки цепочки загрузки

Зачем: отделить проблемы загрузчика от проблем ядра. Заглушка — валидный
arm64 `Image` (magic `ARM\x64`, `text_offset=0x80000`, `image_size`), который
ничего не инициализирует, а:

1. отключает TOPRGU-watchdog (`0x10007000`, WDT_MODE &= ~EN | KEY);
2. пишет `T1100PLD` + 8-байтный адрес исполнения в ramoops console zone
   (persistent_ram: sig `DBGC`, start, size) по трём кандидатным адресам
   (`0x54410000`, `0x54460000`, `0x544a0000`) и в `0x54400000`;
3. заливает 128 КиБ белым в буфер LK (`0x7cd80000`);
4. уходит в `wfi`.

Собирать:
```sh
T=<toolchain>/bin/aarch64-none-linux-gnu-
$Tgcc -c -nostdlib -ffreestanding -o payload.o payload.S
$Tld -Ttext=0 -nostdlib -o payload.elf payload.o
$Tobjcopy -O binary payload.elf payload.bin
# image_size в заголовке (offset 16) выставить вручную, затем gzip и
# repack_boot.py --ref <сток> --kernel payload.bin.gz --ramdisk ... --dtb ...
```

Результат на железе (29.10.2026): при стоковом контейнере и заглушке с
отключением WDT планшет **зависает на логотипе и не перезагружается** —
значит LK грузит и передаёт управление нашему образу. Раньше «циклы» были
сбросом от LK-шного watchdog, потому что mainline умирает до
`early_initcall` (где его останавливает наш драйвер).

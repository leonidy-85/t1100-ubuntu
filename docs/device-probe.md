# Снятие данных с планшета (без UART)

Дата: 28.10.2026. Устройство: Fplus T1100, Aurora 5.1.6.110, ядро 4.14.186.
UART-доступа нет — все данные снимаются **по SSH с самой платы** (скрипты на
планшете), логи загрузки — через **`ramoops`/pstore** в RAM.

## Доступ root (без sudo)

На планшете нет `sudo`; `devel-su` — setuid-обёртка, поднимающая **интерактивный**
root-shell и читающая код блокировки с tty. Рабочий способ:

```sh
scripts/t1100_root.sh 'id; ls /sys/fs/pstore'     # обёртка: ssh -tt + devel-su
```

Внутри: `ssh -tt defaultuser@172.17.141.62 devel-su`, затем `sleep`-паузы и
`12345\r`. Обязательно `\r` (не `\n`) и пауза ≥4 c после приглашения, иначе
ввод проглатывается. Пароль — код блокировки устройства.

> `devel-su -c '...'` и `su -c` **не работают** (первый закрывает сессию,
> второй: `Authentication failure`). `root@` по SSH запрещён (publickey,password).

## Что уже снято (`refs/device/`)

| Файл | Что |
|---|---|
| `fdt-live.dtb`, `fdt-live.dts.gz` | **живой FDT со всеми dtbo-оверлеями** (5400 строк) — включает board-узлы, которых нет в boot-DTB |
| `dmesg-stock.txt.gz` | полный `dmesg` стока (303 КБ) |
| `console-ramoops-prevboot.txt.gz` | `console-ramoops` **прошлой** загрузки (паника при `switch_root`) — доказательство, что pstore переживает перезагрузку |
| `config-stock.gz` | `/proc/config.gz` |
| `interrupts.txt`, `iomem.txt`, `partitions.txt`, `mounts.txt`, `cmdline.txt` | как есть |
| `opps.txt` | CPU OPP: 793…1989 МГц (policy0/policy4) |
| `mmc.txt` | CID eMMC `A3A561` + serial |

## Ключевые факты

- **pstore/ramoops работает и переживает reboot**: `/sys/fs/pstore/console-ramoops`
  (262132 Б) содержит лог предыдущей загрузки, включая `Kernel panic - not syncing:
  Attempted to kill init!` и дамп WDT. -> **это наш канал логов**, пока нет UART.
- **В стоковом ядре нет** `CONFIG_DEBUG_FS`, `CONFIG_DEVMEM` (`/dev/mem` нет),
  `CONFIG_KEXEC`, `CONFIG_DRM`. Есть `CONFIG_PSTORE=y`, `CONFIG_FB=y`,
  `CONFIG_SERIAL_8250_MT6577=y`. -> `clk_summary`, `regulator_summary`,
  `/dev/mem`-дампы регистров на стоке **недоступны**; регистры берём из DTB и
  downstream-исходников.
- **UART0** есть в ядре: `11002000.serial`, IRQ 286, `mt6577-uart`, `/dev/ttyS0`
  (baud в стоке не задан — `earlycon`/`console` для mainline уточнить по факту).
- **Резерв RAM под логи**: `0x54400000..0x54410000` — `ram_console`,
  `0x54410000 + 0xe0000` — `ramoops` (`console_size 0x40000`, `pmsg 0x10000`);
  в `/proc/iomem` эти диапазоны вырезаны из System RAM.
- **Board-узлы из dtbo** (их нет в boot-DTB, нужны для DTS):
  - `odm/lcm` = `elink,lcm`: `rst`=GPIO45, `dvdd`=GPIO55, `stby`=GPIO44,
    `bl`=GPIO56, `ext_pwr`=GPIO175, `ts_rst`=GPIO158, `ts_avdd`=GPIO163;
  - `mediatek,lcd-backlight`, `led_mode = 5`, `pwm_config = <4 0 0 0 0>`;
  - `himax_touch@48` на `i2c@11007000` (`compatible = "mediatek,himax_touch"`);
  - `usbkeyboard`, `hallsensor`, `focaltech_fp`, `vibrator`;
  - `panel@0` = `es,es6311_anx6585_zigzag_wxga` — **`status = "disabled"`**
    (остался от другого продукта, как и ATAG-lcmname).
- **Реальные LCM**: вкомпилирован `drivers/misc/mediatek/lcm/elink_lcm/
  tv110xum_lb2_incell/` (панель BOE TV110XUM, 1600×2176).
- Разметка: `mmcblk0p29` = 32768 КБ (`boot_a`) — совпадает с `docs/hardware.md`;
  с p32 начинается второй major (259) — второй GPT (A/B).

## Как снимать ещё (по мере надобности)

```sh
# bulk-сбор на плате -> /tmp/probe (chmod a+rX), затем scp
scripts/t1100_root.sh 'cp /sys/firmware/fdt /tmp/probe/fdt.bin; chmod -R a+rX /tmp/probe'
scp -r defaultuser@172.17.141.62:/tmp/probe/* build/device/
```

Регистры/dmesg после **нашей** загрузки: загрузиться с нашим ядром (ramoops в
cmdline/DTS), затем **тёплый reboot** в Aurora и `cat /sys/fs/pstore/console-ramoops`.

## Что это даёт проекту

1. `refs/device/fdt-live.dts.gz` — **полный** board-DTS с GPIO/регуляторами/тачем
   (основа `mt6771-fplus-t1100.dts`).
2. Подтверждён канал логов для первых загрузок mainline (pstore).
3. Подтверждён root-доступ по SSH скриптом — можно автоматизировать сбор фактов.

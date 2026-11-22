# Boot splash (Tux)

Раздел `logo` (p15) на этом устройстве обновить не удалось: LK показывал
чёрный экран и с оригинальной раскладкой, и с заменёнными кадрами (см.
историю в `docs/STATUS.md`). Поэтому сплеш рисуется из userspace сразу
после инициализации DRM.

## Как это работает

- `t1100-boot-splash.service` — oneshot, `After=systemd-udev-settle.service`,
  `Before=getty@tty1.service`, `WantedBy=multi-user.target`.
- `/usr/local/sbin/t1100-boot-splash` (python3 + PIL) ждёт `/dev/fb0` до 60 с,
  читает `virtual_size`, `bits_per_pixel`, `stride` из sysfs, требует 32 bpp,
  снимает blank и пишет кадр построчно через `os.pwrite`.
- Картинка — `/usr/share/t1100/splash.png` (1600×2176, RGB).

## Ориентация

Панель сканирует 1600×2176 (портрет). Сцена компонуется в ландшафте
2176×1600 и поворачивается **по часовой стрелке** (`Image.rotate(-90)`),
чтобы при горизонтальном положении планшета Tux и надпись стояли ровно.

## Пересборка картинки

```sh
tools/host/mksplash.py rootfs-overlay/usr/share/t1100/splash.png
# затем на планшет:
scp rootfs-overlay/usr/share/t1100/splash.png root@<ip>:/usr/share/t1100/
```

Генератор рисует фон-градиент, вписывает `Tux.webp` (или встроенный путь
`TUX` при необходимости) и текст «работает на всём, / даже на MTK».

## Ограничения

- Plymouth в initramfs не добавить: система грузится из `boot_a`
  (kernel + initramfs + dtb), а `dracut`/`mkinitrd` в ALT-образе нет.
- `fbcon` не активирован, но fbdev-эмуляция `mediatekdrmfb` выводит кадр на
  панель — проверено на холодной загрузке.
- Сплеш живёт до запуска Phosh; после этого экран перерисовывает композитор.

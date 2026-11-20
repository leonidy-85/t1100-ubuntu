# Бэкап rootfs T1100 (20.11.2026)

Полный слепок Ubuntu-rootfs планшета, снятый по USB-RNDIS (Wi-Fi-попытка
оборвалась на 2,5 ГБ и была удалена).

## Артефакт

| | |
|---|---|
| файл | `build/rootfs-backup/t1100-rootfs-20261120-1452.tar.zst` |
| размер | 20 738 170 880 Б (7,0 ГиБ) |
| sha256 | `42a7819774428b73c6cad7f5142e43aebdbaf2885cf1a27c7a43356e0428674a` |
| формат | GNU tar + zstd -3, `--numeric-owner --xattrs --acls --sparse` |
| исключено | `/proc`, `/sys`, `/dev`, `/run`, `/tmp`, `/var/tmp`, `/lost+found` |
| проверки | `pipeline_rc=0`, `zstd -t` rc=0, `sha256sum -c` — OK |

Рядом лежат `t1100-rootfs-20261120-1452.tar.zst.sha256`, `README.md`
(восстановление в каталог и на раздел, ограничения), `progress.sh` и
`t1100-rootfs-20261120-1452.progress.log` (обновление каждые 10 с).

Каталог `build/rootfs-backup/` в gitignore: сам архив в репозиторий не
коммитится.

## Что было почищено перед снятием

- `/root/Videos` очищен полностью (было ~11 ГБ).
- `/root/Music` — оставлена только папка `mp3` (227 МБ, 43 файла);
  удалено ~8,6 ГБ FLAC/AAC/ogv.
- Манифест удалённого: `/root/media-cleanup-20261120-143139.txt`, копия —
  `build/rootfs-backup/media-cleanup-20261120-143139.txt`.
- После очистки: занято 20 ГБ, свободно 27 ГБ из 49 ГБ
  (`/dev/mmcblk0p54`, ext4).

## Важное ограничение

Архив содержит только rootfs. Boot-раздел p29 (kernel + DTB + initramfs)
в него не входит. Для полного восстановления нужен отдельно текущий
`build/boot_pa.img` (md5 `d7c12647f9ca68dc2e37e31d5cba0f30`) или более
ранний boot-образ из `build/`.

## Восстановление

Проверка:

```sh
cd build/rootfs-backup
sha256sum -c t1100-rootfs-20261120-1452.tar.zst.sha256
zstd -t t1100-rootfs-20261120-1452.tar.zst
```

Разворачивание в каталог:

```sh
mkdir -p /mnt/t1100-rootfs
sudo tar -C /mnt/t1100-rootfs -xpf t1100-rootfs-20261120-1452.tar.zst \
    --numeric-owner --xattrs --acls
```

На раздел — только после монтирования нужного раздела и с проверкой, что
это именно rootfs T1100; для p29 и служебных разделов действует правило
«не прошивать без бэкапа».

# ALT Mobile на T1100 (замена rootfs)

Состояние на 20.11.2026: rootfs заменён на ALT Mobile Sisyphus 2026.09
(phoenix), Phosh 0.58 запускается автоматически, SSH и USB-RNDIS работают.
Ядро и boot-раздел p29 не менялись.

## Что было установлено

Исходный образ:

- `alt-mobile-phosh-def-20261012-aarch64.img.xz` — 1,8 ГиБ;
- распакованный `build/alt-mobile/alt-mobile.img` — 9,9 ГиБ,
  sha256 `885fa76111317ed91cfa43bfcb7719fd97139f7cfc610b283728b04f7b31a951`;
- MBR: p1 FAT32 241M, p2 ext4 617M (`/boot`), p3 f2fs 9G (root).

Ядро p29 (`6.12.114-wifi1`) собрано без `CONFIG_F2FS_FS`, поэтому f2fs-root
загрузить нельзя. Вместо этого содержимое ALT rootfs перенесено в ext4-образ:

- `build/alt-mobile/alt-root.img` — 12 ГиБ, ext4 label `altmobile`,
  UUID `b7f4c2d1-6a3e-4f5b-9c8d-1e2f3a4b5c6d`;
- sha256 образа `b5442e525339096eef22dc2779b3d183042bc3a28f385428a8f3fa333d335b9d`;
- gzip `build/alt-mobile/alt-root.img.gz` — 3,3 ГиБ,
  sha256 `20bf3701dd011dd1017afeaedddc5b8451f8965ce4ff65c19f11f371a097a042`.

Из старого rootfs перенесены:

- `/usr/lib/firmware` (около 721 МиБ);
- `/usr/lib/modules/6.12.114-wifi1` (модули Wi-Fi/BT/панели/panfrost/exfat);
- SSH host keys и `/root/.ssh/authorized_keys`;
- сервисы `t1100-wifi`, `t1100-bt`, USB-RNDIS, sleep-хук;
- `wmt-loader`, `t1100-wifi-func-on`, `t1100-bt-up`.

`/etc/fstab` ALT переписан на `UUID=b7f4... / ext4 defaults 1 1`; записи
`/boot` и `/boot/efi` удалены, так как отдельных p2/p1 на планшете нет.
`t1100-grow-root.service` после первой загрузки расширяет ext4 с 12 ГиБ до
размера p54 (около 50 ГиБ).

## Пользователь и доступ

- Создан `user` UID/GID 1000, home `/home/user`, shell `/bin/bash`;
- добавлен в `wheel, video, render, audio, input, networkops, users`;
- root и `user` имеют пароль, заданный при сборке; в репозиторий он не
  записывается;
- SSH: `/etc/ssh` перенесён из старого rootfs, `PermitRootLogin yes`,
  `PasswordAuthentication yes`;
- Wi-Fi: после первого запуска подключена сеть `home`, планшет получил
  `192.168.2.52/24`; SSH — `root@192.168.2.52`.
- USB-RNDIS: `usb0` получает `10.42.66.66/29`, хост — `10.42.66.67/29`.
  Имя USB-интерфейса на хосте меняется при каждой загрузке, поэтому профиль
  NetworkManager `t1100` надо привязывать к текущему `enx...`:

```sh
IF=$(ip -br addr | awk '/enx/ && $2!="DOWN" {print $1; exit}')
nmcli con mod t1100 connection.interface-name "$IF"
nmcli con up t1100
```

## Загрузка Phosh

ALT использует `greetd` + `phrog`. Штатный `[initial_session]` в
`/etc/phrog/greetd-config.toml` на этой сборке не запускал Phosh: greetd
поднимал greeter. Поэтому Phosh запускается отдельным systemd-сервисом
`t1100-phosh.service` (PAM-сессия `login`, tty1), а `phrog`/`display-manager`
отключены.

После загрузки Phosh показывает lock screen. `t1100-unlock.service` в течение
первой минуты несколько раз вызывает `loginctl unlock-sessions`, чтобы
десктоп открывался без ввода пароля. Это только для boot-сессии; ручная
блокировка после этого не снимается.

Чтобы не запускался мастер первого запуска ALT (`ready-set`), его user-юнит
замаскирован:

```sh
ln -sf /dev/null /etc/systemd/user/ready-set-existing-user.service
```

(в образе это `/etc/systemd/user/ready-set-existing-user.service`).

## Прошивка p54

Recovery: **Vol+ + Power**, USB к хосту, меню Jolla Recovery v2.0.
В recovery есть SSH (`root` / `recovery`):

```sh
gzip -dc build/alt-mobile/alt-root.img.gz |
    ssh root@10.42.66.66 'dd of=/dev/mmcblk0p54 bs=1M conv=fsync; sync'
```

Проверка первых 12 ГиБ:

```sh
ssh root@10.42.66.66 \
  'dd if=/dev/mmcblk0p54 bs=1M count=12288 2>/dev/null | sha256sum'
# b5442e52...335b9d
```

`reboot` из recovery. p29 не менялся: `build/boot_pa.img`
(md5 `d7c12647f9ca68dc2e37e31d5cba0f30`).

Попытка загрузить recovery через `kexec` из работающей Ubuntu не удалась:
ядро recovery загрузилось, но USB/сеть не поднялись; использован штатный
вход кнопками.

## Грабли, найденные при первом запуске

1. **Владелец системных каталогов.** `cp -a overlay/. "$DST/"` перенёс
   владельца каталогов overlay (UID 1000) на `/`, `/etc`, `/usr`, `/usr/lib`.
   В результате `messagebus` не мог выполнить `dbus-daemon`, а `phoc` не
   открывал tty. Исправлено:

```sh
chown root:root /
chmod 755 /
chown -R root:root /etc /usr /opt /srv /var /boot /root
find /etc /usr /opt /srv /var /boot /root -type d \
    -exec chmod u+rwx,go+rx {} +
chmod 1777 /tmp
```

   В `build/alt-mobile/setup-rootfs.sh` этот блок добавлен после копирования
   overlay, чтобы новые сборки не повторяли ошибку.

2. **`/run/dbus/users`.** ALT создаёт его из SysV-скрипта `messagebus`; при
   systemd каталога нет, и `dbus-run-session` падает с
   `Failed to bind socket ... No such file or directory`. Добавлен
   `/etc/tmpfiles.d/t1100-alt.conf`:

```ini
d /run/dbus/users 1777 root root -
d /var/lib/greeter 0700 _greeter _greeter -
d /var/lib/greeter/.cache 0700 _greeter _greeter -
```

3. **`ready-set`.** Мастер первого запуска открывал приветствие и приложения
   (Geary, Fractal). После настройки `performed-steps` и маскирования
   user-юнита он больше не запускается.

4. **greetd `initial_session`.** В этой версии ALT (`greetd 0.10.3-alt3`)
   `[initial_session]` не срабатывал: greetd всё равно запускал
   `/usr/libexec/phrog-greetd-session`. Обход — отдельный
   `t1100-phosh.service`.

5. **OSK.** В ALT нет `squeekboard`; Phosh использует `phosh-osk-stevia`.
   Старый `sm.puri.OSK0.desktop` ссылается на `/usr/bin/osk-wayland`, поэтому
   создан symlink:

```sh
ln -sf /usr/bin/phosh-osk-stevia /usr/bin/osk-wayland
```

## Проверка

- ядро `6.12.114-wifi1 #2`, ALT `2026.09` (phoenix);
- `resize2fs`: `/dev/mmcblk0p54` — 50 ГиБ, занято около 7 ГиБ;
- `t1100-phosh`, `dbus`, `systemd-logind`, `sshd`, `t1100-wifi` — active;
- `systemctl --failed` — 0;
- `grim` снимает Phosh 2176×1600, верхняя панель и OSK работают;
- Wi-Fi подключён к сети `home`: `wlan0` UP, адрес `192.168.2.52/24`,
  интернет проверен (`ping 1.1.1.1`); профиль сохранён в NetworkManager и
  должен подниматься автоматически. Адрес может измениться по DHCP —
  смотреть `ip -br addr show wlan0`.

## Ограничения

- Тач T1100 по-прежнему не готов; для Phosh нужен USB-ввод (мышь/клавиатура).
- Phosh после загрузки разблокируется сервисом; это не замена нормальному
  logind-автологину.
- Аппаратное H.264-декодирование не возобновлялось; текущая rootfs не меняет
  состояние `Vcodec`/SCP.
- `build/` в gitignore; образ ALT, gzip и overlay не коммитятся.

## Откат

- p29 не менялся: `build/boot_pa.img`, md5 `d7c12647f9ca68dc2e37e31d5cba0f30`.
- Старый rootfs: `build/rootfs-backup/t1100-rootfs-20261120-1452.tar.zst`
  (7,0 ГиБ, sha256 `42a78197...8674a`), инструкция —
  `build/rootfs-backup/README.md`.
- Предыдущие boot-образы: `build/recovery/boot_a_heaps_2026-11-20.img`
  (md5 `6bc3c35e...`), `build/scp/boot_vcodec2.img` (md5 `bc48aedf...`).

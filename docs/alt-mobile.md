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
- ALT проверяет пароли через **tcb**, а не только `/etc/shadow`. Поэтому
  после создания пользователя нужно создать
  `/etc/tcb/user/shadow` (и `/etc/tcb/root/shadow`) из соответствующих строк
  `/etc/shadow`; иначе `passwd -S` показывает пароль, но Phosh и sshd его не
  принимают:

```sh
install -d -m 2755 -o root -g root /etc/tcb/user
grep '^user:' /etc/shadow > /etc/tcb/user/shadow
chown root:root /etc/tcb/user/shadow
chmod 640 /etc/tcb/user/shadow
```

- `sudo` в ALT не установлен по умолчанию. Поставлен и разрешён группе
  `wheel`:

```sh
apt-get install -y sudo
printf '%s\n' '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
```

- `su` в пакете ALT имеет режим `0710` (без setuid), поэтому из-под
  пользователя не запускался. Исправлено:

```sh
chmod 4755 /usr/bin/su
# чтобы режим восстанавливался после перезагрузки:
printf '%s\n' 'z /usr/bin/su 4755 root root -' \
    >> /etc/tmpfiles.d/t1100-alt.conf
```

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

6. **Пароль не принимается при разблокировке.** Причина — tcb: запись в
   `/etc/shadow` без `/etc/tcb/user/shadow` не работает для PAM/Phosh. После
   создания tcb-файла пароль `user` проверен через SSH
   (`ssh user@10.42.66.66`, `LOGIN_OK`); `su - user` и Phosh используют тот
   же `pam_tcb`.

## Звук

В ALT не хватало UCM/PipeWire-настроек, поэтому WirePlumber показывал только
«Холостой выход». В образ добавлены файлы из старого Ubuntu-rootfs, где звук
уже был отлажен:

- `/usr/share/alsa/ucm2/conf.d/mt6771-mt6358/` — UCM-профиль динамика;
- `/etc/pipewire/pipewire.conf.d/51-alsa-sink.conf` — sink `MT6358 speaker`;
- `/etc/pipewire/pipewire.conf.d/52-alsa-mic.conf` — микрофон;
- `/etc/wireplumber/wireplumber.conf.d/52-auto-profile.conf`;
- `/usr/local/bin/t1100-audio-mixer.sh` + `ctlroute`/`ctlenum` + systemd
  `t1100-audio-mixer.service`.

После копирования:

```sh
systemctl daemon-reload
systemctl enable --now t1100-audio-mixer.service
# для уже запущенной сессии:
su - user -c 'XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user restart pipewire pipewire-pulse wireplumber'
```

Проверка:

```sh
su - user -c 'XDG_RUNTIME_DIR=/run/user/1000 wpctl status'
# Audio -> Sinks: MT6358 speaker и Internal speaker (default)
su - user -c 'XDG_RUNTIME_DIR=/run/user/1000 pw-play /usr/share/sounds/alsa/Front_Center.wav'
speaker-test -D hw:0,0 -c 2 -r 48000 -t sine -l 1
```

`t1100-audio-mixer.sh` выставляет `ADDA_DL_CH1 DL1_CH1`,
`ADDA_DL_CH2 DL1_CH2`, `DAC In Mux = Normal Path`,
`HPL/HPR Mux = LoudSPK Playback`; UCM делает то же при открытии потока.
Микрофон и переключение «динамик/наушники» — через `t1100-audio-ui` или
`amixer`/`alsaucm`.

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

## opencode на планшете (24.11.2026)

Установлен тот же CLI, что на ноутбуке: **opencode v2.4.1**, standalone-бинарь
под `aarch64`+glibc (ALT Sisyphus 2026.11, glibc 2.43 — подходит; Node.js не
нужен, бинарь self-contained на Bun).

- Установка шла **под `user`**, не под root: TUI запускается из Phosh-сессии,
  а `/root` для uid 1000 закрыт. Команда:
  `su - user -c 'curl -fsSL https://opencode.ai/v2/install | bash'`
  (скачано ~123 МБ архива, распаковано 258 МБ; установщик сам дописал
  `export PATH=/home/user/.opencode/bin:$PATH` в `~/.bashrc`).
- Бинарь: `/home/user/.opencode/bin/opencode`; при первом запуске поднимается
  фоновый сервис `opencode serve --service`.
- Авторизация: `~/.local/share/opencode/auth.json` (0600, uid 1000) —
  скопирован с ноутбука, провайдеры `deepseek` и `opencode-go`.
  Конфиг — `~/.config/opencode/opencode.jsonc`: `$schema` +
  `"model": "deepseek/deepseek-flash"`. MCP-серверы (gitlab/gitflic/
  craft-anything) намеренно не переносились: им нужны env-секреты и node.
- Запуск на экране: `kgx` (GNOME Console) → `opencode`; окно занимает весь
  экран 2176×1600, TUI рендерится нормально, модель видна в строке ввода.
  Проверено и без экрана: `opencode run "…"` по ssh отвечает.
- **Память.** Порог здесь жёсткий: из 3498 МБ при живом Phosh + Waydroid +
  Epiphany свободно ~0.3 ГБ, zram-swap забит на ~1.3 из 1.5 ГБ. TUI держит
  ~177 МБ RSS, сервис — ещё ~260 МБ. Перед работой закрывать браузер,
  при нехватке — `su - user -c 'opencode service stop'` (освобождает ~260 МБ)
  или останавливать `waydroid-container`.
- Не проверено вводом с экрана: Stevia-OSK для TUI (нужны `Ctrl`, `Esc`,
  стрелки, `Shift+Tab`). Если OSK не отдаёт их — USB-клавиатура через OTG
  (`mtu3`, USB-host уже работает).
- **MCP gitflic.** Сервер живёт на ноутбуке: `mcp-shared` слушает
  `127.0.0.1:8810` и проксирует `gitflic-mcp`. Наружу, только в USB-линк,
  его отдаёт юнит `mcp-gitflic-usb.service`
  (`socat TCP-LISTEN:8810,bind=10.42.66.67 → 127.0.0.1:8810`), т.е. в LAN
  порт не выставлен. На планшете в `~/.config/opencode/opencode.jsonc`:
  `mcp.servers.gitflic = {type: remote, url: http://10.42.66.67:8810/mcp,
  oauth: false}`; проверка — `opencode mcp list` → `✓ gitflic connected`.
  Токены при этом остаются на ноутбуке; на планшет дополнительно скопированы
  их копии для git-операций с самого устройства (0600, uid 1000):
  `~/.config/opencode/gitflic-mcp.env`, `secrets/gitflic_token`,
  `secrets/gitflic_git_credentials`.
- **Пароли `0`:** `root` и `user` (по просьбе; ALT хранит их в tcb,
  yescrypt/sha512). Проверено: `ssh user@10.42.66.66` по паролю и `sudo`
  из-под `user` работают, хеши сверены с `crypt("0")`. Для `root` в sshd
  включён `PermitRootLogin yes` (было `without-password`, бэкап
  `/etc/openssh/sshd_config.bak-*`): `ssh root@10.42.66.66` по паролю
  пускает, проверено и по USB, и по Wi-Fi. Устройство в сети, так что это
  осознанно слабые пароли на открытом порту 22.
- **Связка ключей (gnome-keyring).** Коллекция `login` была заперта старым
  паролем и **пуста** (`Items = []`), поэтому её не меняли, а пересоздали:
  бэкап `~/.local/share/keyrings/login.keyring.bak-20261124-2333`,
  новый ключ создан `printf '0\n' | gnome-keyring-daemon --replace --unlock
  --components=secrets` — пароль `0`. Проверено: свежий демон с `--unlock` и
  «0» открывает коллекцию (`Locked=false`), `secret-tool store/lookup`
  работает. При обычном входе разблокировку делает PAM
  (`pam_gnome_keyring` в `/etc/pam.d/greetd` и `/etc/pam.d/phosh`) — тем же
  паролем `0`, так что рассинхрона с логином больше нет.
  (`org.freedesktop.Secret.Service.SetAlias` в gnome-keyring 51.1 принимает
  только алиас `default`, поэтому «Вход»/`login` через D-Bus не назначить —
  используется файл `login.keyring`.)
- **git на планшете:** поставлен `git 2.50.1` (ALT Sisyphus). Авторизация в
  GitFlic — не basic-auth (логин/токен как пароль даёт 401), а заголовок
  `Authorization: token <GITFLIC_TOKEN>`; он прописан в
  `/home/user/.gitconfig` как `http.https://gitflic.ru/.extraHeader`
  (токен берётся из скопированного `secrets/gitflic_token`). Тот же приём
  использован на ноутбуке — с ним `git push` проходит, с `py6on:<token>`
  в URL/credential-store — нет. Идентичность git скопирована
  (`Андрей Маркин <py6on@yandex.ru>`).
- **ssh host key сменился** после переезда на ALT: sshd (ALT) читает ключи из
  `/etc/openssh/`, а не `/etc/ssh/`; действующий отпечаток ED25519 —
  `SHA256:4XLZcU/Asf/iPj4KLIngAzvjDo2Tf7N4Egbcv4FV8kk`. Старые записи
  `10.42.66.66` в `~/.ssh/known_hosts` удалены, новые добавлены.
- Планшет сейчас виден и по Wi-Fi: `wlan0` = `172.17.141.191/24` (адрес по
  DHCP и меняется — проверять `ip -br a show wlan0`, а не `192.168.2.52` из
  раздела «Проверка»); вход `ssh root@<ip>` по ключу или паролю `0`.

## Ограничения

- Тач T1100 по-прежнему не готов; для Phosh нужен USB-ввод (мышь/клавиатура).
- Phosh после загрузки разблокируется сервисом; это не замена нормальному
  logind-автологину.
- Аппаратное H.264-декодирование не возобновлялось; текущая rootfs не меняет
  состояние `Vcodec`/SCP. Прежняя среда vendor-декода была в старом Ubuntu
  rootfs и на ALT отсутствует, но не потеряна: в архиве
  `build/rootfs-backup/t1100-rootfs-20261120-1452.tar.zst` есть
  `root/android32-chroot.tgz`, дерево `root/kbuild/linux-6.12.114` и
  `root/vcodec-port/`. Для возобновления их можно распаковать в ALT (или во
  временный каталог), собрать модуль под `6.12.114-wifi1 #2` и загрузить без
  прошивки p29.
- `build/` в gitignore; образ ALT, gzip и overlay не коммитятся.

## Откат

- p29 не менялся: `build/boot_pa.img`, md5 `d7c12647f9ca68dc2e37e31d5cba0f30`.
- Старый rootfs: `build/rootfs-backup/t1100-rootfs-20261120-1452.tar.zst`
  (7,0 ГиБ, sha256 `42a78197...8674a`), инструкция —
  `build/rootfs-backup/README.md`.
- Предыдущие boot-образы: `build/recovery/boot_a_heaps_2026-11-20.img`
  (md5 `6bc3c35e...`), `build/scp/boot_vcodec2.img` (md5 `bc48aedf...`).

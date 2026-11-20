# Phosh на T1100

Мобильная оболочка Phosh установлена и работает поверх уже готового
Wayland/KMS/panfrost-стека. KDE Plasma остаётся установленной; переключение
между сессиями — через SDDM.

## Что установлено

```sh
apt-get install -y phosh phoc squeekboard phosh-mobile-settings \
    gnome-backgrounds grim
```

Версии на момент установки (Ubuntu 26.04, T1100):

| пакет | версия |
|---|---|
| `phosh` | 0.54.0-1 |
| `phoc` | 0.54.0-1 |
| `squeekboard` | 1.43.1-2 |
| `phosh-mobile-settings` | 0.53.0-2 |
| `gnome-backgrounds` | 50.0-1 |

`phosh-osk-stevia` используется как экранная клавиатура (запускается
автоматически в сессии Phosh).

## Включение сессии

SDDM остаётся display manager. Конфиг автологина:

`/etc/sddm.conf.d/10-t1100-autologin.conf`

```ini
[General]
DisplayServer=x11

[Autologin]
User=root
Session=phosh.desktop
Relogin=false
```

`DisplayServer=x11` здесь не означает X11-сессию: Phosh запускается как
Wayland-композитор `phoc`, а SDDM лишь выбирает `.desktop`-сессию.

Прежний конфиг с `Session=plasma.desktop` сохранён в
`/root/sddm-autologin-plasma.conf.bak`.

Применить:

```sh
systemctl restart sddm
```

Если после перезапуска SDDM падает с ошибкой cgroup
(`Failed to create cgroup /system.slice/sddm.service`), помогает:

```sh
systemctl daemon-reexec
systemctl start sddm
```

После обычной загрузки ошибка не повторялась.

## Проверка

В сессии должны быть процессы:

```sh
pgrep -af 'phoc|phosh|gnome-session|osk'
```

Ожидаемо: `phoc`, `gnome-session --session=phosh`, `/usr/libexec/phosh`,
`phosh-osk-stevia`.

Скриншот без X11:

```sh
grim /tmp/phosh.png
```

Проверено: PNG 2176×1600, видны верхняя панель, quick settings, список
приложений, Konsole и экранная клавиатура; OSK работает.

## Настройки после установки

Чтобы экран не блокировался и не гас без участия пользователя:

```sh
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
```

Обои:

```sh
gsettings set org.gnome.desktop.background picture-uri \
    file:///usr/share/backgrounds/gnome/blobs-d.svg
gsettings set org.gnome.desktop.background picture-uri-dark \
    file:///usr/share/backgrounds/gnome/blobs-d.svg
```

## Ограничения

- **Тач T1100 не готов.** Для работы с Phosh нужна USB-мышь и клавиатура
  (удобно через USB-хаб). Экранная клавиатура работает, но без тача это
  единственный способ ввода с самой панели.
- Родное разрешение панели — 1600×2176; ориентация и масштаб при
  необходимости настраиваются через `phosh-mobile-settings`/`wlr-randr`.
- Кнопку питания в сессии Phosh обрабатывает сам Phosh/logind, а не
  PowerDevil из KDE. Настройка `PowerButtonAction=1` в `powerdevilrc`
  действует только в сессии Plasma.
- Косметические предупреждения в журнале: `libseat seatd` (seatd не
  используется), `Failed to parse EDID`, `Failed to get emergency contacts`
  (нет `org.gnome.Calls`), начальное предупреждение `sm.puri.OSK0`,
  `Failed to write utmpx`. На работу не влияют.

## Возврат на Plasma

Восстановить бэкап:

```sh
cp /root/sddm-autologin-plasma.conf.bak \
   /etc/sddm.conf.d/10-t1100-autologin.conf
systemctl restart sddm
```

Либо вручную поставить `Session=plasma.desktop` в секции `[Autologin]`.
Phosh при этом остаётся установленным и доступен как отдельная сессия.

## Связь с декодированием

Установка Phosh не меняла загрузочный образ: p29 остаётся
`build/boot_pa.img` (md5 `d7c12647f9ca68dc2e37e31d5cba0f30`). Работа по
аппаратному H.264 поставлена на паузу по просьбе пользователя; состояние
и блокер парсера описаны в `docs/vcodec-bringup.md` и `docs/vdec-plan.md`.

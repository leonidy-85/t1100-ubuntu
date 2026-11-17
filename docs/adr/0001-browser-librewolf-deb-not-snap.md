# Браузер: LibreWolf из .deb, snap на планшете не используется

**Статус:** accepted (18.11.2026)

Ubuntu 26.04 отдаёт `firefox` и `chromium-browser` только как переходные
пакеты-заглушки под snap, а snapd на этой плате не работает: в ядре включён
только `CONFIG_SQUASHFS_ZLIB`, тогда как образы snap сжаты xz/zstd
(`docs/browser.md` §1). Поэтому браузер ставится настоящим `.deb` из
`repo.librewolf.net` — LibreWolf 160.0 arm64; это Firefox с отключённой
телеметрией, uBlock Origin и ужесточёнными настройками, то есть закрывает
требование «анонимно и безопасно, но YouTube работает».

## Рассмотренные варианты

| Вариант | Почему нет |
|---|---|
| `firefox` / `chromium-browser` из архива Ubuntu | заглушки snap; snap не монтирует squashfs (проверено опытом с gzip/xz/zstd) |
| Firefox `.deb` с `packages.mozilla.org` | репозиторий на 18.11.2026 отдаёт 404 (`dists/firefox/Release`), arm64-сборок нет |
| snap + включение `CONFIG_SQUASHFS_{XZ,ZSTD,LZ4,LZO}` | потребовало бы пересборки и прошивки ядра ради браузера; само по себе полезно (в фрагмент добавлено), но не как условие установки |
| Epiphany / Falkon / qutebrowser из архива | ставятся, но это WebKit/QtWebEngine без приватных дефолтов — не отвечают требованию «анонимный и безопасный» |

## Последствия

- Ключ репозитория проверяется по отпечатку `662E3CDD…2B12EF16`, установка
  воспроизводима: `tools/host/librewolf-install.sh`.
- Настройки браузера лежат в самом образе: `/etc/librewolf/user.js` +
  `t1100-browser-prefs.service` (раскладывает их в профили). Правка
  `configs/librewolf-user.js` (симлинк на файл в `rootfs-overlay/`) действует
  после перезагрузки или `systemctl start t1100-browser-prefs`.
- Если ядро однажды пересоберут с xz/zstd, snap станет рабочим — это не
  меняет решение: браузер уже поставлен как обычный `.deb`, snap не нужен.

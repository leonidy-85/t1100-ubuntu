# Upstream и vendor: как разделён наш набор патчей

## База

Все патчи применяются к **mainline stable 6.12.y** (у нас 6.12.114) из
kernel.org. Вендорские исходники connectivity-стека (wmt_drv,
wlan_drv_gen3, Bluetooth, FM, GNSS) взяты из публичных MediaTek GPL
релизов и живут отдельно, вне дерева ядра.

## Два набора

| файл | что внутри | куда |
|---|---|---|
| `patches/series-upstream` | DTS Fplus T1100, панель IT6112, мост IT66121/HDMI, тач Himax, звук MT6358, датчики, cpufreq/thermal, USB-роль, топливомер, фикс L2CAP (0077) | можно предлагать в mainline / linux-mediatek |
| `patches/series-vendor` | загрузочные хаки (framebuffer LK, watchdog, ramoops, регуляторы), вендорский RTC power-down, DTS CONSYS/Wi-Fi, BTIF, диагностика panfrost | только этот репозиторий |

`patches/series` остаётся полным набором для сборки рабочего ядра.

## Как предлагать upstream

1. Взять только `series-upstream`, применить к свежему `linux.git`
   (`git am`), проверить `make defconfig`, `dt_binding_check`.
2. Сгруппировать в тематические серии: (a) SoC/board DTS, (b) panel
   IT6112 + bindings, (c) HDMI DPI/IT66121 DTS, (d) touch, (e) sound,
   (f) fuel gauge.
3. Прогнать `scripts/checkpatch.pl --strict`, добавить
   `Signed-off-by`.
4. Отправить в `linux-mediatek@lists.infradead.org` (и в
   `devicetree@vger.kernel.org` для DTS/bindings) через
   `git send-email`/`b4`.

## Лицензии

- Наши патчи и DTS — GPL-2.0-only (DTS также BSD-2-Clause, как принято
  в ядре).
- MediaTek connectivity-код — GPL-2.0 из публичных релизов; файлы
  сохраняют исходные copyright.
- Прошивки в репозиторий не кладём.

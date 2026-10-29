# patches/ — наши изменения ядра как патчи

Дерево ядра живёт **вне** этого репозитория: `../linux-t1100` (mainline 6.12.y).
Здесь — только наши изменения, чтобы их можно было ревьюить и отправлять в
upstream.

## Схема

```
patches/
├── 0001-arm64-dts-mediatek-add-minimal-MT6771-SoC-descriptio.patch
├── 0002-arm64-dts-add-Fplus-T1100-MT6771-board.patch
├── 0003-arm64-dts-mt6771-add-PSCI-and-toprgu-watchdog.patch
└── series            # порядок применения
```

## Как делать патч

```sh
cd ../linux-t1100
# ...правки...
git add -A && git commit -m "clk: mediatek: add MT6771 clock drivers"
git format-patch -1 --output-directory ../t1100-ubuntu/patches --suffix=.patch
```

`format-patch -1` всегда нумерует файл как `0001-…`; переименовать в следующий
свободный номер и дописать строку в `series`.

## Как применить на чистое дерево

```sh
cd ../linux-t1100
git am ../t1100-ubuntu/patches/$(sed -n '/\.patch$/p' ../t1100-ubuntu/patches/series)
```

## Правила

- Патч = одна логическая единица (SoC dtsi, PSCI, clk, pinctrl, mmsys, board dts).
- В сообщении коммита: что сверено по downstream (`refs/stock-mt6771.dts`,
  downstream `clk-mt6771.c`) и что осталось проверить на железе.
- Не тащить downstream-код целиком: только данные (адреса, биты, таблицы).
- После применения — регресс: `make ARCH=arm64 O=build/t1100 dtbs` и сверить
  sha256 DTB с `docs/provenance.md`.

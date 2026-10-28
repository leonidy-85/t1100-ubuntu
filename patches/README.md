# patches/ — наши изменения ядра как патчи

Дерево ядра живёт **вне** этого репозитория: `../linux-t1100` (mainline 6.12.y).
Здесь — только наши изменения, чтобы их можно было ревьюить и отправлять в
upstream.

## Схема

```
patches/
├── 0001-arm64-dts-mediatek-add-mt6771.dtsi.patch
├── 0002-clk-mediatek-add-mt6771-clock-drivers.patch
├── 0003-pinctrl-mediatek-add-mt6771.patch
├── 0004-soc-mediatek-mmsys-add-mt6771-routes.patch
├── 0005-arm64-dts-add-fplus-t1100.patch
└── series            # порядок применения (git apply --directory)
```

## Как делать патч

```sh
cd ../linux-t1100
# ...правки...
git add -A && git commit -m "clk: mediatek: add MT6771 clock drivers"
git format-patch -1 --output-directory ../t1100-ubuntu/patches --numbered \
  --subject-prefix="PATCH t1100"
```

## Как применить на чистое дерево

```sh
cd ../linux-t1100
for p in ../t1100-ubuntu/patches/*.patch; do git am "$p"; done
```

## Правила

- Патч = одна логическая единица (SoC dtsi, clk, pinctrl, mmsys, board dts).
- В сообщении коммита: что сверено по downstream (`refs/stock-mt6771.dts`,
  downstream `clk-mt6771.c`) и что осталось проверить на железе.
- Не тащить downstream-код целиком: только данные (адреса, биты, таблицы).

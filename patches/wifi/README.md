# patches/wifi — патчи к вендорским исходникам, НЕ к ядру

Эти патчи **не применяются к `../linux-t1100`** и не входят в `patches/series`
(там серия патчей ядра). Они применяются к чистым клонам вендорского
connectivity-стека MediaTek (Motorola Pie-9):

```
common   github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-common
         Pie-9-release-POBS @ 3ff67212dcc45757c434ca5e1d35161c73ad7f55
wlan     github.com/MotorolaMobilityLLC/vendor-mediatek-kernel_modules-connectivity-wlan-core-gen3
         Pie-9-release-POBS @ 249649d877d87a151525c3c5629709eba337d2bd
```

Применение (`patch -p1` из корня соответствующего дерева) делает
`scripts/remote/build-wifi-remote.sh` в каталоге на build-хосте. Локально патчи
генерировались как `git diff` «чистый клон → портированное дерево»; никакой
вендорский код в этот репозиторий не копируется.

Логика порта и список правок по темам — `docs/wifi-port-log.md`, §18.

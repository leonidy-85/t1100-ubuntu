# BT (MT6631 поверх STP/BTIF) — лог порта и конфликтов

Дата: 23.11.2026. Рабочая база: ALT Mobile rootfs, ядро `6.12.114-wifi1`,
вендорский `wmt_drv` `7602ac53…` (quiet), `wlan_drv_gen3`, `mtk_btif_drv`.

## Что сделано за сессию

1. **Модули пересобраны** под текущее ядро на build-хосте `172.17.141.124`
   (сценарий `scripts/remote/build-bt-kmods-remote.sh`): `bluetooth`,
   `bnep`, `rfcomm`, `hidp`, `af_alg`, `algif_hash`, `algif_skcipher`,
   `algif_aead`, `ecc`, `ecdh_generic` (in-tree) + `t1100_bt`,
   `t1100_bt_probe` (наш HCI-драйвер, `bt/`). vermagic `6.12.114-wifi1`,
   sha256 в `build/bt/`.
2. **Модули разложены** на планшете: crypto/*, net/bluetooth/*,
   `updates/bt/t1100_bt*.ko`; `depmod -a`.
3. **Сте́лый модуль удалён**: коллега разложил в `updates/wifi/` старый
   `t1100_bt.ko` (16.11, `d4a8d045…`, собран до серии 0078) — modprobe грузил
   именно его, и `hci_register_dev` молча возвращал `-EINVAL` за ~30 мкс
   (`struct hci_dev` разъехался с текущим ядром; MODVERSIONS=n CRC не ловит).
   Диагностика — принты в `t1100_bt_init` (теперь в дереве).
4. **BT поднимается и работает в одномодовом режиме**: после ручного
   power-cycle CONSYS (`modprobe -r wlan_drv_gen3 wmt_drv`) и загрузки
   `wmt_drv` без лишних патчей: `hci0` регистрируется, `func_on(BT) -> 0`,
   скан находит устройства (телефон `Redmi A3 Pro` вплотную — сразу).

## Конфликты (все проверены на железе 23.11)

| # | Условие | Результат |
|---|---|---|
| 1 | `soc3_0_ram_mcu_e1_hdr.bin` в `t1100_rom_patch` (добавлен коллегой 4a0de53) | wlan поднимается, но **BT-радио глухое**: HCI-команды ходят, `Inquiry Complete` приходит, эфир пуст (0 устройств, телефон вплотную) |
| 2 | `soc3_0_ram_bt_1_1_hdr.bin` в `t1100_rom_patch` (наша попытка доставить BT-патч) | **`func_on(BT) -> 1`** всегда, даже без GPS/wlan — доставка через наш STP-путь ломает BT-функцию; файл извлечён из `aurora_root.img` (`7e362811…`), на планшете лежит в `/lib/firmware`, в конфиг не включён |
| 3 | GPS (`gps_drv` + `mnld`) активен → `func_on(BT)` | **`-> 1`**; принудительное включение клинит CONSYS (wlan0 исчезает, `wmt_drv` refcount `-1`, lsmod висит — только ребут) |
| 4 | wlan поднят, GPS нет, новый `wmt_drv` (quiet) | **`func_on(BT) -> 1`**, `hciconfig hci0 up` сегфолтится, bluetoothd SEGV на старте |
| 5 | wlan НЕ загружен, свежий power-cycle CONSYS, два ROMv4-патча | **работает**: `func_on(BT) -> 0`, скан находит устройства |

Вывод: старый `wmt_drv` (16.11, `73256ebb…`/`d3b83212…`) позволял BT при
поднятом wlan; новый quiet-стек — нет. Правильное лечение — вендорский поток
патчей через `wmt_launcher` (RE, см. `refs/m31`…`m41` — там же механизм
`srh_patch`/`patch-info`, которым вендор доставляет и BT-патч), либо перенос
в новый `wmt_drv` старой логики func_on(BT) поверх поднятого wlan.

## Эксплуатация сегодня

- BT — **вручную**, через `t1100-bt-on` (останавливает GPS, выгружает
  `gps_drv`, грузит BT-модули, поднимает `hci0`, размаскирует и стартует
  `bluetooth.service`); `t1100-bt-off` — наоборот. На загрузке BT выключен:
  `t1100-bt.service` disabled, `bluetooth.service` замаскирован (иначе
  bluetoothd SEGV на каждом буте — конфликт №4).
- Но в текущем quiet-стеке `t1100-bt-on` на живом wlan упрётся в конфликт
  №4: полноценно BT работает только после power-cycle CONSYS без wlan
  (скриптом: `systemctl stop t1100-wifi-early; modprobe -r wlan_drv_gen3
  wmt_drv; modprobe wmt_drv t1100_btif_stp=1 t1100_quiet_ms=100
  t1100_rom_patch="ROMv4_be_patch_1_1_hdr.bin ROMv4_be_patch_1_0_hdr.bin"`;
  затем `t1100-bt-on`; wlan вернуть `systemctl restart t1100-wifi-early`
  после). Автоматизировать до выяснения func_on-конфликта не стал.

## Не сделано / дальше

1. Реверс/портирование вендорского порядка патчей (`wmt_launcher`) —
   доставит и BT-патч, и, вероятно, снимет FM-блокер (та же механика).
2. `func_on(BT)` при поднятом wlan на новом `wmt_drv` — сравнить с
   `d3b83212…` (16.11) и локализовать изменённую логику STP/BTIF.
3. Pair/A2DP на ALT (16.11 проверены на Ubuntu-rootfs: pair + A2DP-транспорт
   с EDIFIER D12); PipeWire-звук через A2DP.
4. BD-адрес из NVRAM (сейчас дефолтный `00:00:46:07:88:01`).

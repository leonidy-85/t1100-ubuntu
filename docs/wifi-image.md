# Boot-образ с внутренним Wi-Fi (MT6631) поверх gauge v5 — build-only

Статус: **собран и проверен офлайн, на планшет НЕ прошивался**. Это образ для
одного диагностического прогона M81 (`docs/wifi-port-log.md` §82): ядро с
`CONFIG_WIRELESS_EXT` + узлы CONSYS/Wi-Fi в DTB + вендорские модули из того же
out-дерева. Wi-Fi при этом ещё **не работает** — образ нужен, чтобы получить
ответ на вопрос «легли ли данные секции в память MCU и потребляет ли чип
data-пакеты».

## 1. Из чего собрано

| | |
|---|---|
| source | `/home/l/t1100-ubuntu-build/src-nonwifi` — **то же дерево, что дало p29** (его `Image` = `out-nonwifi/.../Image`, sha256 `8aeea8a5…` = `Image-gauge-v5`) |
| out | `/home/l/t1100-ubuntu-build/out-wifi` (новый, `out-nonwifi` не изменялся) |
| config | `out-nonwifi/.config` + `configs/t1100-wifi.fragment` + `configs/t1100-wifi-image.fragment` |
| toolchain | `aarch64-linux-gnu-gcc` 15.2.0 (Ubuntu), тот же, что у p29 |
| release | **`6.12.114-wifi1`** (см. §5, почему суффикс) |
| DTB | тот же DTS + узлы CONSYS/Wi-Fi (см. §4) |
| модули | `wmt_drv.ko`, `wlan_drv_gen3.ko`, `mtk_btif_drv.ko` — все против `out-wifi` |
| ramdisk | **байт в байт из p29** (`0cfa596d…`), cmdline из p29 не менялся |

Сборка (build-host):

```sh
# 1) DTB: дописать узлы Wi-Fi в nonwifi-дерево (refs/wifi-dt-nodes-nonwifi.dts)
cat refs/wifi-dt-nodes-nonwifi.dts \
 >> ~/t1100-ubuntu-build/src-nonwifi/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dts
# исходный DTS сохранён как ...dts.pre-wifi.bak

# 2) config
merge_config.sh -m out-wifi/.config <(cp out-nonwifi/.config)   # см. §3
merge_config.sh -m out-wifi/.config configs/t1100-wifi.fragment
merge_config.sh -m out-wifi/.config configs/t1100-wifi-image.fragment
make -C src-nonwifi O=out-wifi ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# 3) ядро
make -C src-nonwifi O=out-wifi ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j12 \
     Image Image.gz modules mediatek/mt6771-fplus-t1100.dtb

# 4) вендорские модули (серия из patches/wifi/, см. README там же)
#    wmt_drv/wlan_drv_gen3 — M=/home/l/t1100-wifi-m82/work/{common,wlan},
#    mtk_btif_drv — scripts/build-btif-remote.sh KERNEL_OUT=out-wifi
#    все три: LOCALVERSION=-wifi1 (или из include/config/kernel.release)

# 5) boot.img
scripts/repack_boot.py --ref build/gauge/boot_gauge_v5.img \
  --kernel build/wifi-image/Image.gz \
  --ramdisk /tmp/.../ramdisk            # извлечён из p29, sha 0cfa596d…
  --dtb build/wifi-image/mt6771-fplus-t1100.dtb \
  --out build/wifi-image/boot_wifi.img --size 33554432
```

## 2. Артефакты (`build/wifi-image/`)

| файл | размер | sha256 | md5 |
|---|---|---|---|
| `boot_wifi.img` | 33 554 432 | `b52feb4ceacb1707bc124e0adc3e5bca154402d2a1c850b40e168770b8cf6caa` | `ae94ab58339d35aceb7999ebca3ed174` |
| `Image` | 42 162 688 | `b5af36146111b9cc97c919bcc5c7fbe38b53cc5fa1cac372b3c07849182ae907` | |
| `Image.gz` | 15 596 397 | `30e296e5228ee9f1dad8f02a634400e15cfb06e6c9bde2bb37748c81b53d775b` | |
| `mt6771-fplus-t1100.dtb` | 59 247 | `8362894fdc4232e4e0b2bdc30cf7f8f40e9720a72e4eccbf4d35cff17d886e63` | |
| `modules/wmt_drv.ko` | 1 167 520 | `56e4a663050ce2af324eb93156eb6925a437b2ae6595b8478675aacb373eec91` | |
| `modules/wlan_drv_gen3.ko` | 2 946 816 | `f3ba65366374facc46f16a3e0e9e9528096c1864780116575089532806cd339d` | |
| `modules/mtk_btif_drv.ko` | 187 792 | `92d4740c9dae1129b89e884a05815b8af5f616bdbdb80a696755958114bec391` | |

Проверено: `bootimg_extract.py` вынимает из `boot_wifi.img` ровно эти
`Image.gz`, `dtb` и ramdisk; заголовок образа (kernel `@0x40080000`, ramdisk
`@0x55000000`, tags `0x54000000`, page 2048, cmdline) совпадает с p29;
`text_offset=0`, `image_size=0x2900000` — как у `Image-gauge-v5`.

**Vermagic:** все три модуля — `6.12.114-wifi1 SMP preempt mod_unload aarch64`,
`include/config/kernel.release` = `6.12.114-wifi1`, баннер Image —
`Linux version 6.12.114-wifi1`. Зависимости: `wlan_drv_gen3 → wmt_drv →
mtk_btif_drv`. `CONFIG_MODULE_SIG*` в конфиге нет (подписи не проверяются).

## 3. Diff конфига (`build/wifi-image/config-wifi.diff`)

Относительно `out-nonwifi/.config` (p29) — только это:

```
-CONFIG_LOCALVERSION=""
+CONFIG_LOCALVERSION="-wifi1"
+CONFIG_COMPAT_NETLINK_MESSAGES=y
+CONFIG_WIRELESS_EXT=y
+CONFIG_WEXT_CORE=y
+CONFIG_WEXT_PROC=y
+CONFIG_WEXT_SPY=y
+CONFIG_WEXT_PRIV=y
-# CONFIG_NL80211_TESTMODE is not set
+CONFIG_NL80211_TESTMODE=y
-# CONFIG_CFG80211_WEXT is not set
+CONFIG_CFG80211_WEXT=y
+CONFIG_CFG80211_WEXT_EXPORT=y
+CONFIG_LIB80211=m (+CRYPT_WEP/CCMP/TKIP, не устанавливаются)
-# CONFIG_IPW2200 is not set
+CONFIG_IPW2200=m (+LIBIPW=m; нужны только чтобы включить скрытые WEXT_* и
+                WIRELESS_EXT, в rootfs не кладутся и не загружаются)
```

Почему так, а не «просто `configs/t1100-wifi.fragment`»: тот фрагмент ставит
`CFG80211=m`/`MAC80211=m`, а в образе p29 они **built-in**, и USB-драйверы
донглов (`MT7601U`, `RTL8XXXU`, `ATH9K_HTC`) зависят от них как `=y`. Если
взять фрагмент как есть, `olddefconfig` молча понизит донглы до модулей — а на
p54 нет дерева модулей, USB Wi-Fi бы отвалился. Поэтому
`configs/t1100-wifi-image.fragment` фиксирует `CFG80211=y`, `MAC80211=y`
после базового фрагмента. Проверено: `CONFIG_MT7601U=y`, `RTL8XXXU=y`,
`ATH9K_HTC=y`, `RFKILL=y`, `WLAN=y` — как в p29.

## 4. DTB: **менять пришлось** (это единственное расхождение с «DTB не менять»)

DTB из p29 (`4f01d337…` = `dtb-gauge-v3` = `out-nonwifi/.../dtb`) **не содержит
узлов CONSYS/Wi-Fi**: дерево `src-nonwifi` — снимок до патчей 0049/0056
(`grep -c "mediatek,wifi" ...dts` = 0). Без них `wmt_drv`/`wlan_drv_gen3` не к
чему биндиться, поэтому узлы добавлены (`refs/wifi-dt-nodes-nonwifi.dts`,
эквивалент 0049+0056 с `status = "okay"`).

Проверено сравнением декомпилированных DTB: отличий от p29 ровно на
добавленный блок и три `phandle` (vcn18/vcn28/vcn33):

```
+ consys-reserve-memory (2 MiB, no-map, alloc-ranges 0x40000000+0x80000000)
+ consys@18070000  (reg/irq/memory-region/vcn*-supply, status okay)
+ wifi@180f0000    (reg/irq/clocks "wifi-dma"/hardware-values, status okay)
+ phandle = <0xa2/0xa3/0xa4> у mt6358 ldo_vcn18/vcn28/vcn33
```

Остальное (дисплей/панель/тач/регуляторы/OPP/thermal/ramoops) — побайтово как в
p29: `diff` декомпилированных версий не показывает других изменений. LK-совместимость
сохранена: `/mtk-lk-sink` и `compatible = "mediatek,scp"` на месте (50 вхождений),
`reserved-memory` без статических детей.

## 5. Почему release `6.12.114-wifi1`, а не `6.12.114`

`CONFIG_WIRELESS_EXT` меняет layout `struct net_device`, `NL80211_TESTMODE` —
`struct cfg80211_ops`. С одинаковым `uname -r` (=`6.12.114`) старый модуль,
собранный до этих опций, **прошёл бы vermagic-проверку и молча испортил
память** (ровно класс ошибок §29 журнала). Суффикс делает невозможным
случайную загрузку «чужих» .ko и сразу виден в `uname -r`, pstore и
`/lib/modules/`.

## 6. План установки (не выполнялся)

Всё — только после отдельного согласования владельца; физического recovery нет.

### 6.1 Подготовка (с хоста, при загруженной p29/Aurora по SSH)

```sh
# на планшете (root): сохранить текущий p29 ещё раз и сверить
ssh root@<ip> 'dd if=/dev/block/mmcblk0p29 of=/tmp/p29_backup.img bs=1M; sha256sum /tmp/p29_backup.img'
# ожидаем 2d1177c6d5c6e71b7cc4bf61bc79aec48d76730cee294d10c56414ee41a17861
```

Копия p29 на всякий случай есть и здесь: `build/gauge/boot_gauge_v5.img`
(sha256 `2d1177c6…`, md5 `e8fe1896…`).

### 6.2 Прошивка через recovery (USB, `tools/host/recovery.py`)

```sh
# 1) планшет в recovery (vol+ + power), USB к хосту, меню: пункт 3
tools/host/recovery.py put build/wifi-image/boot_wifi.img /tmp/boot_wifi.img
tools/host/recovery.py sh 'sha256sum /tmp/boot_wifi.img'
#    ожидаем b52feb4ceacb1707bc124e0adc3e5bca154402d2a1c850b40e168770b8cf6caa

# 2) бэкап p29 внутри recovery (если не сделан в 6.1)
tools/host/recovery.py sh 'dd if=/dev/block/mmcblk0p29 of=/tmp/p29.img bs=1M; sync; sha256sum /tmp/p29.img'

# 3) прошивка
tools/host/recovery.py sh 'dd if=/tmp/boot_wifi.img of=/dev/block/mmcblk0p29 bs=1M conv=fsync; sync; sha256sum /dev/block/mmcblk0p29'
#    sha256 раздела должен совпасть с sha256 файла (b52feb4c…)

# 4) перезагрузка
tools/host/recovery.py reboot
```

Откат — тот же путь с `build/gauge/boot_gauge_v5.img` (sha256 `2d1177c6…`)
либо с `dd`-дампа `/tmp/p29.img`, снятого в п.2.

### 6.3 Модули (после загрузки нового ядра, по SSH)

```sh
REL=$(ssh root@<ip> uname -r)      # ожидаем 6.12.114-wifi1
ssh root@<ip> "mkdir -p /lib/modules/$REL/updates/wifi"
scp build/wifi-image/modules/*.ko root@<ip>:/lib/modules/$REL/updates/wifi/
ssh root@<ip> 'depmod -a $(uname -r)'
# порядок загрузки (wlan зависит от wmt, wmt от btif):
ssh root@<ip> 'modprobe mtk_btif_drv; modprobe wmt_drv; modprobe wlan_drv_gen3 t1100_probe=1'
# (точные module_param'ы прогона M81 — в docs/wifi-port-log.md §82.6)
```

Проверка, что загрузилось именно новое ядро и узлы на месте:

```sh
uname -r                                   # 6.12.114-wifi1
ls /proc/device-tree/ | grep -E 'consys|wifi'
dmesg | grep -E 'Linux version|mt6358-gauge|consys|wmt|wlan' | head -30
```

## 7. Что НЕ изменилось (gauge v5 сохранён)

- исходник и конфиг — из того же дерева/конфига, что p29 (gauge v5):
  `CONFIG_MT6358_GAUGE=y`, в Image есть `mediatek,mt6358-gauge`;
- ramdisk и cmdline — побайтово из p29;
- DTB-часть про дисплей/тач/регуляторы — побайтово как в p29 (см. §4);
- `boot_gauge_v5.img` и `p29` не изменялись (только читались).

## 8. Риски

1. **Нет физического recovery.** Если образ не загрузится (LK/ядро), вернуть
   p29 можно только через recovery-раздел по USB — он есть на устройстве
   (p50), но если планшет уйдёт в цикл preloader, нужен USB-хост с
   `recovery.py` и рабочий кабель. Решение о прошивке — за владельцем.
2. **DTB изменён** (§4). Риск для LK низкий (структура та же, узлы добавлены в
   конец, `__symbols__`/`mtk-lk-sink` на месте), но это первый образ с этими
   узлами на *этом* дереве; проверять по pstore/`/proc/device-tree`.
3. **WEXT меняет ABI ядра.** Любые сторонние .ko, собранные под прежний
   `6.12.114`, нельзя грузить в `6.12.114-wifi1` (vermagic не совпадёт —
   специально). В rootfs p54 сторонних .ko нет.
4. **`ipw2200.ko`/`lib80211.ko` собираются, но не устанавливаются**: они нужны
   только как «переключатели» скрытых WEXT-символов. Если случайно положить их
   в `/lib/modules` — ничего не сломают (не загружаются).
5. **Wi-Fi всё ещё не работает**: образ лишь позволяет выполнить прогон M81
   (`ACCESS_REG`-чтение памяти MCU, `WHISR/WTQCR`, vendor-`WIFI_START`). Даже
   при удачном прогоне `wlan0` в этом образе может не появиться.
6. **Питание/зарядка**: код gauge/charger не менялся, но любое новое ядро —
   это новый бинарник; первый прогон делать с контролем `capacity`/`status`
   (в p29 было 56–59 % стабильно).
7. **Место на build-хосте**: свободно ~1.2 ГБ; `out-wifi` (1.6 ГБ) и
   `t1100-wifi-m82` остаются, при следующей сборке это надо учитывать.

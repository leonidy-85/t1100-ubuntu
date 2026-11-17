# Как собрать ядро «как на прошивке»: серия патчей, DTB из образа

Обновлено: 18.11.2026. Это запись того, как 18.11 собиралось ядро для
проверки `CONFIG_INPUT_UINPUT` и panfrost-патчей 0075/0076, и какие грабли при
этом вылезли. Пригодится для задачи «воспроизводимая сборка» (`docs/TASKS.md`,
п. 5).

## 1. Проблема: дерево отстаёт от серии

`../linux-t1100` — git-дерево «база linux 6.12.114 + наши коммиты». На 18.11 в
нём **52 коммита** (последний — 13.11, Type-C PD), а `patches/series` содержит
**75** записей (по 0078). То есть 25 патчей (0053…0078: батарея/гейдж, IMU,
ALS/PS, аудио-машина, cpufreq MT6771, CPU-OPP, Type-C, panfrost 0075/0076, HDMI)
живут **только в `patches/`**.

Прошитое на планшете ядро (`6.12.114-wifi1`, сборка 15.11) собрано из дерева
**с** этими патчами — это видно по `/proc/config.gz`: в нём есть
`CONFIG_MT6358_GAUGE`, `CONFIG_SND_SOC_MT6771_MT6358`, `CONFIG_INV_ICM42607`,
которых в текущем `../linux-t1100` нет. Сборка из текущего дерева молча теряет
эти драйверы (`olddefconfig` выкидывает неизвестные символы).

## 2. Что делать (скрипт)

```sh
git -C ../linux-t1100 worktree add ../linux-t1100-b78 69d96978a
scripts/apply-series.sh ../linux-t1100-b78 --from 0053    # --dry-run для проверки
```

Скрипт накатывает `patches/series` через `git apply`, при конфликте в DTS
пробует ещё раз с `--exclude='arch/arm64/boot/dts/*'` (DTS нам не нужен — DTB
берём из прошивки, см. §4).

Применяется 20 из 22 патчей диапазона. Два конфликтуют с базой 13.11:

| патч | что | как разрешено |
|---|---|---|
| `0060-phy-mediatek-tphy-software-role-switch` | tphy: программный role switch MT6771 | `patch -p1 -F3`, затем руками: в блок `U3P_U2PHYDTM1` добавлены `P2C_FORCE_IDPULLUP` (BIT 8), `P2C_RG_BVALID` (3), `P2C_RG_IDPULLUP` (0) — остальные define'ы в дереве уже были |
| `0074-drm-panel-it6112-recover-the-bridge-after-the-dsi-st` | it6112: восстановление моста после остановки DSI | `patch -p1 -F3`, затем руками: поля `rails_on`/`bridge_owned`/`enabled_once` оказались **после** `};` структуры `it6112_ctx` — перенесены внутрь |

**Без 0060 планшет грузится, но USB-гаджет не поднимается** (проверено:
`usb0` есть, `role = device`, а хост не видит устройство; после применения 0060
USB вернулся). Это цена «пропустить патч, потому что он про USB».

## 3. Сборка

```sh
# конфиг прошитого ядра + нужные правки
ssh root@<ip> 'zcat /proc/config.gz' > /tmp/device.config
sed -i 's/^# CONFIG_INPUT_UINPUT is not set/CONFIG_INPUT_UINPUT=y/' /tmp/device.config

# на build-хосте
rsync -a --exclude=.git ../linux-t1100-b78/ l@172.17.141.172:/home/l/t1100-ubuntu-build/src-b78/
cd /home/l/t1100-ubuntu-build && mkdir -p out-b78 && cp /tmp/device.config out-b78/.config
make -C src-b78 O=$PWD/out-b78 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
# проверка: кроме UINPUT отличий от конфига прошивки быть не должно
make -C src-b78 O=$PWD/out-b78 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j12 Image Image.gz
```

`CONFIG_LOCALVERSION="-wifi1"` сохраняется — иначе вендорские модули Wi-Fi
(`wlan_drv_gen3.ko` и др.) не загрузятся: `CONFIG_MODVERSIONS` и `MODULE_SIG`
в конфиге выключены, но vermagic сверяется по строке релиза.

## 4. Перепаковка boot и прошивка

DTB **не пересобираем**: в прошитом образе он содержит узлы, которых нет в
собранном из дерева (gauge/IMU/ALS/CPU-OPP — они пришли из DTS-патчей, а DTS в
этой сборке пропущены). Берём DTB и ramdisk из текущего образа:

```sh
python3 scripts/bootimg_extract.py --image build/boot_wifi1_working.img --outdir /tmp/old
python3 scripts/repack_boot.py --ref build/boot_wifi1_working.img \
    --kernel build/kernel-b78/Image.gz --dtb /tmp/old/dtb \
    --out build/boot_b78_uinput.img --size 33554432
T1100_HOST=<ip> tools/host/flash-ssh.sh build/boot_b78_uinput.img /dev/mmcblk0p29 --reboot
```

Проверить перед прошивкой: `bootimg_extract.py` из нового образа даёт **тот же**
ramdisk и kernel = наш `Image.gz`, а `md5sum` прочитанной обратно p29 совпадает.

Бэкап (обязателен): `dd if=/dev/mmcblk0p29 of=/root/boot_a_prev_wifi1.img`
(в этой сессии — sha256 `69a4616a…`, тот же образ лежит локально в
`build/boot_wifi1_working.img`). Откат — тем же `flash-ssh.sh`.

## 5. Результат 18.11

| | |
|---|---|
| kernel | `6.12.114-wifi1` (серия 0053–0078 + UINPUT) |
| `Image.gz` | 15 600 445 Б, sha256 `bc8b2a58…f79296c` |
| boot | `build/boot_b78b_uinput.img`, md5 `cab7f422…`, p29 прочитан обратно |
| проверено | USB-RNDIS + SSH (usb0), Wi-Fi (модули загрузились), `/dev/uinput`, тач/панель |
| не проверено | suspend/resume, DPMS-цикл панели (0074 теперь в ядре) |

## 6. Что осталось по процессу

- Дерево `../linux-t1100` стоит догнать до 0078 (или до 0073) коммитами из
  серии — иначе `scripts/build-kernel-remote.sh` по умолчанию собирает ядро без
  батареи/IMU/аудио/cpufreq.
- Патчи 0060 и 0074 стоит перегенерировать в репозитории, чтобы `apply-series.sh`
  проходил без ручных правок.

# Waydroid на Fplus T1100 (ALT Mobile + Phosh)

Состояние: **подготовка ядра и образов**, запуск ещё не подтверждён.
Устройство переведено на ALT Mobile Sisyphus (см. `docs/alt-mobile.md`),
оболочка — Phosh 0.58, GPU — Panfrost (Mali-G72 MC3).

## Что требует Waydroid от ядра

| Опция | Тип | Зачем |
|---|---|---|
| `CONFIG_ANDROID_BINDER_IPC` | bool | binder, основной IPC Android |
| `CONFIG_ANDROID_BINDERFS` | bool | `/dev/binderfs` и создание `/dev/binder*` |
| `CONFIG_ANDROID_BINDER_DEVICES=""` | строка | не создавать статические binder-узлы |
| `CONFIG_PSI` | bool | pressure stall information для `lmkd` |
| `CONFIG_INPUT_UINPUT` | bool/tristate | виртуальный ввод |
| `CONFIG_UHID` | tristate | HID-устройства внутри контейнера |
| `CONFIG_NF_TABLES` | tristate | сеть Waydroid (`waydroid-net.sh`, nftables) |
| `CONFIG_NF_TABLES_INET` | bool | таблицы inet |
| `CONFIG_NF_TABLES_NETDEV` | bool | netdev-таблицы |
| `CONFIG_NFT_NAT`, `CONFIG_NFT_MASQ` | tristate | NAT/masquerade для `waydroid0` |

`CONFIG_ASHMEM` не нужен: в mainline он удалён с 5.18, современный Waydroid
использует binder + dma-buf. `CONFIG_DMA_SHARED_BUFFER`, `CONFIG_SYNC_FILE`,
`CONFIG_OVERLAY_FS`, namespaces и cgroups на T1100 уже есть.

Binderfs и PSI — **bool**, поэтому требуют нового `Image`; `UHID` и nftables
можно ставить модулями. В репозитории опции добавлены в
`configs/t1100_defconfig` и `configs/t1100.fragment`.

## Сборка ядра

Сборка на локальном 8-ядерном ПК (build-хост `172.17.141.172` недоступен):

```sh
cd /home/leo/t1100-build/linux-6.12.114
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j8 Image.gz dtbs modules
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=/home/leo/t1100-build/modstage-waydroid modules_install
```

Проверить в `.config`:

```text
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ANDROID_BINDER_DEVICES=""
CONFIG_PSI=y
CONFIG_INPUT_UINPUT=y
CONFIG_UHID=m
CONFIG_NF_TABLES=m
CONFIG_NFT_NAT=m
CONFIG_NFT_MASQ=m
```

## Перепаковка и прошивка p29

Текущий p29 — `build/boot_pa.img` (md5 `d7c12647f9ca68dc2e37e31d5cba0f30`).
Перед прошивкой сохранить его как `build/recovery/boot_a_pre_waydroid.img`.

```sh
python3 scripts/repack_boot.py \
  --ref build/boot_pa.img \
  --kernel /home/leo/t1100-build/linux-6.12.114/arch/arm64/boot/Image.gz \
  --ramdisk build/waydroid/boot_pa_x/ramdisk \
  --dtb build/waydroid/boot_pa_x/dtb \
  --size 33554432 --out build/waydroid/boot_waydroid.img

T1100_HOST=10.42.66.66 tools/host/flash-ssh.sh \
  build/waydroid/boot_waydroid.img /dev/mmcblk0p29 --reboot
```

Откат: `build/scp/boot_vcodec2.img` (md5 `bc48aedf5cee38cab0c8fb11cdd11e5a`)
или `build/recovery/boot_a_heaps_2026-11-20.img` (md5 `6bc3c35e…`).
Прошивать только при доступном SSH/recovery и после проверки md5.

## Модули nftables/uhid

Из staging-каталога скопировать на планшет:

```sh
modstage=/home/leo/t1100-build/modstage-waydroid/lib/modules/6.12.114-wifi1
scp -r "$modstage/kernel/net/netfilter" \
       "$modstage/kernel/net/ipv4/netfilter" \
       "$modstage/kernel/net/ipv6/netfilter" \
       "$modstage/kernel/net/bridge/netfilter" \
       root@10.42.66.66:/lib/modules/6.12.114-wifi1/kernel/net/
scp "$modstage/kernel/drivers/hid/uhid.ko" \
    root@10.42.66.66:/lib/modules/6.12.114-wifi1/kernel/drivers/hid/
ssh root@10.42.66.66 depmod -a 6.12.114-wifi1
```

После загрузки проверить:

```sh
ls -l /dev/binderfs /dev/binder /dev/uinput
nft list ruleset
zcat /proc/config.gz | grep -E 'BINDER|PSI|NF_TABLES|UINPUT|UHID'
```

## Образы Waydroid

Локальные образы (в git не коммитятся, `build/` в `.gitignore`):

- `build/waydroid-images/system.zip` — 871M, sha256 `5fb8179e…` (system.img ~1.99 ГБ);
- `build/waydroid-images/vendor-mainline.zip` — 141M, sha256 `20a49c11…` (MAINLINE vendor для arm64);
- `build/waydroid-images/vendor.zip` — 40M, HALIUM_13 (не использовать для arm64 MAINLINE).

На планшете:

```sh
mkdir -p /usr/share/waydroid-extra/images
cd /usr/share/waydroid-extra/images
unzip -o /root/waydroid-zip/system.zip
unzip -o /root/waydroid-zip/vendor-mainline.zip
waydroid init -i /usr/share/waydroid-extra/images
systemctl enable --now waydroid-container
waydroid session start
waydroid show-full-ui
```

`waydroid init` без сети нормально работает с уже распакованными
`system.img`/`vendor.img`; если он всё же обращается к OTA, нужен HTTP-сервер
с JSON (`build/waydroid-ota`) и reverse-туннель на `127.0.0.1:8000`.

## Проверка

```sh
waydroid status
ip -br addr show waydroid0      # 192.168.240.1/24
nft list ruleset | head
ps aux | grep -E 'waydroid|binder'
```

Ожидаемо: `Session: RUNNING`, `Container: RUNNING`, интерфейс `waydroid0`,
Android-окно в Phosh. GPU используется через host Panfrost/Mesa; аппаратный
H.264-декод внутри Waydroid не гарантирован (vendor-путь на паузе).

## Ограничения

- Тач T1100 в mainline не готов — для Android-окна нужен USB-ввод.
- RAM 3.4 ГБ, Android-контейнеру может не хватить; следить за zram/swap.
- Binderfs/PSI нельзя включить модулями — только новым ядром.
- nftables обязателен для штатного `waydroid-net.sh`; iptables — только fallback.

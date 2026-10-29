# provenance — версии, хеши и воспроизводимость

Обновлено: 29.10.2026. Всё ниже проверено на хосте
`/home/leo/Aurora_All/device` (Linux, 20 логических CPU, 79 ГБ свободно).

## Источники

| Что | Версия / значение | sha256 |
|---|---|---|
| Ядро | `linux-6.12.114.tar.xz` (cdn.kernel.org) | `7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3` |
| Тулчейн | Arm GNU Toolchain **14.2.Rel1** (`aarch64-none-linux-gnu-`, gcc 14.2.1) | тарбол 152 227 388 B, `xz -t` OK |
| `dtc` | 1.7.2 (системный) | — |
| Хост-пакеты | `make`, `gcc`, `bc`, `flex`, `bison`, `libssl-dev`, `python3` | — |
| busybox (initramfs) | `busybox-static` 1.37.0-7ubuntu1, arm64, из ports.ubuntu.com | 1 981 032 B (бинарник) |

`sudo` на хосте требует пароль, поэтому тулчейн распакован в
`../toolchains/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/`,
а не установлен в `/usr`. `scripts/build_kernel.sh` находит его сам.

## Дерево ядра

- Путь: `/home/leo/Aurora_All/device/linux-t1100` (вне репозитория проекта).
- База: коммит `1eca0a8` = «linux 6.12.114 (kernel.org tarball)».
- Патчи (`patches/series`, применяются `git am`):

| Патч | sha256 | Строк |
|---|---|---|
| 0001 SoC dtsi | `719e84a60829ce70…a52e9f` | 300 |
| 0002 board DTS | `30772f1b58f6356e…8b94951d` | 75 |
| 0003 PSCI + WDT, bootargs | `9bcb97c46bd7338d…35e7475a2` | — |

Регресс: на **чистом** дереве 6.12.114 `git am` всех трёх патчей проходит без
конфликтов и даёт тот же DTB:

```
build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
4941 B  sha256 66f4446d05e4e06caa530554f48dad2e5931ec68e434eb1be6044e9b906aaf49
```

(Исторический DTB без патча 0003 — 4806 B, `bbf097af…d8b5e`; он больше не
актуален.)

## Сборка

Команда:

```sh
cd t1100-ubuntu && scripts/build_kernel.sh
```

Что делает: `defconfig` → `merge_config.sh` с `configs/t1100.fragment` →
`olddefconfig` → `make -j$(nproc) Image dtbs modules_prepare`, out-of-tree в
`build/t1100`, лог в `build/logs/`.

| Артефакт | Размер | sha256 |
|---|---|---|
| `Image` | 38 531 584 B | `b4d289a062df393e7ee55c2e770d84e46a87437b57f876a4e38875a1281d58ac` |
| `mt6771-fplus-t1100.dtb` | 4941 B | `66f4446d05e4e06caa530554f48dad2e5931ec68e434eb1be6044e9b906aaf49` |
| `.config` | — | `741a7158d0a24992b390df9b1a1f3a76b5af8065cd1b21ff0ef5717bfad00fa2` |
| DTB всего | 1192 (mediatek 84) | список: `build/logs/build-20261029-084802.dtbs.sha256` |
| warnings | **0** | `build/logs/build-20261029-084802.log` |

Ключевые опции `.config`: `CONFIG_PSTORE{,_RAM,_CONSOLE,_PMSG}=y`,
`CONFIG_MEDIATEK_WATCHDOG=y`, `CONFIG_ARM_PSCI_FW=y`,
`CONFIG_ARM64_VA_BITS=39`, `CONFIG_DEBUG_INFO_NONE=y`, `CONFIG_PANIC_TIMEOUT=10`.

## Тестовый `boot_a`

Команда:

```sh
scripts/make_test_boot.sh --dtb build/t1100/arch/arm64/boot/dts/mediatek/mt6771-fplus-t1100.dtb
```

| Компонент | Размер |
|---|---|
| `Image.gz` | 13 986 402 B |
| initramfs (`build/initramfs.cpio.gz`) | 1 031 517 B, sha256 `2b38977d62ad2b789df0014f32f596b101bc3fe8b577371b6e1f397a9d05c4e9` |
| DTB (в MTK-контейнере) | 4941 B (wrapped 5005 B) |
| **`build/boot_a_test.img`** | **33 554 432 B (32 МиБ)**, sha256 `6d0250d67da345f1a24393eab9c3d4cf515038f82c61588ae1ca2b95cb589e47` |

Заголовок/адреса — от **снятого с платы** стокового `boot_a`
(`build/backup/boot_a_stock_2026.img`, sha256
`9601bcd6556a56ae1bd6367764a2bc2ea80dbb6a6f497ff0ce4e4415501b864f`,
ядро 4.14.186 от 2025-07-24); cmdline:
`bootopt=64S3,32N2,64N2 maxcpus=1 panic=10 pstore.backend=ramoops`.

Локальный `../1100/boot_a.bin` (`92875f51…492c`) — **более старая** сборка
(ядро 2025-05-06), как шаблон заголовка больше не используется. Round-trip
перепаковки проверен на обоих образах: результат побайтово равен всем 32 МиБ.

**На устройство образ не прошивался.** Прошивка — только с подтверждением
владельца (`docs/boot-test.md`).

### Доступ к плате (проверено 29.10.2026)

- Recovery по USB: интерфейс RNDIS `10.42.66.67/32`, планшет `10.42.66.66`,
  `telnet 10.42.66.66:23` → Aurora Recovery v2.0.
- Root-shell: пункт `3`, затем `y` **без перевода строки**, затем код
  блокировки `12345` (см. `scripts/t1100_root.sh`/`rec.py`); иначе пустая
  строка уходит как код и получается «Wrong code».
- `/dev/block` отсутствует; раздел — `/dev/mmcblk0p29` (65536 секторов = 32 МиБ).
- `/sys/fs/pstore` в recovery есть и пуст — лог нашей загрузки можно прочитать,
  загрузившись в recovery (ramoops в RAM не обнуляется).

## Референсы

| Файл | sha256 |
|---|---|
| `refs/stock-mt6771.dts` | `a8b5666dd38a849619432f7d5e9327a2c5588f5d097c1f944d34ac47b23acc0c` |
| `refs/it6112/panel-it6112-boe-tv110xum-lb2.c` | `4d4dd33aaca71bba6532d0f56f60e15f9dbc1ab5fad745f895d4cbbd7fe91fef` |
| `refs/mt6771-next/mt6771.dtsi` | `231d99bcf57653566542f7a74abd3c42c8729423148e3e1115869d57f98542e6` |
| `refs/mt6771-next/mt8788-fplus-t1100.dts` | `acee7f99d6b43f4765ca667a5e42544e6b2dffae6f2527af9a8cefbbfd871152` |

## Что НЕ воспроизводится на этом хосте

- Чтение pstore с платы: `scripts/t1100_root.sh` работает через
  `devel-su`-сессию, но для входа по SSH нужен ключ/пароль `defaultuser`,
  которого на этом хосте нет (`Permission denied (publickey,password)`).
  Плата в сети: `172.17.141.62:22`, `SSH-2.0-OpenSSH_8.0`.
- `Image`/DTB/`.config` лежат в `build/` (в `.gitignore`), в репозитории —
  только хеши выше.

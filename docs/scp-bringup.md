# SCP на MT6771: загрузка mainline-прошивки MT8183

Дата: 20.11.2026. Статус: **GO** — SCP-ядро загружается, remoteproc в
состоянии `running`, IRQ приходит. Это ещё не аппаратный декод, но главный
блокер декодера снят: mainline `mtk_scp` умеет поднимать SCP на MT6771.

## Зачем это нужно

Mainline-драйвер `mtk-vcodec` для декодера требует не VPU, а SCP с сервисом
`AP_IPIMSG_DEC_*`. Стоковая прошивка MT6771 (`scp_a`, p21) — контейнер
`tinysys-loader-CM4_A`, не ELF, и mainline `mtk_scp` её не грузит. В
linux-firmware есть ELF-прошивка `mediatek/mt8183/scp.img`; в ней есть строки
`VDEC_SERVICE`, `h264`, `vp9`. Блоки SCP и VDEC у MT6771 совпадают с MT8183 по
базе и IRQ, поэтому был шанс загрузить именно её.

## Что совпало

| Блок | MT6771 (стоковый DTS) | MT8183 (mainline) |
|---|---|---|
| SCP | `0x10500000`, SRAM `0x80000`, cfg `0x105c0000+0x19080`, IRQ **174** | то же |
| VDEC | `0x16020000`, PP `0x16025000`, IRQ **250** | то же |
| Прошивка | контейнер `tinysys`, не ELF | ELF32, `.ipi_buffer` `0x7bdb0`, DRAM `0x50000000` |

## Что сделано

### DTB

В собранный DTB добавлены два узла (скрипт
`scripts/dtb-add-scp.py`, он же воспроизводит результат из любого boot.img):

```
reserved-memory {
    memory@50000000 {
        compatible = "shared-dma-pool";
        reg = <0 0x50000000 0 0x2900000>;   /* 41 MiB */
        no-map;
    };
};

scp@10500000 {
    compatible = "mediatek,mt8183-scp";
    reg = <0 0x10500000 0 0x80000>, <0 0x105c0000 0 0x19080>;
    reg-names = "sram", "cfg";
    interrupts = <GIC_SPI 174 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&infracfg CLK_INFRA_SCPSYS>;
    clock-names = "main";
    memory-region = <&scp_mem_reserved>;
    firmware-name = "mediatek/mt8183/scp.img";
    status = "okay";
};
```

Регион обязателен: DRAM-сегмент прошивки имеет `p_paddr = 0x50000000`, а
`mt8183_scp_da_to_va()` считает адрес как `da - dma_addr`. Размер 41 MiB взят
из кукуи-платы (`0x2900000`), драйверу нужно минимум `0x500000`.

### Модули

На планшете не были установлены модули remoteproc. Скопированы из
`/root/kbuild/linux-6.12.114` (vermagic `6.12.114-wifi1`):

- `drivers/remoteproc/mtk_scp.ko`
- `drivers/remoteproc/mtk_scp_ipi.ko`
- `drivers/rpmsg/mtk_rpmsg.ko` — без него `mtk_scp` не загружается
  (`Unknown symbol mtk_rpmsg_create_rproc_subdev`).

`depmod -a 6.12.114-wifi1`, автозагрузка — `/etc/modules-load.d/scp.conf` с
`mtk_scp`.

### Прошивка

`/lib/firmware/mediatek/mt8183/scp.img`, 1 030 776 Б, sha256
`401e9c027b0e105efa9eb9b31683924a8d5f5ab3b1654f0915b174effe2df33d`.
На планшете уже лежал `scp.img.zst`, он распаковывается в тот же файл.

## Проверка

```
mtk-scp 10500000.scp: assigned reserved memory node memory@50000000
remoteproc remoteproc0: powering up scp
remoteproc remoteproc0: Booting fw image mediatek/mt8183/scp.img, size 1030776
mtk-scp 10500000.scp: IPI buf addr 0x0007bdb0
mtk-scp 10500000.scp: SCP is ready. FW version kukui_scp_v2.0.13324-280b9fce97
remoteproc remoteproc0: remote processor scp is now up
```

`/sys/class/remoteproc/remoteproc0/state` → `running`; в `/proc/interrupts`
строка `MT_SYSIRQ 174 Level 10500000.scp` с ненулевым счётчиком.

## Грабли: IRQ 0x174 вместо 0xae

Первая сборка DTB содержала `interrupts = <0 0x174 4>`, то есть hwirq
**372**, а не 174. SCP при этом стартовал и поднимал `TO_HOST` bit0, но
прерывание не приходило, драйвер ждал 2 секунды и падал с `-62` (ETIME), а
SCP уходил в watchdog. В `/proc/interrupts` была видна строка с IRQ 372 и
счётчиком 0.

Правильное значение — `0xae` (174), как в стоковом DTS:
`interrupts = <0x00 0xae 0x04>`. После замены SCP загрузился с первой
попытки.

## Ограничения

- Раз в секунду в dmesg: `No handler for ipi id = 13` — это канал
  `cros-ec-rpmsg` (addr 0xd), cros-ec драйвера у нас нет. На работу не влияет.
- `vcodec_dec` в DTB пока не возвращён; IOMMU выключен. Это следующий этап.
- Исходный board DTS всё ещё удаляет `&scp`; пока используется бинарный патч
  DTB. Патч исходника — после того как появится сборка под рукой.

## Воспроизведение

```sh
# 1. Достать DTB из текущего boot.img
python3 scripts/bootimg_extract.py --image p29.img --outdir p29x

# 2. Добавить узлы SCP
python3 scripts/dtb-add-scp.py --dtb p29x/dtb --out scp.dtb

# 3. Перепаковать и прошить p29 (бэкап обязателен)
python3 scripts/repack_boot.py --ref p29.img --kernel p29x/kernel \
    --ramdisk p29x/ramdisk --dtb scp.dtb --size 33554432 --out boot_scp.img
T1100_HOST=192.168.2.146 tools/host/flash-ssh.sh boot_scp.img /dev/mmcblk0p29 --reboot
```

## Дальше

1. Вернуть `vcodec_dec` (наследуется из `mt8183.dtsi`), включить IOMMU и
   проверить, что `scp_get_vdec_hw_capa()` отвечает.
2. Собрать/установить `mtk-vcodec-dec` и проверить `/dev/video*` через
   `v4l2-ctl --list-formats-out`.
3. Userspace: GStreamer `v4l2codecs` или mpv `--hwdec=v4l2request`.
4. HEVC не цель: mainline HEVC-путь только для LAT (MT8192/8195), у MT6771
   его нет.

# Видео-декод: состояние и развилка (23.11.2026)

## Где мы
Цель — аппаратный H.264 на Fplus T1100 (MT6771) под ALT Linux / mainline 6.12.114-wifi1.

Вендорский AP-side путь (`media.codec` → `libMtkOmxVdecEx.so` → `libvcodecdrv.so`
→ `/dev/Vcodec`) доведён до:
- порт драйвера в `vendor/vcodec/`, IRQ 400 после `unbind` mainline `mtk-vcodec-dec`;
- compat-ioctl: `LOCKHW ret=0`, аллокатор `VCODEC_ALLOC_NON_CACHE_BUFFER`
  через `alloc_pages` (реальные PA), mmap с `pgprot_writecombine` — SIGBUS ушёл;
- ION-шим `tools/ionshim_vc.c` (`libionshim_vc4.so`);
- 32-битные харнессы `omx_decode2_au4` / `omx_decode2_csd` в `/opt/bionic/vendor/bin`.

Блокеры, которые остались:
1. VDEC не забирает битстрим: `Fail to parse Slice header`, IRQ 400 = 0.
2. Вендорский `smi_bus_prepare_enable(SMI_LARB1)` в порту — заглушка; клоки
   `larb@16010000` (apb+smi) теперь включаются (`LARB1 on (clk apb=1 smi=1)`),
   но программирование портов SMI осталось вендорским.
3. HAL нестабилен: в 3 из 4 прогонов SIGSEGV после первого AU (`pc=0`,
   NULL-вызов), в логе `Failed to open ged device`, `Open SMI(/dev/MTK_SMI) failed`,
   `BWC: Failed to switch SMI/EMI profile`.

Вывод: вендорский userspace требует ещё нескольких вендорских подсистем ядра
(SMI-порты, GED, BWC/EMI), каждой нет в mainline.

## Развилка
A. Дописывать вендорский слой: порты LARB1, заглушки GED/BWC, затем HAL.
   Плюс: готовый userspace (OMX). Минус: неизвестно, сколько ещё слоёв.

B. Идти mainline-путём: DT-узел VDEC для `mtk-vcodec-dec` (без SCP) + V4L2
   stateless декодер в userspace (GStreamer `v4l2slh264dec`, mpv `--hwdec=v4l2request`).
   Плюс: SMI/IOMMU/клоки/питание уже в mainline, никакого вендорского HAL.
   Минус: нужен корректный DT-узел и проверка, что VDEC MT6771 работает
   без SCP-прошивки.

## Рекомендация
Сначала B (ограниченный эксперимент: DT-узел + bind + `v4l2-compliance` +
короткий клип). Если VDEC MT6771 без SCP не поднимается — вернуться к A,
но начинать с портов LARB1, а не с HAL.

## Доступы
Планшет: `root@172.17.141.159` (по ключу), пароли 12345; IP плавает.
Build: `l@172.17.141.124` (pass 0), сборка модуля:
`make -C /home/l/t1100-ubuntu-build/src-nonwifi O=/home/l/live-out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M=/tmp/vcodec-b78 KBUILD_MODPOST_WARN=1 modules`

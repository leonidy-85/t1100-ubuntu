# ADR 0004: SCP-путь доказан, vcodec — рабочий трек

**Статус:** accepted (20.11.2026)

## Контекст

ADR 0003 откладывал аппаратный декод, пока не доказан SCP-путь: mainline
`mtk_scp` не поддерживал MT6771, а стоковая `scp_a` — не ELF. 20.11.2026
удалось загрузить на MT6771 прошивку `mediatek/mt8183/scp.img` из
linux-firmware: `remoteproc0` в состоянии `running`, FW
`kukui_scp_v2.0.13324-280b9fce97`, IRQ 174 приходит. В прошивке есть
`VDEC_SERVICE`.

После этого `mtk-vcodec-dec` с `mediatek,mt8183-vcodec-dec` пробуется:
`probe of 16020000.video-codec returned 0`, зарегистрирован `/dev/video0`,
формат **H.264 Parsed Slice Data** (`0x34363253`). Реальный декод кадра ещё
не проверен.

## Решение

1. Продолжаем порт `mtk-vcodec` для H.264/VP8/VP9 stateless.
2. HEVC не цель: mainline HEVC-путь только для LAT (MT8192/8195), у MT6771
   LAT нет; вендорный HEVC — только OMX-блоб.
3. Софт-декод остаётся fallback (720p–1080p H.264 комфортно).
4. Ближайший критерий приёмки: декод одного H.264-кадра через V4L2 request
   API (GStreamer `v4l2codecs`, `v4l2-request-test` или mpv `v4l2request`).
5. `iommus` для VDEC добавляем после того, как userspace-тест покажет, нужны
   ли они (сейчас probe и регистрация формата работают без них).

## Последствия

- `docs/scp-bringup.md` — как поднят SCP и какие грабли (IRQ `0xae`).
- `docs/vcodec-bringup.md` — DTB-узел vcodec, модули, `/dev/video0`, грабли
  `fdtput -x` (`0xfa`/`0xa`).
- `docs/vdec-plan.md` — обновлённый план.
- p29 сейчас содержит `build/scp/boot_vcodec2.img`; откат —
  `build/scp/boot_scp2.img` или `/root/boot_a_before_scp.img`.
- Браузерное ускорение, скорее всего, останется на софт-декоде: Firefox
  умеет VA-API, а не V4L2 stateless.

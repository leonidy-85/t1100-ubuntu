# VDEC: IRQ 400 и polling done-бита (23.11.2026)

Состояние вендорского AP-side пути (`/dev/Vcodec` + 32-битный HAL) после
LARB1 MMU bypass.

## IRQ 400 не приходит, но декодер завершает работу

- `/proc/interrupts`: строка **400** = `MT_SYSIRQ 250 Level Vcodec`,
  **0 прерываний**. Это корректный Linux virq для DT IRQ 250; драйвер
  запрашивает его правильно.
- В момент `WAITISR` регистры:

  ```
  GCON=00000101  MISC28=00000001  MISCa4=00011000
  MISC14=0e88654d  VLD84=fffff000  VLDe8=00000811  VLD2d8=00000000
  ```

  `MISCa4` содержит bit16 (`0x10000`) — декодер завершил операцию. IRQ при
  этом не приходит (нет линии/маски), поэтому HAL ждёт до таймаута.

## workaround: polling done-бита в драйвере

Патч `patches/0082-vcodec-poll-dec-done.patch`:

- `dec_isr()` очищает `MISC+0xa4` маской `0x10011` (добавлен bit16).
- `vcodec_poll_dec_done(timeout_ms)` опрашивает `MISC+0xa4 & 0x10000`
  с `usleep_range(1000, 2000)`, при успехе вызывает `dec_isr()`.
- `vcodec_waitisr_kernel()` вызывает polling перед `eVideoWaitEvent()`;
  при таймауте печатает дамп `GCON/MISC/VLD`.

Результат: `WAITISR ret=0`, HAL продолжает работу:

```
[VCODEC] poll dec done after 1 ms MISCa4=00011000
[VCODEC] compat WAITISR ret=0
```

Модуль: `sha256 df10584253df3ccb4c768970da962a05566f3ed4b15da4eb000559413432dedd`,
на устройстве `/tmp/vcodec_poll.ko`, загрузка `insmod ... hw_power=1`.

## Что с самим декодом

- `parseSliceHeaderHW` иногда возвращает 1, вызывается
  `Vdec_Drv_setDecPicInfo`; но ue-поля slice header нестабильны:
  IDR часто `ue1=0, ue2=13` (slice_type > 9) → `-12`;
  non-IDR `5,0,4` / `2,0,1` → `-16`.
- `/data/out.yuv` остаётся 115200 байт `0x10`
  (md5 `8e4dd5c5c31a54672e30503f6ee13321`) — изображения нет.
- `VLD84=fffff000` может быть error-state, а `MISCa4 bit16` — не только
  done, но и признаком ошибки. Это ещё нужно разделить.

## Опасность: чтение VLD из userspace

Шим v13 читал `VLD 0xe8/0x84/0xf4` до/после `bVDecWaitVldFetchOk` —
плата зависла (bus hang). Шим v32 прочитал `VLD 0x54` через
`H264_HAL_ReadVLD` внутри `WriteVLD(0xc0)` — плата снова зависла
(`ping` 100% loss, SSH timeout). **Чтение VLD-регистров из userspace на
этом стенде небезопасно**; для диагностики использовать только чтения,
которые делает сама библиотека, либо дамп из драйвера после ошибки.

## Следующие шаги

1. После power-cycle: не запускать v32; вернуться к v31/v24 без чтения VLD.
2. Проверить гипотезу slice offset: `InitH264BarrelShift` вызывается до
   `GetStartCode`, `ctx+0xa18` = 0. Ветка `Vdec_Drv_H264_setPara` выставляет
   `a18` перед вызовом; возможно, компонент не передаёт offset. Обернуть
   `Vdec_Drv_H264_setPara` (без чтения VLD) и залогировать param id/value.
3. Разделить `MISCa4 bit16` (done) и `bit12` (возможно, error); проверить
   `VLD84` после успешного `parse`.
4. Если `a18`/slice offset подтвердится — патчить точку перед
   `InitH264BarrelShift` (не `0x467f8` +5, а реальный offset из
   `GetStartCode`/`setPara`).

## Артефакты

- Патч: `patches/0082-vcodec-poll-dec-done.patch`.
- LARB bypass: `8b55af6`, `patches/0081-vcodec-larb1-mmu-bypass.patch`,
  `docs/vdec-larb1-2026-11-23.md`.
- Шимы: v24 (`cf93973f...`), v30 (`db6e6483...`), v31 (`723c5e83...`);
  v32 (`5f595490...`) — опасен, не использовать.
- Планшет: `root@172.17.141.162` (пароль 12345), после зависания нужен
  power-cycle; `/dev/Vcodec` (160:0); mainline `mtk_vcodec_dec` выгружен.

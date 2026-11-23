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
  при таймауте печатает дамп `GCON/MISC` (без VLD, см. ниже).

Результат: `WAITISR ret=0`, HAL продолжает работу:

```
[VCODEC] poll dec done after 1 ms MISCa4=00011000
[VCODEC] compat WAITISR ret=0
```

Модуль: `sha256 a106062001da61dc2dbb7bb0c84c808d17cf7ffa655ef5e7360f0e4230696308`,
локально `/tmp/opencode/vcodec_safe.ko`, на устройстве `/tmp/vcodec_safe.ko`;
загрузка `insmod ... hw_power=1`.

> Первая версия модуля (`df105842…`) при таймауте `WAITISR` читала
> `VLD+0x84/+0xe8/+0x2d8`. CSD-прогон v33 привёл к таймауту, дамп VLD —
> и плата зависла. В безопасной версии VLD-чтения из драйвера убраны
> полностью: при простое/зависании обращение к VLD вешает SMI-шину.

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
этом стенде небезопасно.**

## Опасность: VLD-дамп из драйвера

Первая версия polling-модуля (`df105842…`) при таймауте `WAITISR` читала
`VLD+0x84/+0xe8/+0x2d8`. CSD-прогон v33 привёл к таймауту, сработал дамп
VLD — плата зависла (SSH/ping пропали). В безопасной версии
(`a1060620…`) VLD-чтения из драйвера убраны полностью; дамп содержит
только `GCON`, `MISC+0x28`, `MISC+0xa4`, `MISC+0x14`.

## v33: CSD отправляется, но slice offset не доходит

- `omx_decode2_avc_csd`: `CSD=649`, `SHIM SetParam` только id
  11/15/23/22/17/18 (CSD/SPS/PPS-id нет), `SHIM Wait ret=1`.
- `SHIM sc ret=357`, но `ctx+0xa18=0`: `GetStartCode` находит slice на
  смещении 357, а `InitH264BarrelShift` (вызывается раньше) стартует VLD
  с начала AU. Все `parse` дают `ue=3,3,3` → `-16`; `setDecPicInfo` не
  вызывается.

## Следующие шаги

1. После power-cycle: загрузить безопасный модуль `a1060620…`, **не**
   запускать v32 и старый `df105842…`.
2. Проверить гипотезу slice offset: убрать ведущий SEI/AUD
   (`/tmp/opencode/strip_nal.py`) или выставить `a18` из `GetStartCode`
   до `InitH264BarrelShift`.
3. Обернуть `Vdec_Drv_H264_setPara` с корректным ABI (без чтения VLD),
   чтобы понять, передаёт ли компонент offset.
4. Разделить `MISCa4 bit16` (done) и `bit12` (возможно, error); VLD
   читать только средствами библиотеки, не из шима/драйвера.

## Артефакты

- Патч: `patches/0082-vcodec-poll-dec-done.patch`.
- LARB bypass: `8b55af6`, `patches/0081-vcodec-larb1-mmu-bypass.patch`,
  `docs/vdec-larb1-2026-11-23.md`.
- Шимы: v24 (`cf93973f...`), v30 (`db6e6483...`), v31 (`723c5e83...`);
  v32 (`5f595490...`) — опасен, не использовать.
- Планшет: `root@172.17.141.162` (пароль 12345), после зависания нужен
  power-cycle; `/dev/Vcodec` (160:0); mainline `mtk_vcodec_dec` выгружен.

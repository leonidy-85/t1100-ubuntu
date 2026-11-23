# VLD-шим v13 подвесил плату; v14 без чтения VLD (23.11.2026)

## Что случилось

После прогона HAL `omx_decode2_avc2` с шимом `libvdecformat13.so` планшет
`172.17.141.162` перестал отвечать: `ping` 100 % loss, SSH `Connection timed
out`, вторая SSH-команда (`ls /sys/.../smi*`, `clk_summary`) тоже зависла.
`timeout 30` не смог убить процесс — это не обычный `D`-state userspace,
а, вероятно, **bus hang** при доступе к VLD/VDEC.

Нужен физический power-cycle.

## Чем v13 отличался от стабильного v12

`libvdecformat13.so` (sha256 `c3440aaa29c6c553ee5a505055157f0ae5e84f3005d816f432e9e17ad4bd09bd`)
оборачивал:

- `bVDecWaitVldFetchOk(ctx, file)` — **до** вызова читал `H264_HAL_ReadVLD(ctx+0x7d4, 0xe8/0x84/0xf4)`,
  **после** — ещё раз;
- `H264_HAL_ReadVLD` — логировал `0xe8/0x84/0xf4/0x2d8`.

В v12 (`libvdecformat12.so`, sha `725e7d…`) этих обёрток не было; он отработал
до таймаута `WAITISR` и не подвесил плату.

Наиболее вероятная причина зависания — **чтение VLD-регистров до/во время
инициализации VLD** (шим читает `0xe8` перед `bVDecWaitVldFetchOk`), когда
база/клок VLD ещё не в том состоянии. Обычный `readl` в ioctl не отключает
прерывания глобально, но при отсутствии ответа interconnect CPU может
зависнуть навсегда.

## SMI common / DIS: гипотеза ослаблена

По DTB p29:

- `larb@16010000` ссылается на **общий** SMI `smi@14019000` (phandle `0x2f`),
  а он в домене **DIS** (`power-domains = <0x47 0x07>`).
- Дисплей/консоль работают, значит DIS и SMI common включены.
- `larb1` в домене VDE (`<0x47 0x0a>`), его клоки и `pm_runtime` включает
  `vcodec_larb_get()`; `GCON=0x111` подтверждал VDEC+LARB1.
- Поэтому «SMI common выключен» — маловероятно. Более вероятен именно
  VLD-доступ (или неверная банковская/PA-адресация VLD).

`eVideoWaitEvent()` использует `wait_event_interruptible_timeout()`
(`mt6771/common/val/src/val.c`), то есть сам `WAITISR` прерываемый и
ядро подвесить не должен. Зависание — на регистровом доступе.

## v14: безопасный шим

Собран `libvdecformat14.so` из `vdecformat12.c` с единственной обёрткой
`bVDecWaitVldFetchOk`, которая **не читает VLD**, а только логирует вход и
возврат:

```c
int bVDecWaitVldFetchOk(void *ctx, void *file)
{
        static int n;
        int r;

        if (n++ < 32)
                logmsg("SHIM Wait begin ctx=%p\n", ctx);
        r = real_wait ? real_wait(ctx, file) : -999;
        if (n <= 32)
                logmsg("SHIM Wait ret=%d\n", r);
        return r;
}
```

- Файл на build-хосте: `/home/l/omx-avc/vdecformat14.c`,
  `/home/l/omx-avc/libvdecformat14.so`.
- sha256: `a2ae3f2df112051eb6eff91c5c3175579e53028109274f0bf2e26dda28597025`.
- Остальные обёртки (`ReadAVCVLD`, `WriteVLD`, `SetSPS/PPS`, `parse`) — как в
  v12, они не добавляют лишних чтений VLD.

## План после power-cycle

1. Найти новый IP планшета (`.162` мог смениться), проверить `uptime`,
   `lsmod`, `/dev/Vcodec`.
2. Загрузить вендорский модуль с `hw_power=0`:
   `rmmod vcodec_kernel_driver; insmod /tmp/vcodec_larb_mmu2.ko hw_power=0`.
3. `vcodec_lock_test` — только `LOCKHW`/`UNLOCKHW`, без HAL и VLD. Это
   проверяет `vdec_power_on`/`vdec_break` и LARB1. Если зависает здесь —
   проблема в драйвере/питании, не в HAL.
4. Затем `hw_power=1` и HAL с **v14** (или v12), `timeout 30`, вывод в файл;
   **после** завершения/таймаута читать `dmesg`:
   `dmesg | grep -E "VCODEC.*(DUMP|POTENTIAL|LARB1|WAITISR)|vdec_break"`.
   Драйверный `vdec_break()` на release дампит `MISC[68..79]` и
   `VLD[45,46,52,58,59,61,62,63]` — это безопаснее live-чтений.
5. Если v14 снова подвесит плату — вернуться к v12 и не трогать VLD из
   userspace; анализировать только драйверный дамп после release.

## Артефакты

- Планшет: `root@172.17.141.162` (пароль 12345), сейчас недоступен.
- Вендорский модуль: `/tmp/vcodec_larb_mmu2.ko` (sha `37ab74c7…`), `hw_power=1`.
- HAL: `/opt/bionic/vendor/bin/omx_decode2_avc2`
  (sha `c6628c96…`), ION-шим `/vendor/lib/libionshim_vc4.so`,
  лог-шим `/vendor/lib/liblogshim.so`.
- Build-хост: `l@172.17.141.124`, `/home/l/omx-avc`,
  `/home/l/vcodec-work`, `~/t1100-ubuntu-build/src`, `out-debug`.
- Git: последний коммит `8b55af6` (LARB1 bypass), запушен.

# panfrost на MT6771: клин «картинка замерла» при отключении USB

Дата: 15.11.2026. Автор: `gpu-mesa`. Железо: Fplus T1100 (MT6771, Mali-G72 MP3),
ядро 6.12.114, p29 = `build/it6112-resume/boot_resume_full.img`
(sha256 `75af7b5f…`). На устройстве в этой сессии ничего не запускалось и не
прошивалось; всё ниже — разбор кода + факты, снятые lead'ом.

## 1. Факты с устройства

| # | Факт | Источник |
|---|---|---|
| 1 | `panfrost 13040000.gpu: js fault, js=0, status=DATA_INVALID_FAULT, head==tail` — ~100–111 за загрузку, 3700 в загрузке с s2idle | dmesg |
| 2 | Редко: `gpu sched timeout, js=0, config=0x7b00/0x7302/0x7b01, status=0x8 (JOB_CONFIG_FAULT), head==tail` | dmesg |
| 3 | В момент клина `kworker/u32:*` (`Workqueue: panfrost-reset`) в state:D на `__synchronize_irq → synchronize_irq → panfrost_job_timedout+0x58` | sysrq-w |
| 4 | `unexpectedly high interrupt latency` — ровно при подключении/отключении USB | dmesg |
| 5 | Кабель подключён (RNDIS, charger `online=0`) — не замерзает; замерзает **при отключении** кабеля | пользователь |
| 6 | Замер 18:00:27–18:01:35: `kwin_wayland` в `dma_fence_default_wait` ~65 с; reset-воркер там же ~48 с; затем IRQ завершился, **fence оказался signaled**, reset не делался (`lat` 7→8); KWin вышел из ожидания через ~2 с после возврата кабеля (`usb0: carrier: link connected`) | `freeze3.sh` |
| 7 | В том же sysrq-дампе `sugov:0` и `sugov:4` в state:D (стеки обрезаны) | sysrq-w |
| 8 | `echo on > …/13040000.gpu/power/control` (runtime PM выключен) — клин **повторился** | эксперимент lead'а |
| 9 | `mtu3` не печатает `pullup D-` в момент клина | dmesg |

## 2. Что именно означает D-состояние в `synchronize_irq()`

`panfrost_job_irq_handler` — **threaded** IRQ (`devm_request_threaded_irq`,
`IRQF_SHARED`), а `synchronize_irq()` (kernel/irq/manage.c) после ожидания
top-half делает

```c
	wait_event(desc->wait_for_threads, !atomic_read(&desc->threads_active));
```

`threads_active` держится всё время, пока выполняется
`panfrost_job_irq_handler_thread()` → `panfrost_job_handle_irqs()`. Поэтому
стек из sysrq-w доказывает только одно: **threaded-обработчик был активен**, а
не «hardirq залип на MMIO» и не «IRQ не доставлен». Кто именно держит
`threads_active` — из стека не видно.

## 3. Гипотезы: что мертво, что живо

**Мертво — «IRQ приходит, когда GPU в runtime-suspend, и hardirq залипает на
MMIO».** Два независимых аргумента:
1. эксперимент №8 (`power/control=on`) клин не отменил;
2. пока job не завершён, panfrost держит ref на устройстве
   (`pm_runtime_get_sync()` в `panfrost_job_hw_submit()`), а
   `panfrost_device_runtime_suspend()` вообще возвращает `-EBUSY`, пока
   `panfrost_job_is_idle()` == false. То есть во время таймаута GPU
   принципиально не может быть в runtime-suspend.

**Живо — thread держится ~48 с внутри `panfrost_job_irq_handler_thread()`.**
Три кандидата, все проверяемы:

| K | Гипотеза | Чем подтвердится |
|---|---|---|
| K1 | цикл `while (status)` в `panfrost_job_handle_irqs()` не выходит: `JOB_INT_RAWSTAT` снова и снова выставляет бит | счётчик кругов > 8 + `rawstat`/`js_state` в dmesg |
| K2 | thread ждёт `pfdev->js->job_lock`, который держит `panfrost_job_hw_submit()` **вместе с MMIO-записью в job slot**; запись стопорится (зависшая AXI-транзакция GPU) — тогда thread крутится на спинлоке, `threads_active` не падает, TDR-воркер стоит в D | время ожидания `job_lock` в dmesg |
| K3 | thread медленный/не планируется по причине вне panfrost (в кадре есть `sugov:0/4` в D — общий ресурс PMIC/pwrap/regulator или SPM/EMI-переход при отключении USB) | «job irq thread took N ms» + полный `sysrq-l` (см. §6) |

`config=0x7b00` в сообщении о таймауте раскладывается по `panfrost_regs.h` как
`START_FLUSH_CLEAN_INVALIDATE | JOB_CHAIN_FLAG | END_FLUSH_CLEAN_INVALIDATE |
ENABLE_FLUSH_REDUCTION` — то есть конфиг, который писал драйвер; `status=0x8`
(`JOB_CONFIG_FAULT`) читается уже в таймауте, а не из IRQ.

## 4. Патч 0075 — только измерения

`patches/0075-drm-panfrost-instrument-the-job-irq-stall.patch` (в `series`).
Ничего не решает и не меняет поведение, добавляет в dmesg:

1. `job irq: N round(s), job_lock waited X ms, rawstat=…, js_state=…` — при
   `rounds > 8` или ожидании лока > 100 мс (K1/K2);
2. `job irq thread took X ms, suspended=0/1` — если весь threaded-обработчик
   дольше 100 мс (K3);
3. `synchronize_irq(job) took X ms` — в `panfrost_job_timedout()`;
4. в существующую строку `gpu sched timeout` добавлены `rawstat`, `js_state`,
   `int_mask`.

Все чтения — в путях, которые и так читают регистры; предупреждения не
режутся ratelimit'ом, но срабатывают не чаще одного раза на событие IRQ, так
что усугубить клин патч не может.

Почему не «лечим» сразу: любой вариант «не входить в `synchronize_irq` без
таймаута» упирается в то, что `panfrost_reset()` сам делает
`job_write(JOB_INT_MASK, 0); synchronize_irq()` — то есть тот же unbounded
wait, только позже, уже с `panfrost_core_dump()` и с риском гонки с живым
threaded-обработчиком. Пока не известно, кто держит `threads_active`,
«безопасно развязать» нельзя.

## 5. Сборка (build-only, на планшет не прошивалось)

Дерево `/home/l/t1100-ubuntu-build/src-nonwifi` (то же, что дало p29),
out — `out-nonwifi`, инкрементально (`CC drivers/gpu/drm/panfrost/panfrost_job.o`
+ link), 0 warnings.

| Артефакт | Значение |
|---|---|
| `Image` (до патча = p29) | `de04b7ab02c6…af943f`, 42 162 688 Б |
| `Image` с 0075 | **`6711450f5615bf899d3583b7aac48412e3b9de21a8b4204faedf8c171e745f6d`** |
| `Image.gz` | `fccc4b68…dc235e`, 15 578 041 Б |
| boot-образ | **`build/pf-irq/boot_pf_irq_diag.img`**, 33 554 432 Б, sha256 `40f0cce2ab59721befdb17a5659096e246dfd9330ecee360dd37773e0aafb70e`, md5 `0af49be7b0135006f8751449bd5be06a` |
| DTB в образе | `4f01d337…` — **тот же, что в p29** (в `src-nonwifi` DTS уже с CONSYS/Wi-Fi, `8362894f…`, поэтому DTB взят из p29) |
| ramdisk / cmdline | из p29 без изменений (`0cfa596d…`, `t1100.it6112_skip_init=1`) |
| kernelrelease | `6.12.114` |

Круговая проверка: распакованный из образа kernel = `6711450f…`, DTB и ramdisk
побайтно совпадают с p29. Откат — p29 (`75af7b5f…`).

## 6. План проверки на устройстве (по согласованию с lead)

### 6.1. Без прошивки — сначала это

Цель: понять, кто держит `threads_active`, ещё до любого тестового ядра.

1. `ps -eLo pid,tid,stat,wchan:40,comm | grep -E "irq/.*(panfrost|13040000)"` и
   `cat /proc/<tid>/stack` в момент клина — стек **IRQ-треда**, а не только
   D-задач.
2. `echo l > /proc/sysrq-trigger` (backtrace **всех** CPU, не только D) в
   момент клина — покажет, крутится ли CPU в `panfrost_job_handle_irq` /
   `queued_spin_lock_slowpath` / `readl` (K1/K2) или там ничего нет (K3).
3. `/proc/interrupts` до/во время/после клина по строке `panfrost-job` (и
   `13040000.gpu`): растёт ли счётчик (IRQ доставляются) или стоит.
4. `cat /sys/kernel/debug/devfreq/13040000.gpu/trans_stat` до/после — был ли
   переход частоты GPU в момент клина.
5. A/B по DVFS без прошивки: `echo performance > …/governor` (фикс. 800) и
   `echo powersave > …/governor` (фикс. 698), в каждом — 3 отключения кабеля.
   Если клин исчезает в обоих — виноват переход частоты GPU.
6. То же для CPU: `echo performance > /sys/devices/system/cpu/cpufreq/policy{0,4,6}/scaling_governor`
   (убирает `sugov:0/4`) → если клин исчез, копать PMIC/regulator/SPM, а не
   panfrost.
7. `dmesg | grep -iE "pwrap|regulator|devfreq|cpufreq|mtk-emi|spm"` вокруг
   момента клина.

### 6.2. С тестовым ядром (только после согласования)

Прошивка `build/pf-irq/boot_pf_irq_diag.img` в p29 (бэкап p29 —
`build/it6112-resume/boot_resume_full.img`, sha256 `75af7b5f…`).

Сценарий: KWin/Wayland на панели, `dmesg -w` в файл, отключить USB-кабель,
подождать 60–90 с, вернуть кабель.

Что читать в dmesg:

| строка | вывод |
|---|---|
| `job irq: N round(s), job_lock waited X ms` | N>8 → K1 (RAWSTAT не очищается); X>100 мс → K2 (спинлок за MMIO в `hw_submit`) |
| `job irq thread took X ms` | X ≈ длительности клина и мало кругов → K3 (или ожидание лока) |
| `synchronize_irq(job) took X ms` | подтверждает, что D-состояние = ожидание threaded-обработчика |
| `gpu sched timeout … rawstat=… js_state=… int_mask=…` | какие источники висят: `int_mask=0` при ненулевом `rawstat` = thread не дошёл до переармирования; `js_state` показывает, активен ли слот |

Критерий «патч не сломал»: загрузка до Plasma, `kmscube`/`glmark2` проходят,
нет новых WARN/BUG, клин воспроизводится так же (патч диагностический).

## 7. Открытые вопросы

- Хронические `DATA_INVALID_FAULT` (п.1 фактов) — **отдельный** баг: они
  бывают и без клина (17:59:50 / 18:00:17 / 18:01:37 при `sto=3`), и в
  glmark2-сценах `conditionals/function/loop/logic` (13.11). Похожие отчёты
  есть по G57 (Mesa #16359: шторм `DATA_INVALID_FAULT` + порча картинки,
  лечится только shrinker-scan) — то есть это может быть не MT6771-специфика,
  а взаимодействие Mesa 26.x с panfrost. Для нашей платы первый дешёвый тест —
  `PAN_MESA_DEBUG=nofp16`/`noafbc`/`sync` и проверка, меняется ли число fault'ов.
- `sugov:0/4` в D в момент клина — сильный намёк на общий ресурс
  (PMIC/pwrap/regulator или SPM/EMI). Если §6.1 п.6 подтвердит, это уже не
  panfrost, а DVFS-стек MT6771.

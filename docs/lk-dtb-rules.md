# Почему наши образы не запускаются: требования LK к DTB

Дата: 29.10.2026. Источник — `refs/pennyos-lk/` (проект PennyOS: mainline Linux
на **том же MT6771/Helio P70**, стоковый MTK LK). У них была ровно наша
симптоматика: **любой mainline-образ → boot-loop**, «ядро не доходит до USB».

## Корень проблемы

LK **никогда не прыгает в наше ядро**. Он падает в `ASSERT`/`while(1)` на этапе
подготовки device tree (применение вендорского `dtbo`, поиск обязательных
узлов, проверка reserved-memory), после чего плату сбрасывает watchdog — это и
есть наш «циклический ресет» с `bootreason=lk_crash`.

Размер ядра, упаковка в boot.img, `text_offset`, адрес загрузки — **ни при чём**.
Мы это и наблюдали: минимальное 3,4 МБ ядро, payload на 328 Б, образ со стоковым
DTB — все вели себя одинаково.

## Четыре правила LK (нарушение любого = сброс)

| # | Правило | Как нарушено у нас |
|---|---|---|
| 1 | Вендорский **`dtbo` всегда накладывается** на DTB; `/__symbols__` должен резолвить **все** метки из `__fixups__` оверлея | в нашем минимальном DTB нет меток, на которые ссылается `dtbo_a` |
| 2 | `/chosen/bootargs` обязан существовать | ✅ есть |
| 3 | Должен существовать узел с `compatible = "mediatek,scp"` (`platform_fdt_scp`, assert `mt_boot.c:0x394`) | ❌ нет |
| 4 | Ни один статический `/reserved-memory`-ребёнок с `reg` не должен пересекаться с резервациями самого LK (ATF, TEE, SSPM, SPM, SCP, modem, framebuffer, dramc, **`ibc-reserved`**) — LK добавляет их сам как `mblock-N-*` | ❌ мы скопировали эти регионы из стокового DTB; позже — свой `ramoops@0x70000000` поверх `ibc-reserved` |

Прочее, что требует LK и что полезно знать:
- DTB ищется в **последних 512 КиБ** kernel-блоба обратным сканом по `d00dfeed`
  (у PennyOS DTB **дописан к `Image.gz`**; у нас сток v2 с полем `dtb` — работает).
- `tags_addr=0x54000000`, `ramdisk_addr=0x55000000`, ramdisk ≤ 16 МиБ,
  kernel 512 КиБ-выровнен, `bootopt=64…` в cmdline, merged DTB ≤ 512 КиБ.
- Сжатое ядро кладётся на `0x56900000` и разжимается на `0x40080000`.
- `text_offset=0` на `0x40080000` — нормально при `CONFIG_RELOCATABLE=y`.

## План починки (по образцу PennyOS)

1. Снять с платы `dtbo_a` (p31) и `lk_a` (p28) — из рекавери, `dd | nc`.
2. `dtc -I dtb -O dts dtbo_a` → `gen-lk-compat-dtsi.py` → наш
   `mt6771-fplus-t1100-lk-compat.dtsi`: `/__symbols__` на инертные узлы
   `/mtk-lk-sink/*`, `scp` c `compatible = "mediatek,scp"` и
   `status = "disabled"`, `/delete-node/` для статических ATF/SPM/SSPM/SCP/
   dramc/TEE-резерваций, `odm`/`gpio@10005000`/`chosen` — «вендорной формы».
3. Проверить офлайн: `fdtoverlay` (+ адаптированный `check-lk-dtb.py`) —
   собрать образ только если правила 1–4 проходят.
4. Пересобрать DTB/`boot_a` и прошить.
5. «Чёрный ящик» (по их же схеме): `ramoops` ровно как у вендора
   (`0xe0000@0x54410000`, console 256 КиБ) + `simple-framebuffer` на буфере LK
   + initramfs, который **сам перезагружается через N секунд**, чтобы лог
   гарантированно пережил сброс и читался из Aurora (`/sys/fs/pstore`).

## 11.11.2026: настоящая причина найдена — `ibc-reserved` на `0x70000000`

Правила 1–3 и `check-lk-dtb.py` проходили 10/10, а образ всё равно уходил в
цикл. Ключ дал `expdb` (p3) **нашего** планшета: initramfs успевал записать
туда `dmesg`, а LK перед сбросом — свой лог. В конце сессии:

```
[4203] DTS node:ramoops@70000000 reserved start: 0x70000000 size: 0x100000
[4204] reserved_memory_conflict_check:1314 failed i:2 0:1:1:1
[4237] reserved_memory_conflict_check fatal error keep while (1)
```

То есть LK резервирует `0x70000000` (1 МиБ, `ibc-reserved`) сам, а наш
`/reserved-memory/ramoops@0x70000000` с ним пересекается — правило 4, и LK
честно уходит в `while (1)`.

Почему офлайн-валидатор это пропустил: список резерваций он берёт из **живого
дерева Aurora**, а `ibc-reserved` LK добавляет только при загрузке, в дерево
он не попадает. Лечение — `LK_EXTRA_RES`:

```sh
LK_EXTRA_RES=0x70000000:0x10000:ibc-reserved \
  python3 refs/pennyos-lk/check-lk-dtb.py <dtb> <dtbo_a> <live.dts>
```

Pstore переехал на вендорское окно, которое LK резервирует и сам прописывает в
cmdline (`ramoops.mem_address=0x54410000 ramoops.mem_size=0xe0000`,
`ramoops.console_size=0x40000`): узел `ramoops@70000000` удалён патчем **0042**,
ядро регистрирует pstore по параметрам (`fs/pstore/ram.c`).

После этого `boot_ubuntu28.img` загрузился: на экране лог ядра, `card1-DSI-1`
`connected/enabled` 1600×2176, `fb0: mediatekdrmfb`.

**Урок:** «валидатор сказал ok» ≠ «LK принял». Единственные надёжные признаки —
`[LK]jump to K64 0x40080000` в expdb или живой userspace. И второе: LK у
разных сборок разный (у рабочего планшета ENG-сборка `cedbe12e…`, у нас
`f94d45b1…`), поэтому набор собственных резерваций надо брать с **той же**
платы.

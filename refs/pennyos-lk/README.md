# refs/pennyos-lk — требования MT6771-LK к DTB (PennyOS, Planet Cosmo)

Источник: `github.com/planet-community/pennyos` (mainline Linux 6.4 + Debian на
**том же SoC MT6771/Helio P70**, LK `k71v1_64_bsp`).

Почему это важно: у них была **ровно наша проблема** — «каждый mainline-образ
уходил в boot-loop». Причина: **LK падает в ASSERT/while(1) при подготовке
device tree**, ещё до прыжка в ядро. Размер ядра, упаковка и адреса были ни при
чём.

Файлы:
- `lk-dtb-requirements.md` — 4 правила LK + детали (DTB ищется в **последних
  512 КиБ** kernel-блоба сканом назад по `d00dfeed`; `tags_addr=0x54000000`,
  `ramdisk_addr=0x55000000`, ramdisk ≤16 МиБ; kernel 512 КиБ-выровнен;
  `bootopt=64…` в cmdline; merged DTB ≤512 КиБ; kernel.gz → `0x56900000`,
  gunzip → `0x40080000`; `text_offset=0` при `CONFIG_RELOCATABLE=y` нормально).
- `gen-lk-compat-dtsi.py` — генератор `__symbols__`-прослойки из `__fixups__`
  вендорского dtbo (наш случай — сгенерировать из нашего `dtbo_a`).
- `mt6771-mtk-lk-compat.dtsi` — пример сгенерированного файла (для Cosmo).
- `check-lk-dtb.py` — офлайн-проверка правил 1–4 через `fdtoverlay`.
- `pennyos-debug.dtsi` — «чёрный ящик»: `ramoops` (0xe0000@0x54410000, как у
  вендора) + `simple-framebuffer` на буфере LK.
- `read-lastboot.sh` — чтение лога прошлой загрузки из Android/Aurora.

Лицензии/авторство — у исходного проекта (GPL-2.0/ MIT для dtsi).

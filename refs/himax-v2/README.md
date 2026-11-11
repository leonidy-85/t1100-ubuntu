# himax_v2_common — вендорский драйвер Himax (GPL-2.0)

Публичный исходник драйвера Himax, из которого взяты init-последовательность и
раскладка кадра для HX83102E (см. `docs/touch-hx83102e.md`, §8).

| | |
|---|---|
| URL | https://github.com/MorgenYang/himax_v2_common |
| коммит | `106bb9614d169e008565c013f7ce0ec110b9646a` (2019-08-09, «modify coding style») |
| лицензия | GPL-2.0 (`SPDX-License-Identifier: GPL-2.0` в каждом файле) |
| размер | ~1.3 МБ, каталог `hxchipset/` |

Локально скопированы только два файла (остальное — по ссылке выше):

- `himax_ic_HX83102.c` — `hx83102e_chip_init`, `hx83102e_sense_off`,
  `hx83102e_read_event_stack`, `himax_hx83102e_reg_re_init`,
  `himax_hx83102e_func_re_init`, `himax_hx83102d_sense_on`,
  `himax_hx83102d_reload_to_active`, `hx83102_register_read`,
  `hx83102_flash_write_burst`, `hx83102_burst_enable`;
- `himax_ic_HX83102.h` — константы для 83102E
  (`hx83102e_fw_addr_raw_out_sel 0x100072EC`,
  `hx83102e_ic_adr_tcon_rst 0x80020004`, RX/TX/res по умолчанию).

Не скопированы, но нужны при дальнейшем разборе:

- `himax_ic_core.h` — карта адресов (`fw_addr_ctrl_fw 0x9000005c`,
  `fw_addr_chk_fw_status 0x900000a8`, `fw_addr_event_addr 0x30`,
  `fw_addr_sorting_mode_en 0x10007f04`, `fw_data_fw_stop 0xA5`,
  `fw_data_clear 0`, `fw_data_safe_mode_release_pw_active 0x53`);
- `himax_common.c` — `himax_report_data_init` (размер кадра),
  `himax_parse_report_points` (раскладка), `himax_checksum_cal`,
  `himax_ts_event_check`;
- `himax_ic_incell_core.c` — `himax_mcu_power_on_init`,
  `himax_mcu_touch_information`.

Как получить заново (на build-хосте, где есть сеть):

```sh
git clone --depth 1 https://github.com/MorgenYang/himax_v2_common.git
```

Проверка, что это та же кодовая база, что в стоковом ядре: совпадают
`0x100072EC`, `0x80020004`, `0x53`, `0x9000005C`, `0xA5`, `0x900000A8`,
`0x10007F40`, `0x10007F04`, `0x30`, пароль `0x31=0x27 / 0x32=0x95`.

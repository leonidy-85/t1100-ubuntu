# M26 — LK/ATF и DEVAPC: что нашлось офлайн (13.11)

Задача рубежа: понять, кто не пускает AP к `0x1100c000`. Разбор вёлся по
**образу LK с самой платы** (read-only дамп раздела) и по сравнению DTB.

## 1. Образ LK

| что | значение |
|---|---|
| раздел | GPT entry 24 `lk_a` = `/dev/block/179:28`, 8 МиБ |
| md5 | `fab6c0a7cf83375e16d43211f9998c20` |
| дамп | `/tmp/opencode/lk_a.img` (не в git) |

`strings -a -t x` по нему:

```
0x58344  [DEVAPC] sec_post_init
0x5835c  [DEVAPC] platform_sec_post_init - SMC call to ATF from LK
0x5831c  [SEC] crypto engine HW disable fail
0xae904  devapc_mpu_ao@10015000
0xae928  mediatek,devapc_mpu_ao
0xaf7dc  devapc@10207000
0xaf7f8  mediatek,devapc
0xaf86c  devapc-infra-clock
0xb2764  btif@1100c000
0xb2780  mediatek,btif
0xb2824  btifc
0xb2920  irtx@1100d000
0xb1e30  serial@11003000
0xaeb08  security_ao@1001a000
0xaeab0  mbist_ao@10013000
0xaeb68  topckgen_ao@1001b000
0xaec00  okay                      <- значение status, которое LK ищет
```

Вывод: LK **не программирует права DEVAPC сам** — он вызывает SMC, и политику
ставит ATF (`[DEVAPC] platform_sec_post_init - SMC call to ATF from LK`).
Узлы (`devapc@10207000`, `devapc_mpu_ao@10015000`, `btif@1100c000`,
`irtx@1100d000`) LK ищет **по compatible в нашем DTB** (в LK лежат и имена
узлов, и compat-строки, и `status`-строка `okay`).

ATF-образ (`gz_a`, GPT entry 22 = `/dev/block/179:26`, 16 МиБ, md5
`d50a93083b254bae7b451b9db6506784`) **не содержит читаемых строк** про
devapc/dmpu — упакован/зашифрован, офлайн-разбор политики невозможен.

## 2. Сравнение нашего DTB со стоковым

Наш живой DTB (`refs/device/fdt-live.dtb`) против `refs/stock-mt6771.dts`:

| узел | сток | наш живой DTB |
|---|---|---|
| `devapc@10207000` | reg 0x10207000+0x1000e000, `interrupts = <0 0x91 8>`, `clocks = <&infracfg_ao 0x2d>`, `clock-names = "devapc-infra-clock"` | **идентично** |
| `devapc_mpu_ao@10015000` | `mediatek,devapc_mpu_ao`, reg 0x1000 | **идентично** |
| `btif@1100c000` | `mediatek,btif`, 3 окна, 3 IRQ, `clock-names = "btifc","apdmac"` | **идентично** |
| `irtx@1100d000` | `mediatek,irtx`, reg 0x1000 | **идентично** |
| `eem_fsm@1100b000` | `mediatek,eem_fsm` | **идентично** |

Отличий по этим узлам **нет** ⇒ добавлять в DTS нечего, прошивка DTB не
требуется (правило «не прошивать наугад» соблюдено, boot не трогали).

## 3. DEVAPC как блокиратор исключён (замер на железе)

После перезагрузки блок DEVAPC живой: `VIO_MASK0 (0x10207000) = 0xffffffff`
(логирование нарушений включено по всем 379 слейвам). Наш отброшенный write в
BTIF (`IER ← 0xa5a5a5a5`) не оставил **ни одного** следа:

```
VIO_STA word3 (0x1020740c, слейвы 96..127, BTIF=бит6) = 0x00000000
VIO_DBG0 = 0x00000000   VIO_DBG1 = 0x00000000
APC_CON  (0x10207f00) = 0x00000000, запись 0x80000000 не держится
IFR1 (0x10001094) = 0xc78f7db2, бит20 (infra_device_apc) не включается
   (соседние биты того же регистра пишутся: CLR/SET бита18 работает)
```

То есть DEVAPC не заявляет о нарушении, а без VIO утверждать, что это он, нельзя.

## 4. Что добавлено в код

`scripts/remote/m23-btif/` (`m23_devapc_try()`, параметр `m23_devapc_open`):
повторяет вендорскую последовательность `start_devapc()` (`devapc.c:659-663`:
гейт `INFRA_DEVICE_APC` + `APC_CON ← 0x80000000`) и печатает before/after.
На нашем буте результат воспроизводится:

```
m23-devapc[probe]: IFR1 sta=0xc78f7db2 (DEVICE_APC bit20=0)
m23-devapc[probe]: after SET20 sta=0xc78f7db2
m23-devapc[probe]: APC_CON=0x00000000 VIO_MASK0=0xffffffff
m23-devapc[probe]: APC_CON after write=0x00000000 VIO_DBG0=0x00000000
IER 0x1100c004: пишем 0xa5a5a5a5 → читаем 0x00000000
```

## 5. Ограничение метода

Массовое включение всех гейтов INFRACFG_AO (SET `0xffffffff` в 0x80/0x88/0xa4/0xc0)
**вешает плату** (ребут) — так искать «забытый гейт» нельзя.

## 6. Следующий шаг

Одна загрузка **стока** и три чтения: `0x10207f00` (APC_CON), `0x10207000`
(VIO_MASK0), `0x10001094` (бит20) + `tools/device/btif-probe.sh`. Если на стоке
`APC_CON = 0x80000000` и/или бит20 = 1 — значит нужен ровно вендорский
`start_devapc()`, и он у нас уже есть в коде (останется понять, почему запись
не проходит у нас). Если на стоке то же самое (нули) — BTIF write-dead не связан
с DEVAPC, и следующий кандидат — DMPU/ATF (`devapc_mpu_ao@10015000`, у нас
читается нулями) либо блокировка на уровне APB-моста PERI.

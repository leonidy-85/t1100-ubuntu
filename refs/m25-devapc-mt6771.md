# M25 — DEVAPC MT6771: базы, слейв BTIF и состояние на устройстве (13.11)

Цель: выяснить, закрывает ли **DEVAPC** доступ AP к `0x1100c000` (BTIF) и
`0x1100d000` (irtx), и можно ли открыть его из Linux. Итог: **раскладку нашли,
но контроллер в нашем буте недоступен** (APC_CON не пишется, VIO нули, гейт
DEVICE_APC не включается). Ниже — источники и замеры.

## 1. Где DEVAPC в дереве MT6771

`Hadenix/android_kernel_alps-4.4`, ветка `4.4.146`:
`drivers/misc/mediatek/devapc/mt6771/{devapc.c,devapc.h}`.

Узлы в стоковом DT (`refs/stock-mt6771.dts`):

```dts
devapc@10207000 {                      /* :1599 */
	compatible = "mediatek,devapc";
	reg = <0x00 0x10207000 0x00 0x1000 0x00 0x1000e000 0x00 0x1000>;
	interrupts = <0x00 0x91 0x08>;      /* SPI 145 */
	clocks = <0x15 0x2d>;               /* infracfg_ao 45 = DEVICE_APC */
	clock-names = "devapc-infra-clock";
};
devapc_mpu_ao@10015000 { compatible = "mediatek,devapc_mpu_ao"; } /* :1397 */
```

Базой (`DAPC_DEVICE_TREE_NODE_PD_INFRA_INDEX = 0`, `devapc.c:918` `of_iomap(node, 0)`)
служит **0x10207000** — блок VIO/PD; второе окно **0x1000e000** — APC-инстанс
`DEVICE_APC_AO_INFRA_PERI`.

## 2. Раскладка регистров (`devapc/mt6771/devapc.h:73-96`)

```c
#define DEVAPC_PD_INFRA_VIO_MASK(index)  (base + 0x4 * index)
#define DEVAPC_PD_INFRA_VIO_STA(index)   (base + 0x400 + 0x4 * index)
#define DEVAPC_PD_INFRA_VIO_DBG0         (base + 0x900)
#define DEVAPC_PD_INFRA_VIO_DBG1         (base + 0x904)
#define DEVAPC_PD_INFRA_APC_CON          (base + 0xF00)
#define DEVAPC_PD_INFRA_VIO_SHIFT_STA    (base + 0xF10)
#define DEVAPC_PD_INFRA_VIO_SHIFT_SEL    (base + 0xF14)
#define DEVAPC_PD_INFRA_VIO_SHIFT_CON    (base + 0xF20)
```

DBG0 декодируется как `MSTID[15:0]`, `DMNID[21:16]`, `W_VIO[22]`, `R_VIO[23]`,
`ADDR_HIGH[27:24]` (`devapc.h:57-68`). Индексация VIO_STA — **32 слейва на
слово**: `apc_index = module / (MOD_NO_IN_1_DEVAPC * 2) = module / 32`,
`bit = module % 32` (`devapc.c:640-656`). Всего слейвов **379**
(`devapc.c:107-…`, `DEVICE_INFO devapc_infra_devices[]`).

## 3. Номер слейва BTIF

Порядок массива `devapc_infra_devices[]` = номер слейва:

| # | имя |
|---|---|
| 14 | `INFRA_AO_DEVICE_APC_AO_INFRA_PERI` |
| 36 | `INFRASYS_DEVICE_APC` |
| 90 | `PERISYS_APDMA` |
| 92 | `PERISYS_UART0` |
| 93 | `PERISYS_UART1` |
| 97 | `PERISYS_I2C0` |
| **102** | **`PERISYS_BTIF`** |
| 104 | `PERISYS_DISP_PWM` |

⇒ BTIF: `apc_index = 102/32 = 3`, бит **6** ⇒ VIO-слово `0x1020740c`,
бит 6. IRT X в таблице MT6771 отсутствует (только `PERISYS_*` из списка выше),
поэтому «права irtx» по номеру слейва не определить.

## 4. Кто владеет правами: LK/ATF, а не ядро

`devapc.c:659-666`:

```c
static void start_devapc(void)
{
	mt_reg_sync_writel(0x80000000, DEVAPC_PD_INFRA_APC_CON);

	/* SMC call is called to set Device APC in LK instead */
```

и `devapc.h:33`: `#define MTK_SIP_LK_DAPC 0x82000101`.

То есть: ядро только (а) включает APC одним битом `APC_CON[31]` и (б) логирует
нарушения; **сами таблицы прав (APC по слейвам) ставит LK/ATF** через SMC.
В mainline-ядре драйвера DEVAPC нет вообще.

## 5. Замеры на устройстве (mainline `6.12.114-g400cb6f-touch-rot`)

```
APC_CON  0x10207f00 = 0x00000000        запись 0x80000000 → читается 0x00000000
VIO_MASK 0x10207000..                = 0 (0..0x5EC)
VIO_STA  0x10207400/04/08/0c/10/14    = 0   (слово 3 = слейвы 96..127, BTIF бит6 = 0)
VIO_DBG0 0x10207900 = 0x00000000      VIO_DBG1 = 0x00000000
VIO_SHIFT_STA 0x10207f10 = 0x00004000 (жив, менялось при доступах)
APC-инстанс 0x1000e000 (0..0x1AC)     = 0
DMPU_AO 0x10015000 (0x00..0x20)       = 0
```

Гейт `DEVICE_APC` = INFRA1[20] (вендор `clk-mt6771.c:1210`
`GATE_INFRA1(INFRACFG_AO_DEVICE_APC_CG, "infra_device_apc", "axi_sel", 20)`):

```
0x10001094 = 0xc78f7df6   (бит20 = 0)
SET 0x10001088 ← 0x00100000  → 0x10001094 = 0xc78f7df6  (бит20 НЕ встал)
CLR 0x1000108c ← 0x00040000 (бит18 apdma) → 0xc78b7df6  (бит18 снялся)
SET 0x10001088 ← 0x00040000              → 0xc78f7df6  (вернулся)
```

Т.е. соседние биты того же регистра пишутся, а бит `DEVICE_APC` — **нет
(protected/RO)**. После всех манипуляций запись в BTIF по-прежнему не проходит:

```
IER 0x1100c004: было 0x00000000, записали 0xa5a5a5a5 → читается 0x00000000
```

## 6. Вывод

* DEVAPC-контроллер в нашем буте **недоступен на запись** (APC_CON/VIO не
  меняются), его гейт `DEVICE_APC` **не включается**, APC-таблицы и DMPU читаются
  нулями. Ни прочитать права AP для слейва 102, ни изменить их из Linux нельзя.
* Нарушений (VIO) наш denied-write не оставил (`VIO_STA` слово 3 = 0, DBG = 0),
  т.е. либо контроллер не работает (и блокирует не он), либо он не логирует в
  этом состоянии — различить из AP невозможно.
* Факт по источнику: права DEVAPC на MT6771 ставит **LK/ATF** (`MTK_SIP_LK_DAPC`),
  ядро их не программирует. Значит проверка «на стоке» должна смотреть те же
  окна: если на стоке `APC_CON != 0` и `0x1000e000` непустой — права приходят
  от LK и нужно либо повторить его конфигурацию, либо ходить через SMC; если и
  на стоке нули — DEVAPC не при чём, и причина write-dead в другом (следующий
  кандидат — DMPU/ATF-конфигурация secure-регионов `0x10015000`).

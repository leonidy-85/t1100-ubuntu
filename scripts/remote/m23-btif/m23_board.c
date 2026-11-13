// SPDX-License-Identifier: GPL-2.0
/*
 * MT6771 (Fplus T1100): board glue for the public MediaTek BTIF driver.
 *
 * The public port (drivers/staging/mtk-connectivity/btif) is a device-tree
 * driver: it takes three register windows, three IRQs and the clocks
 * "btifc"/"apdmac" from a "mediatek,btif" node.  Mainline 6.12 has neither
 * that node for MT6771 (this port deliberately does not repack the boot DTB,
 * see docs/wifi-port-log.md M23) nor a clk-mt6771 driver that could resolve
 * those gates (MT6771 binds the mt8183 clock drivers).  This file therefore
 *
 *   - registers a platform device so the driver binds without a DT node,
 *   - supplies the register bases and IRQs from module parameters whose
 *     defaults are the stock device tree values (refs/stock-mt6771.dts:2198,
 *     btif@1100c000: reg 0x1100c000/0x11000a80/0x11000b00, IRQ 0x72/0x8b/0x8c),
 *   - enables the two gates directly in INFRACFG_AO (no CCF involvement),
 *   - can dump the controller (read-only) and run one open/close self test.
 */
#include <linux/delay.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/irqdomain.h>
#include <linux/of.h>
#include <linux/of_irq.h>
#include <linux/clk.h>
#include <linux/clk-provider.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>

#include "m23_board.h"
#include "inc/mtk_btif_exp.h"

/* Stock DT, btif@1100c000 (refs/stock-mt6771.dts:2198). */
int m23_btif_pa = 0x1100c000;
module_param(m23_btif_pa, int, 0444);
MODULE_PARM_DESC(m23_btif_pa, "BTIF register window (stock DT: 0x1100c000)");

int m23_btif_txdma_pa = 0x11000a80;
module_param(m23_btif_txdma_pa, int, 0444);
MODULE_PARM_DESC(m23_btif_txdma_pa, "BTIF TX AP-DMA window (stock DT: 0x11000a80)");

int m23_btif_rxdma_pa = 0x11000b00;
module_param(m23_btif_rxdma_pa, int, 0444);
MODULE_PARM_DESC(m23_btif_rxdma_pa, "BTIF RX AP-DMA window (stock DT: 0x11000b00)");

/* GIC SPI numbers, stock DT <0 0x72 8>, <0 0x8b 8>, <0 0x8c 8>. */
int m23_btif_irq = 114;
module_param(m23_btif_irq, int, 0444);
MODULE_PARM_DESC(m23_btif_irq, "BTIF IRQ (stock DT: SPI 0x72 = 114)");

int m23_btif_txdma_irq = 139;
module_param(m23_btif_txdma_irq, int, 0444);
MODULE_PARM_DESC(m23_btif_txdma_irq, "BTIF TX DMA IRQ (stock DT: SPI 0x8b = 139)");

int m23_btif_rxdma_irq = 140;
module_param(m23_btif_rxdma_irq, int, 0444);
MODULE_PARM_DESC(m23_btif_rxdma_irq, "BTIF RX DMA IRQ (stock DT: SPI 0x8c = 140)");

/* >0: after init, dump the controller and do exactly one open/close. */
/* >0: pulse BTIF_WAK once per open (wake the CONNSYS BTIF side). */
int m23_wak_pulse;
module_param(m23_wak_pulse, int, 0444);
MODULE_PARM_DESC(m23_wak_pulse, "T1100: write BTIF_WAK after hw init (wake CONNSYS BTIF)");

/* >0: clear BTIF_HANDSHAKE after hw init (no CTS/RTS flow control). */
int m23_no_handshake;
module_param(m23_no_handshake, int, 0444);
MODULE_PARM_DESC(m23_no_handshake, "T1100: clear BTIF_HANDSHAKE (disable flow control)");

/*
 * M26: the vendor devapc driver does two things before the block is usable:
 * enable the INFRA1[20] "infra_device_apc" clock and write APC_CON[31]
 * (start_devapc(), devapc.c:659-663).  Both failed from userspace in our boot
 * (see refs/m26-lk-devapc.md); the attempt is kept here so it is reproduced
 * and logged on every load, and can be flipped once stock is measured.
 */
/*
 * M28: raw gate writes do not bring up the parents.  CCF does: it walks
 * parent -> mux -> PLL and enables the whole chain, which is what the vendor
 * kernel gets from devm_clk_get("btifc")/("apdmac") and the devapc driver.
 * The clocks are taken from the infracfg provider by ID (mt8183 numbering,
 * include/dt-bindings/clock/mt8183-clk.h: CLK_INFRA_BTIF = 26,
 * CLK_INFRA_DEVICE_APC = 44), so no DT change is needed.
 */
int m23_ccf;
module_param(m23_ccf, int, 0444);
MODULE_PARM_DESC(m23_ccf, "T1100: enable infra_btif/infra_device_apc through CCF (parents included)");

int m23_devapc_open;
module_param(m23_devapc_open, int, 0444);
MODULE_PARM_DESC(m23_devapc_open, "T1100: try the vendor start_devapc() sequence (clock + APC_CON)");

int m23_selftest;
module_param(m23_selftest, int, 0444);
MODULE_PARM_DESC(m23_selftest, "T1100: 1 = dump BTIF registers and run one open/close self test");

/*
 * INFRACFG_AO clock gates.  MT6771 binds the mt8183 CCF drivers, which know
 * nothing about these bits, so the gates are driven here.  Register layout is
 * the mt6765/6771 family one (drivers/clk/mediatek/clk-mt6765.c:522-544):
 * mode-0 set/clr/sta at 0x80/0x84/0x90, mode-1 at 0x88/0x8c/0x94,
 * IFR2 bit31 = btif, IFR3 bit18 = ap_dma.
 */
#define M23_INFRA_AO_BASE	0x10001000
#define M23_IFR2_SET		0x80
#define M23_IFR3_SET		0x88
#define M23_IFR2_CLR		0x84
#define M23_IFR3_CLR		0x8c
#define M23_IFR2_STA		0x90
#define M23_IFR3_STA		0x94
#define M23_CG_BTIF		BIT(31)
#define M23_CG_APDMA		BIT(18)
#define M23_IFR1_SET		0x88
#define M23_IFR1_STA		0x94
#define M23_CG_APC		BIT(20)	/* infra_device_apc */

static void __iomem *m23_infra;
static struct platform_device *m23_pdev;

static void __iomem *m23_map(u32 pa, const char *what)
{
	void __iomem *p = ioremap(pa, 0x1000);

	if (!p)
		pr_err("m23-btif: cannot map %s at 0x%08x\n", what, pa);
	return p;
}

void m23_btif_dump(const char *tag)
{
	static const struct {
		const char *name;
		u32 off;
	} regs[] = {
		{ "RBR/THR", 0x00 }, { "IER", 0x04 }, { "IIR/FCR", 0x08 },
		{ "LCR", 0x0c }, { "LSR", 0x14 }, { "SLEEP_EN", 0x48 },
		{ "DMA_EN", 0x4c }, { "RTOCNT", 0x54 }, { "TRI_LVL", 0x60 },
		{ "WAK", 0x64 }, { "WAT_TIME", 0x68 }, { "HANDSHAKE", 0x6c },
	};
	void __iomem *base = m23_map(m23_btif_pa, "btif");
	int i;

	if (!base)
		return;
	for (i = 0; i < ARRAY_SIZE(regs); i++)
		pr_info("m23-btif[%s] %-9s (0x%03x) = 0x%08x\n", tag,
			regs[i].name, regs[i].off,
			readl(base + regs[i].off));
	iounmap(base);
}

/*
 * Translate an SoC interrupt number to a Linux virq without a device tree
 * entry for the device.
 *
 * A bare request_irq(114) does *not* mean SPI 114 here: virq 114 happens to
 * be owned by the mt-eint (pinctrl) domain, which then refuses to lock the
 * line (tried to flag a GPIO set as output for IRQ).  Devices on this SoC
 * are children of the sysirq domain (mediatek,mt8183-sysirq, /soc
 * interrupt-parent in mt8183.dtsi:21), whose hwirq is the SPI number and
 * which allocates the parent GIC mapping itself, so the DT-equivalent path
 * is irq_create_fwspec_mapping() with the stock DT cell layout
 * <GIC_SPI n IRQ_TYPE_LEVEL_LOW>.
 */
int m23_irq_map(int spi)
{
	struct device_node *root_irqc;
	struct irq_fwspec fwspec;
	unsigned int virq;

	root_irqc = of_find_compatible_node(NULL, NULL, "mediatek,mt8183-sysirq");
	if (!root_irqc)
		root_irqc = of_find_compatible_node(NULL, NULL,
						    "mediatek,mt6577-sysirq");
	if (!root_irqc) {
		pr_err("m23-btif: no sysirq node\n");
		return -ENODEV;
	}

	fwspec.fwnode = of_node_to_fwnode(root_irqc);
	fwspec.param_count = 3;
	fwspec.param[0] = 0;			/* GIC_SPI */
	fwspec.param[1] = spi;
	fwspec.param[2] = IRQ_TYPE_LEVEL_LOW;

	virq = irq_create_fwspec_mapping(&fwspec);
	of_node_put(root_irqc);
	if (!virq) {
		pr_err("m23-btif: cannot map SPI %d\n", spi);
		return -ENOMEM;
	}
	pr_info("m23-btif: SPI %d -> virq %u\n", spi, virq);
	return virq;
}

int m23_clk_enable(void)
{
	u32 sta2, sta3;

	if (!m23_infra) {
		m23_infra = m23_map(M23_INFRA_AO_BASE, "infracfg_ao");
		if (!m23_infra)
			return -ENOMEM;
	}

	sta2 = readl(m23_infra + M23_IFR2_STA);
	sta3 = readl(m23_infra + M23_IFR3_STA);
	pr_info("m23-btif: infra sta2=0x%08x (btif gate %s) sta3=0x%08x (apdma gate %s)\n",
		sta2, sta2 & M23_CG_BTIF ? "CLOSED" : "open",
		sta3, sta3 & M23_CG_APDMA ? "CLOSED" : "open");

	/*
	 * MT6771 inverts the meaning of these bits compared to the mt8183 /
	 * mt6765 CCF tables this port inherits: the IFR bit is the gate
	 * *enable*, so 1 = clock cut, 0 = clock running.  Writing SET (as
	 * mtk_clk_gate_ops_setclr and our first glue version did) therefore
	 * *turned BTIF off*, which is why every BTIF register write was
	 * silently dropped from M23 to M28 while reads returned the values
	 * the bootloader had left there.  Open the gates through CLR.
	 */
	writel(M23_CG_BTIF, m23_infra + M23_IFR2_CLR);
	writel(M23_CG_APDMA, m23_infra + M23_IFR3_CLR);
	wmb();

	sta2 = readl(m23_infra + M23_IFR2_STA);
	sta3 = readl(m23_infra + M23_IFR3_STA);
	if ((sta2 & M23_CG_BTIF) || (sta3 & M23_CG_APDMA)) {
		pr_err("m23-btif: clock gate still closed (sta2=0x%08x sta3=0x%08x)\n",
		       sta2, sta3);
		return -EIO;
	}
	pr_info("m23-btif: clocks on (sta2=0x%08x sta3=0x%08x)\n", sta2, sta3);
	return 0;
}

int m23_clk_disable(void)
{
	/* Left running on purpose: CONNSYS keeps the BTIF link. */
	return 0;
}

int m23_board_register(void)
{
	m23_pdev = platform_device_register_simple("mtk_btif", -1, NULL, 0);
	if (IS_ERR(m23_pdev)) {
		int ret = PTR_ERR(m23_pdev);

		pr_err("m23-btif: platform_device_register_simple failed: %d\n", ret);
		m23_pdev = NULL;
		return ret;
	}
	pr_info("m23-btif: platform device registered (no DT node: base=0x%08x irq=%d)\n",
		m23_btif_pa, m23_btif_irq);
	return 0;
}

void m23_board_unregister(void)
{
	if (m23_pdev)
		platform_device_unregister(m23_pdev);
	m23_pdev = NULL;
}

/*
 * AP-side datapath test: internal loopback of the BTIF controller.  Nothing
 * leaves the SoC, the CONNSYS side is not involved, so this separates "our
 * TX/RX plumbing works" from "the chip does not answer".
 */
int m23_test;
module_param(m23_test, int, 0444);
MODULE_PARM_DESC(m23_test, "T1100: 1 = BTIF internal loopback test (AP side only)");

static void m23_test_loopback(void)
{
	unsigned long id = 0;
	u8 tx[8] = { 'M', '2', '3', 'T', 'E', 'S', 'T', '\n' };
	u8 rx[16];
	int written, got;
	int ret;

	m23_btif_dump("pre-loopback");
	ret = mtk_wcn_btif_open("m23-loopback", &id);
	pr_info("m23-btif: loopback open -> %d\n", ret);
	if (ret)
		return;

	ret = mtk_wcn_btif_loopback_ctrl(id, 1);
	pr_info("m23-btif: loopback_ctrl(1) -> %d\n", ret);
	msleep(20);

	written = mtk_wcn_btif_write(id, tx, sizeof(tx));
	pr_info("m23-btif: write -> %d\n", written);
	msleep(50);

	memset(rx, 0, sizeof(rx));
	got = mtk_wcn_btif_read(id, rx, sizeof(rx));
	pr_info("m23-btif: read -> %d %*ph\n", got, got > 0 ? got : 0, rx);

	mtk_wcn_btif_loopback_ctrl(id, 0);
	m23_btif_dump("post-loopback");
	mtk_wcn_btif_close(id);
}

/* One open/close, no data: proves HW init + IRQ registration work. */
void m23_devapc_try(const char *tag)
{
	void __iomem *infra, *dapc;

	infra = m23_map(M23_INFRA_AO_BASE, "infracfg_ao");
	dapc = m23_map(0x10207000, "devapc");
	if (!infra || !dapc)
		return;

	pr_info("m23-devapc[%s]: IFR1 sta=0x%08x (DEVICE_APC bit20=%d)\n", tag,
		readl(infra + M23_IFR1_STA),
		!!(readl(infra + M23_IFR1_STA) & M23_CG_APC));
	writel(M23_CG_APC, infra + M23_IFR1_SET);
	wmb();
	pr_info("m23-devapc[%s]: after SET20 sta=0x%08x\n", tag,
		readl(infra + M23_IFR1_STA));
	pr_info("m23-devapc[%s]: APC_CON=0x%08x VIO_MASK0=0x%08x\n", tag,
		readl(dapc + 0xF00), readl(dapc));
	writel(0x80000000, dapc + 0xF00);
	wmb();
	pr_info("m23-devapc[%s]: APC_CON after write=0x%08x VIO_DBG0=0x%08x\n",
		tag, readl(dapc + 0xF00), readl(dapc + 0x900));

	iounmap(infra);
	iounmap(dapc);
}

static struct clk *m23_clk_by_id(struct device_node *np, unsigned int id)
{
	struct of_phandle_args spec;

	memset(&spec, 0, sizeof(spec));
	spec.np = np;
	spec.args_count = 1;
	spec.args[0] = id;
	return of_clk_get_from_provider(&spec);
}

static void m23_ccf_one(struct device_node *np, const char *what, unsigned int id)
{
	struct clk *clk, *parent;
	int ret;

	clk = m23_clk_by_id(np, id);
	if (IS_ERR_OR_NULL(clk)) {
		pr_err("m23-ccf: %s (id %u): no clock (%ld)\n", what, id,
		       PTR_ERR(clk));
		return;
	}
	parent = clk_get_parent(clk);
	pr_info("m23-ccf: %s (id %u) before: rate=%lu parent=%s rate=%lu\n",
		what, id, clk_get_rate(clk),
		parent ? __clk_get_name(parent) : "none",
		parent ? clk_get_rate(parent) : 0UL);

	ret = clk_prepare_enable(clk);
	pr_info("m23-ccf: %s clk_prepare_enable -> %d, rate=%lu\n",
		what, ret, clk_get_rate(clk));
	parent = clk_get_parent(clk);
	if (parent)
		pr_info("m23-ccf: %s parent %s rate=%lu\n", what,
			__clk_get_name(parent), clk_get_rate(parent));
}

void m23_ccf_enable(void)
{
	struct device_node *np;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt8183-infracfg");
	if (!np) {
		pr_err("m23-ccf: no mediatek,mt8183-infracfg node\n");
		return;
	}
	m23_ccf_one(np, "infra_btif", 26);
	m23_ccf_one(np, "infra_device_apc", 44);
	of_node_put(np);
}

void m23_selftest_run(void)
{
	if (m23_ccf)
		m23_ccf_enable();

	if (m23_devapc_open)
		m23_devapc_try("probe");

	unsigned long id = 0;
	int ret;

	if (m23_test == 1) {
		m23_test_loopback();
		return;
	}

	if (!m23_selftest)
		return;

	m23_btif_dump("pre-open");
	ret = mtk_wcn_btif_open("m23-selftest", &id);
	pr_info("m23-btif: mtk_wcn_btif_open -> %d, id=0x%lx\n", ret, id);
	m23_btif_dump("post-open");
	if (ret == 0)
		mtk_wcn_btif_close(id);
	m23_btif_dump("post-close");
}

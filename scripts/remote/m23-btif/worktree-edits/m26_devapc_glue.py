import re
p='/home/l/m23-btif/m23_board.c'
s=open(p).read()

if 'm23_devapc_open' not in s:
    s = s.replace('''int m23_selftest;''', '''/*
 * M26: the vendor devapc driver does two things before the block is usable:
 * enable the INFRA1[20] "infra_device_apc" clock and write APC_CON[31]
 * (start_devapc(), devapc.c:659-663).  Both failed from userspace in our boot
 * (see refs/m26-lk-devapc.md); the attempt is kept here so it is reproduced
 * and logged on every load, and can be flipped once stock is measured.
 */
int m23_devapc_open;
module_param(m23_devapc_open, int, 0444);
MODULE_PARM_DESC(m23_devapc_open, "T1100: try the vendor start_devapc() sequence (clock + APC_CON)");

int m23_selftest;''')

    s = s.replace('''void m23_selftest_run(void)
{''', '''void m23_devapc_try(const char *tag)
{
	void __iomem *infra, *dapc;

	infra = m23_map(M23_INFRA_AO_BASE, "infracfg_ao");
	dapc = m23_map(0x10207000, "devapc");
	if (!infra || !dapc)
		return;

	pr_info("m23-devapc[%s]: IFR1 sta=0x%08x (DEVICE_APC bit20=%d)\\n", tag,
		readl(infra + M23_IFR1_STA),
		!!(readl(infra + M23_IFR1_STA) & M23_CG_APC));
	writel(M23_CG_APC, infra + M23_IFR1_SET);
	wmb();
	pr_info("m23-devapc[%s]: after SET20 sta=0x%08x\\n", tag,
		readl(infra + M23_IFR1_STA));
	pr_info("m23-devapc[%s]: APC_CON=0x%08x VIO_MASK0=0x%08x\\n", tag,
		readl(dapc + 0xF00), readl(dapc));
	writel(0x80000000, dapc + 0xF00);
	wmb();
	pr_info("m23-devapc[%s]: APC_CON after write=0x%08x VIO_DBG0=0x%08x\\n",
		tag, readl(dapc + 0xF00), readl(dapc + 0x900));

	iounmap(infra);
	iounmap(dapc);
}

void m23_selftest_run(void)
{
	if (m23_devapc_open)
		m23_devapc_try("probe");
''')
    # constants for bank1 + APC gate
    s = s.replace('#define M23_CG_APDMA		BIT(18)',
                  '#define M23_CG_APDMA		BIT(18)\n'
                  '#define M23_IFR1_SET		0x88\n'
                  '#define M23_IFR1_STA		0x94\n'
                  '#define M23_CG_APC		BIT(20)	/* infra_device_apc */')
    open(p,'w').write(s)
    print('patched')
else:
    print('already')

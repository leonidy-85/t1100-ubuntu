p='/home/l/m23-btif/m23_board.c'
s=open(p).read()

old_en = '''	sta2 = readl(m23_infra + M23_IFR2_STA);
	sta3 = readl(m23_infra + M23_IFR3_STA);
	pr_info("m23-btif: infra sta2=0x%08x (btif %s) sta3=0x%08x (apdma %s)\\n",
		sta2, sta2 & M23_CG_BTIF ? "on" : "OFF",
		sta3, sta3 & M23_CG_APDMA ? "on" : "OFF");

	/* Writing 1 to a bit that is already set is a no-op. */
	writel(M23_CG_BTIF, m23_infra + M23_IFR2_SET);
	writel(M23_CG_APDMA, m23_infra + M23_IFR3_SET);
	wmb();

	sta2 = readl(m23_infra + M23_IFR2_STA);
	sta3 = readl(m23_infra + M23_IFR3_STA);
	if (!(sta2 & M23_CG_BTIF) || !(sta3 & M23_CG_APDMA)) {
		pr_err("m23-btif: clock gate did not come up (sta2=0x%08x sta3=0x%08x)\\n",
		       sta2, sta3);
		return -EIO;
	}
	pr_info("m23-btif: clocks on (sta2=0x%08x sta3=0x%08x)\\n", sta2, sta3);
	return 0;'''

new_en = '''	sta2 = readl(m23_infra + M23_IFR2_STA);
	sta3 = readl(m23_infra + M23_IFR3_STA);
	pr_info("m23-btif: infra before sta2=0x%08x (BTIF bit31=%d) sta3=0x%08x (APDMA bit18=%d)\\n",
		sta2, !!(sta2 & M23_CG_BTIF), sta3, !!(sta3 & M23_CG_APDMA));

	/*
	 * M29: on MT6771 these infra "CG" bits are *active high gated*: bit=1
	 * turns the module clock OFF.  Measured on the board: with
	 * IFR0[31]=1 a write to IER/TRI_LVL is dropped, with IFR0[31]=0 the
	 * same writes land (TRI_LVL 0x5a->0x18, IER 0->1).  The mt8183 gate
	 * driver that MT6771 inherits uses the opposite convention, so never
	 * call clk_enable() on these clocks and clear the gate here.
	 */
	writel(M23_CG_BTIF, m23_infra + M23_IFR2_CLR);
	wmb();

	sta2 = readl(m23_infra + M23_IFR2_STA);
	pr_info("m23-btif: infra after  sta2=0x%08x (BTIF bit31=%d, 0 = clock running)\\n",
		sta2, !!(sta2 & M23_CG_BTIF));
	return sta2 & M23_CG_BTIF ? -EIO : 0;'''

assert s.count(old_en)==1, s.count(old_en)
s=s.replace(old_en,new_en)

# CLR register for bank0
s=s.replace("#define M23_IFR2_SET		0x80",
            "#define M23_IFR2_SET		0x80\n#define M23_IFR2_CLR		0x84")

# m23_clk_disable: gate it back only on explicit request
s=s.replace('''int m23_clk_disable(void)
{
	/* Left running on purpose: CONNSYS keeps the BTIF link. */
	return 0;
}''','''int m23_clk_disable(void)
{
	/* Left running on purpose: CONNSYS keeps the BTIF link. */
	return 0;
}''')

# do NOT CCF-enable infra_btif (CCF enable writes the same bit = gates it)
s=s.replace('''	m23_ccf_one(np, "infra_btif", 26);
	m23_ccf_one(np, "infra_device_apc", 44);''','''	/*
	 * Do not enable infra_btif through CCF: clk_prepare_enable() writes
	 * SET, and on MT6771 SET means "gate the clock" (see m23_clk_enable).
	 */
	m23_ccf_one(np, "infra_device_apc", 44);''')

open(p,'w').write(s)
print("patched")

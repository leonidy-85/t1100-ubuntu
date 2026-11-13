#!/usr/bin/env python3
"""M28: enable infra_btif / infra_device_apc through CCF (parents included)."""
import sys

D = "/home/l/m23-btif/"


def sub(path, old, new, count=1):
    p = D + path
    s = open(p).read()
    n = s.count(old)
    if n != count:
        sys.exit("%s: expected %d, found %d" % (path, count, n))
    open(p, "w").write(s.replace(old, new))
    print("%s: patched" % path)


# --- header: declare
sub("m23_board.h", "int m23_irq_map(int spi);",
    "int m23_irq_map(int spi);\nvoid m23_ccf_enable(void);")

# --- board: CCF path + params
sub("m23_board.c",
    '#include <linux/module.h>\n#include <linux/platform_device.h>',
    '#include <linux/clk.h>\n#include <linux/clk-provider.h>\n'
    '#include <linux/module.h>\n#include <linux/of.h>\n'
    '#include <linux/platform_device.h>')

sub("m23_board.c",
    "int m23_devapc_open;",
    """/*
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

int m23_devapc_open;""")

sub("m23_board.c",
    "void m23_selftest_run(void)\n{",
    """static struct clk *m23_clk_by_id(struct device_node *np, unsigned int id)
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
		pr_err("m23-ccf: %s (id %u): no clock (%ld)\\n", what, id,
		       PTR_ERR(clk));
		return;
	}
	parent = clk_get_parent(clk);
	pr_info("m23-ccf: %s (id %u) before: rate=%lu parent=%s rate=%lu\\n",
		what, id, clk_get_rate(clk),
		parent ? __clk_get_name(parent) : "none",
		parent ? clk_get_rate(parent) : 0UL);

	ret = clk_prepare_enable(clk);
	pr_info("m23-ccf: %s clk_prepare_enable -> %d, rate=%lu\\n",
		what, ret, clk_get_rate(clk));
	parent = clk_get_parent(clk);
	if (parent)
		pr_info("m23-ccf: %s parent %s rate=%lu\\n", what,
			__clk_get_name(parent), clk_get_rate(parent));
}

void m23_ccf_enable(void)
{
	struct device_node *np;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt8183-infracfg");
	if (!np) {
		pr_err("m23-ccf: no mediatek,mt8183-infracfg node\\n");
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
""")

# --- driver: hoist hw_init dump to a callable place is not needed; keep as is
print("done")

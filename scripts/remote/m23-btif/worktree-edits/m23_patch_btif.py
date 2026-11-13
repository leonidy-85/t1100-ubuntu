#!/usr/bin/env python3
"""M23: make the public MTK BTIF driver bind without a device tree node.

Three edits, all in the out-of-tree copy under /home/l/m23-btif:

  btif_plat.c      bases/IRQ from module parameters, gates poked directly
  btif_dma_plat.c  TX/RX AP-DMA bases/IRQ from module parameters
  mtk_btif.c       register the platform device before the driver, selftest hook
"""
import re
import sys

D = "/home/l/m23-btif/"


def sub(path, old, new, count=1):
    p = D + path
    s = open(p).read()
    n = s.count(old)
    if n != count:
        sys.exit("%s: expected %d occurrence(s), found %d of:\n%s"
                 % (path, count, n, old[:200]))
    open(p, "w").write(s.replace(old, new))
    print("%s: patched (%d)" % (path, count))


# ---------------------------------------------------------------- btif_plat.c
sub("btif_plat.c",
    '#include "mtk_btif.h"\n\n#define BTIF_USER_ID "btif_driver"',
    '#include "mtk_btif.h"\n#include "m23_board.h"\n\n'
    '#define BTIF_USER_ID "btif_driver"')

# _btif_set_default_setting(): the no-DT fallback.
sub("btif_plat.c",
    """	} else {
		BTIF_ERR_FUNC("get btif device node fail\\n");
	}
""",
    """	} else {
		/*
		 * M23: no "mediatek,btif" node (mainline MT6771 DTS is not
		 * touched).  Use the stock DT values passed as module
		 * parameters instead.
		 */
		mtk_btif_info.p_irq->irq_id = m23_btif_irq;
		mtk_btif_info.p_irq->irq_flags = IRQF_TRIGGER_LOW;
		mtk_btif_info.base =
			(unsigned long)ioremap(m23_btif_pa, 0x1000);
		BTIF_INFO_FUNC("m23: btif irq(%d), register base(0x%lx)\\n",
			       mtk_btif_info.p_irq->irq_id,
			       (unsigned long)mtk_btif_info.base);
	}
""")

# prepare: no CCF clocks without a DT node.
sub("btif_plat.c",
    """		int i_ret = -1;

		clk_btif = devm_clk_get(&pdev->dev, "btifc");""",
    """		int i_ret = -1;

		/*
		 * M23: without a DT node there are no clock phandles, and
		 * MT6771 has no clk-mt6771 driver that would resolve
		 * "btifc"/"apdmac" anyway; the gates are driven directly in
		 * INFRACFG_AO by m23_clk_enable().
		 */
		if (!pdev->dev.of_node)
			return m23_clk_enable();

		clk_btif = devm_clk_get(&pdev->dev, "btifc");""")

# gate control through the direct poke.
# gate control through the direct poke (done with sed, see below)
sub("btif_plat.c",
    """	clk_unprepare(clk_btif);""",
    """	clk_unprepare(clk_btif);""")

# unprepare must tolerate NULL clocks.
sub("btif_plat.c",
    """	clk_unprepare(clk_btif);
	clk_unprepare(clk_btif_apdma);""",
    """	if (clk_btif)
		clk_unprepare(clk_btif);
	if (clk_btif_apdma)
		clk_unprepare(clk_btif_apdma);""")

# ------------------------------------------------------------ btif_dma_plat.c
sub("btif_dma_plat.c",
    '#include "btif_dma_priv.h"\n#include "mtk_btif.h"',
    '#include "btif_dma_priv.h"\n#include "mtk_btif.h"\n#include "m23_board.h"')

sub("btif_dma_plat.c",
    """		} else {
			BTIF_ERR_FUNC("get rx_dma device node fail\\n");
		}""",
    """		} else {
			/* M23: no DT node, use the stock DT values. */
			mtk_btif_rx_dma.p_irq->irq_id = m23_btif_rxdma_irq;
			mtk_btif_rx_dma.p_irq->irq_flags = IRQF_TRIGGER_LOW;
			mtk_btif_rx_dma.base =
				(unsigned long)ioremap(m23_btif_rxdma_pa, 0x100);
			BTIF_INFO_FUNC("m23: rx_dma irq(%d), base(0x%lx)\\n",
				       m23_btif_rxdma_irq,
				       (unsigned long)mtk_btif_rx_dma.base);
		}""")

sub("btif_dma_plat.c",
    """		} else {
			BTIF_ERR_FUNC("get tx_dma device node fail\\n");
		}""",
    """		} else {
			/* M23: no DT node, use the stock DT values. */
			mtk_btif_tx_dma.p_irq->irq_id = m23_btif_txdma_irq;
			mtk_btif_tx_dma.p_irq->irq_flags = IRQF_TRIGGER_LOW;
			mtk_btif_tx_dma.base =
				(unsigned long)ioremap(m23_btif_txdma_pa, 0x100);
			BTIF_INFO_FUNC("m23: tx_dma irq(%d), base(0x%lx)\\n",
				       m23_btif_txdma_irq,
				       (unsigned long)mtk_btif_tx_dma.base);
		}""")

# ----------------------------------------------------------------- mtk_btif.c
sub("mtk_btif.c",
    '#define DRV_NAME "mtk_btif"',
    '#define DRV_NAME "mtk_btif"\n\n#include "m23_board.h"')

sub("mtk_btif.c",
    """/*Platform Driver initialization*/
	i_ret = platform_driver_register(&mtk_btif_dev_drv);""",
    """/*
	 * M23: mainline MT6771 has no "mediatek,btif" node, so register a
	 * board platform device first; the driver then binds by name.
	 */
	i_ret = m23_board_register();
	if (i_ret)
		goto err_exit1;

/*Platform Driver initialization*/
	i_ret = platform_driver_register(&mtk_btif_dev_drv);""")

sub("mtk_btif.c",
    """#if BTIF_CDEV_SUPPORT
	btif_chrdev_init();
#endif

	return 0;

err_exit4:""",
    """#if BTIF_CDEV_SUPPORT
	btif_chrdev_init();
#endif

	m23_selftest_run();

	return 0;

err_exit4:""")

sub("mtk_btif.c",
    """	driver_remove_file(&mtk_btif_dev_drv.driver, &driver_attr_flag);
	platform_driver_unregister(&mtk_btif_dev_drv);
	BTIF_DBG_FUNC("--");
}""",
    """	driver_remove_file(&mtk_btif_dev_drv.driver, &driver_attr_flag);
	platform_driver_unregister(&mtk_btif_dev_drv);
	m23_board_unregister();
	BTIF_DBG_FUNC("--");
}""")

#!/usr/bin/env python3
"""M23 part 2: unprepare guard + btif_dma_plat.c + mtk_btif.c hooks."""
import sys

D = "/home/l/m23-btif/"


def sub(path, old, new, count=1):
    p = D + path
    s = open(p).read()
    n = s.count(old)
    if n != count:
        sys.exit("%s: expected %d, found %d of:\n%s" % (path, count, n, old[:200]))
    open(p, "w").write(s.replace(old, new))
    print("%s: patched (%d)" % (path, count))


sub("btif_plat.c",
    """	clk_unprepare(clk_btif);
	clk_unprepare(clk_btif_apdma);""",
    """	/* M23: both are NULL when the driver bound without a DT node. */
	if (clk_btif)
		clk_unprepare(clk_btif);
	if (clk_btif_apdma)
		clk_unprepare(clk_btif_apdma);""")

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

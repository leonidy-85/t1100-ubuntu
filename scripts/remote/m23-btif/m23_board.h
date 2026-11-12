/* SPDX-License-Identifier: GPL-2.0 */
/*
 * MT6771 (Fplus T1100) board glue for the public MediaTek BTIF driver.
 * See m23_board.c for the rationale.
 */
#ifndef __M23_BOARD_H_
#define __M23_BOARD_H_

extern int m23_btif_pa;
extern int m23_btif_txdma_pa;
extern int m23_btif_rxdma_pa;
extern int m23_btif_irq;
extern int m23_btif_txdma_irq;
extern int m23_btif_rxdma_irq;

int m23_board_register(void);
void m23_board_unregister(void);
int m23_irq_map(int spi);
int m23_clk_enable(void);
int m23_clk_disable(void);
void m23_btif_dump(const char *tag);
void m23_selftest_run(void);

#endif /* __M23_BOARD_H_ */

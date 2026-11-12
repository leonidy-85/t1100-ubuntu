# Out-of-tree wrapper for the public MTK BTIF driver (M23 milestone).
obj-m += mtk_btif_drv.o
mtk_btif_drv-y := mtk_btif.o mtk_btif_exp.o btif_dma_plat.o btif_plat.o m23_board.o
ccflags-y += -I$(src)/inc -I$(src)/plat_inc
ccflags-y += -DBTIF_DBG_SUPPORT=0
# M23: PIO first (no AP-DMA dependency); override with -DENABLE_BTIF_*_DMA=1
ccflags-y += -DENABLE_BTIF_TX_DMA=0 -DENABLE_BTIF_RX_DMA=0
ccflags-y += -Wno-missing-prototypes -Wno-missing-declarations -Wno-enum-conversion

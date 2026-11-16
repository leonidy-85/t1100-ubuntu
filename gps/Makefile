obj-m += gps_drv.o

gps_drv-objs := stp_chrdev_gps.o fw_log_gps.o

ccflags-y += -I$(src)
ccflags-y += -I$(src)/compat
ccflags-y += -DMTK_WCN_WMT_STP_EXP_SYMBOL_ABSTRACT
ccflags-y += -DCONFIG_MTK_WCN_ARM64
ccflags-y += -DWMT_IDC_SUPPORT=0
ccflags-y += -DWMT_CREATE_NODE_DYNAMIC=1
ccflags-y += -DREMOVE_MK_NODE=0

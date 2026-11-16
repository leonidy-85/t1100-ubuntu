// SPDX-License-Identifier: GPL-2.0
/*
 * t1100_bt_probe — минимальный пробник BT-транспорта MT6631 (CONSYS_6771)
 * для Fplus T1100.
 *
 * Цель: проверить, что после WMT func_on(BT) канал STP type 0 работает и
 * контроллер отвечает на HCI Reset. Полноценный HCI-драйвер будет отдельно.
 *
 * В bluez-режиме STP не кладёт BT-пакеты в rx-очередь, а отдаёт их через
 * зарегистрированный if_rx callback — поэтому регистрируем и его.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/delay.h>
#include <linux/workqueue.h>
#include <linux/slab.h>
#include <linux/spinlock.h>

#define BT_TASK_INDX	0
#define BT_STP_TYPE	0
#define WMTDRV_TYPE_BT	0
#define BT_RX_MAX	2048

extern int mtk_wcn_wmt_func_on(int type);
extern int mtk_wcn_wmt_func_off(int type);
extern int mtk_wcn_stp_register_event_cb(int type, void (*func)(void));
extern int mtk_wcn_stp_send_data(const unsigned char *buf,
				 const unsigned int len,
				 const unsigned char type);
extern int mtk_wcn_stp_receive_data(unsigned char *buf, unsigned int len,
				    unsigned char type);
extern int mtk_wcn_stp_is_ready(void);
extern void mtk_wcn_stp_set_bluez(int flag);
extern int mtk_wcn_stp_register_if_rx(void (*func)(const unsigned char *data,
						   int size));

static struct work_struct rx_work;
static struct delayed_work reset_work;
static unsigned int rx_frames;
static unsigned int rx_bytes;
static unsigned int evt_calls;
static unsigned char rx_buf[BT_RX_MAX];
static unsigned int rx_len;
static DEFINE_SPINLOCK(rx_lock);

static void bt_probe_rx_work(struct work_struct *work)
{
	unsigned long flags;
	unsigned int n;

	spin_lock_irqsave(&rx_lock, flags);
	n = rx_len;
	rx_len = 0;
	spin_unlock_irqrestore(&rx_lock, flags);

	if (!n)
		return;
	print_hex_dump(KERN_INFO, "t1100-bt rx: ", DUMP_PREFIX_OFFSET,
		       16, 1, rx_buf, n, false);
}

/* STP отдаёт BT-пакеты сюда напрямую (bluez-режим) */
static void bt_probe_if_rx(const unsigned char *data, int size)
{
	unsigned long flags;

	rx_frames++;
	rx_bytes += size;

	spin_lock_irqsave(&rx_lock, flags);
	if (size > 0 && size <= BT_RX_MAX) {
		memcpy(rx_buf, data, size);
		rx_len = size;
	}
	spin_unlock_irqrestore(&rx_lock, flags);

	schedule_work(&rx_work);
}

static void bt_probe_rx_cb(void)
{
	unsigned char buf[600];
	int n;

	evt_calls++;
	while ((n = mtk_wcn_stp_receive_data(buf, sizeof(buf), BT_STP_TYPE)) > 0) {
		rx_frames++;
		rx_bytes += n;
		print_hex_dump(KERN_INFO, "t1100-bt queued: ", DUMP_PREFIX_OFFSET,
			       16, 1, buf, n, false);
	}
}

static void bt_probe_reset_work(struct work_struct *work)
{
	/* HCI Reset: opcode 0x0c03, len 0 */
	static const unsigned char hci_reset[] = { 0x01, 0x03, 0x0c, 0x00 };
	int ret;

	pr_info("t1100-bt: stp ready=%d, sending HCI Reset\n",
		mtk_wcn_stp_is_ready());
	ret = mtk_wcn_stp_send_data(hci_reset, sizeof(hci_reset), BT_STP_TYPE);
	pr_info("t1100-bt: HCI Reset send -> %d\n", ret);
}

static int __init bt_probe_init(void)
{
	int ret;

	pr_info("t1100-bt: probing BT transport\n");

	INIT_WORK(&rx_work, bt_probe_rx_work);
	INIT_DELAYED_WORK(&reset_work, bt_probe_reset_work);

	mtk_wcn_stp_set_bluez(1);
	ret = mtk_wcn_stp_register_if_rx(bt_probe_if_rx);
	pr_info("t1100-bt: register_if_rx -> %d\n", ret);

	ret = mtk_wcn_stp_register_event_cb(BT_TASK_INDX, bt_probe_rx_cb);
	pr_info("t1100-bt: register_event_cb -> %d\n", ret);

	ret = mtk_wcn_wmt_func_on(WMTDRV_TYPE_BT);
	pr_info("t1100-bt: wmt func_on(BT) -> %d\n", ret);

	schedule_delayed_work(&reset_work, msecs_to_jiffies(300));

	return 0;
}

static void __exit bt_probe_exit(void)
{
	cancel_delayed_work_sync(&reset_work);
	cancel_work_sync(&rx_work);
	mtk_wcn_stp_register_if_rx(NULL);
	mtk_wcn_stp_register_event_cb(BT_TASK_INDX, NULL);
	mtk_wcn_wmt_func_off(WMTDRV_TYPE_BT);
	pr_info("t1100-bt: removed, rx_frames=%u rx_bytes=%u evt_calls=%u\n",
		rx_frames, rx_bytes, evt_calls);
}

module_init(bt_probe_init);
module_exit(bt_probe_exit);

MODULE_DESCRIPTION("T1100 MT6631 BT STP transport probe");
MODULE_LICENSE("GPL");

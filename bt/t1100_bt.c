// SPDX-License-Identifier: GPL-2.0
/*
 * t1100_bt — HCI-драйвер для BT-контроллера MT6631 (CONSYS_6771)
 * на Fplus T1100.
 *
 * Транспорт: WMT/STP поверх BTIF (в wmt_drv), канал STP type 0.
 * В bluez-режиме STP отдаёт принятые кадры через if_rx callback,
 * а отправка идёт через mtk_wcn_stp_send_data().
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/skbuff.h>
#include <net/bluetooth/bluetooth.h>
#include <net/bluetooth/hci_core.h>

#define BT_STP_TYPE	0
#define WMTDRV_TYPE_BT	0

extern int mtk_wcn_wmt_func_on(int type);
extern int mtk_wcn_wmt_func_off(int type);
extern int mtk_wcn_stp_register_event_cb(int type, void (*func)(void));
extern int mtk_wcn_stp_send_data(const unsigned char *buf,
				 const unsigned int len,
				 const unsigned char type);
extern void mtk_wcn_stp_set_bluez(int flag);
extern int mtk_wcn_stp_register_if_rx(void (*func)(const unsigned char *data,
						   int size));

static struct hci_dev *t1100_hdev;
static bool t1100_bt_powered;

static void t1100_bt_if_rx(const unsigned char *data, int size)
{
	struct sk_buff *skb;
	u8 type;

	if (!t1100_hdev || size < 2)
		return;

	type = data[0];
	skb = bt_skb_alloc(size - 1, GFP_ATOMIC);
	if (!skb)
		return;

	memcpy(skb_put(skb, size - 1), data + 1, size - 1);
	hci_skb_pkt_type(skb) = type;
	hci_recv_frame(t1100_hdev, skb);
}

static void t1100_bt_event_cb(void)
{
	/* в bluez-режиме данные приходят через if_rx; событие — просто сигнал */
}

static int t1100_bt_open(struct hci_dev *hdev)
{
	int ret;

	pr_info("t1100-bt: open\n");

	mtk_wcn_stp_set_bluez(1);
	ret = mtk_wcn_stp_register_if_rx(t1100_bt_if_rx);
	if (ret)
		pr_warn("t1100-bt: register_if_rx -> %d\n", ret);
	mtk_wcn_stp_register_event_cb(BT_STP_TYPE, t1100_bt_event_cb);

	ret = mtk_wcn_wmt_func_on(WMTDRV_TYPE_BT);
	pr_info("t1100-bt: wmt func_on(BT) -> %d\n", ret);
	if (!ret) {
		mtk_wcn_stp_register_if_rx(NULL);
		return -EIO;
	}

	t1100_bt_powered = true;
	set_bit(HCI_RUNNING, &hdev->flags);

	return 0;
}

static int t1100_bt_close(struct hci_dev *hdev)
{
	pr_info("t1100-bt: close\n");

	clear_bit(HCI_RUNNING, &hdev->flags);
	mtk_wcn_stp_register_if_rx(NULL);
	mtk_wcn_stp_register_event_cb(BT_STP_TYPE, NULL);
	if (t1100_bt_powered) {
		mtk_wcn_wmt_func_off(WMTDRV_TYPE_BT);
		t1100_bt_powered = false;
	}

	return 0;
}

static int t1100_bt_send(struct hci_dev *hdev, struct sk_buff *skb)
{
	int ret;

	if (!t1100_bt_powered) {
		kfree_skb(skb);
		return -ENODEV;
	}

	/* STP ждёт HCI-пакет вместе с байтом типа */
	skb_push(skb, 1);
	skb->data[0] = hci_skb_pkt_type(skb);

	ret = mtk_wcn_stp_send_data(skb->data, skb->len, BT_STP_TYPE);
	kfree_skb(skb);

	if (ret < 0)
		return ret;

	return 0;
}

static int __init t1100_bt_init(void)
{
	int ret;

	t1100_hdev = hci_alloc_dev();
	if (!t1100_hdev)
		return -ENOMEM;

	t1100_hdev->bus = HCI_VIRTUAL;
	t1100_hdev->open = t1100_bt_open;
	t1100_hdev->close = t1100_bt_close;
	t1100_hdev->send = t1100_bt_send;
	set_bit(HCI_QUIRK_BROKEN_ERR_DATA_REPORTING, &t1100_hdev->quirks);

	ret = hci_register_dev(t1100_hdev);
	if (ret) {
		hci_free_dev(t1100_hdev);
		t1100_hdev = NULL;
		return ret;
	}

	pr_info("t1100-bt: hci registered as hci%d\n", t1100_hdev->id);
	return 0;
}

static void __exit t1100_bt_exit(void)
{
	if (t1100_hdev) {
		hci_unregister_dev(t1100_hdev);
		hci_free_dev(t1100_hdev);
		t1100_hdev = NULL;
	}
}

module_init(t1100_bt_init);
module_exit(t1100_bt_exit);

MODULE_DESCRIPTION("T1100 MT6631 HCI over WMT/STP");
MODULE_LICENSE("GPL");

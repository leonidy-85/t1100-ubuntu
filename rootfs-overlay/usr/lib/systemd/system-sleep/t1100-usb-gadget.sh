#!/bin/sh
# The MTU3 gadget rejects system suspend while the RNDIS gadget is connected
# (-EBUSY).  Detach the UDC for the sleep window and restore it on resume.
G=/sys/kernel/config/usb_gadget/t1100

case "$1" in
pre)
	if [ -r "$G/UDC" ] && [ -n "$(cat "$G/UDC")" ]; then
		cat "$G/UDC" > /run/t1100-udc
		echo "" > "$G/UDC"
	fi
	;;
post)
	if [ -s /run/t1100-udc ]; then
		echo "$(cat /run/t1100-udc)" > "$G/UDC"
		rm -f /run/t1100-udc
	fi
	;;
esac

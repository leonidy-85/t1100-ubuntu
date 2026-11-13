#!/bin/sh
# Разложить собранные Wi-Fi-модули на планшет и (опционально) загрузить стек.
#
#   tools/host/deploy-wifi.sh            # только скопировать + depmod
#   tools/host/deploy-wifi.sh --load     # ещё и modprobe wmt_drv / wlan_drv_gen3
#
# Модули берутся из build/wifi/{common,wlan}/*.ko (их кладёт туда
# scripts/build-wifi-remote.sh) и build/remote/modules/*.ko (ядерные
# cfg80211/mac80211/rfkill, их собирает scripts/build-kernel-remote.sh --modules).
#
# Почему не rootfs-overlay: .ko привязаны к точному релизу ядра (vermagic), в
# git их не кладём, а на устройстве они живут в /lib/modules/$(uname -r)/updates/wifi.
set -eu
HOST=${HOST:-10.42.66.66}
LOAD=0
[ "${1:-}" = "--load" ] && LOAD=1
REPO=$(cd "$(dirname "$0")/../.." && pwd)
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$HOST"
SCP="scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

REL=$($SSH 'uname -r')
echo "== планшет: релиз $REL"

for f in "$REPO"/build/wifi/common/wmt_drv.ko "$REPO"/build/wifi/wlan/wlan_drv_gen3.ko; do
	[ -f "$f" ] || { echo "нет $f — сначала scripts/build-wifi-remote.sh" >&2; exit 1; }
done

$SSH "mkdir -p /lib/modules/$REL/updates/wifi /lib/modules/$REL/kernel/net/wireless \
	/lib/modules/$REL/kernel/net/mac80211 /lib/modules/$REL/kernel/net/rfkill \
	/lib/modules/$REL/kernel/lib/crypto"

echo "== вендорские модули -> /lib/modules/$REL/updates/wifi"
$SCP "$REPO"/build/wifi/common/wmt_drv.ko "$REPO"/build/wifi/wlan/wlan_drv_gen3.ko \
	"root@$HOST:/lib/modules/$REL/updates/wifi/"

if [ -f "$REPO/build/remote/modules/cfg80211.ko" ]; then
	echo "== ядерные модули (cfg80211/mac80211/rfkill/libarc4)"
	$SCP "$REPO"/build/remote/modules/cfg80211.ko "root@$HOST:/lib/modules/$REL/kernel/net/wireless/"
	$SCP "$REPO"/build/remote/modules/mac80211.ko "root@$HOST:/lib/modules/$REL/kernel/net/mac80211/"
	$SCP "$REPO"/build/remote/modules/rfkill.ko "root@$HOST:/lib/modules/$REL/kernel/net/rfkill/"
	[ -f "$REPO/build/remote/modules/libarc4.ko" ] && \
		$SCP "$REPO"/build/remote/modules/libarc4.ko "root@$HOST:/lib/modules/$REL/kernel/lib/crypto/"
fi

echo "== depmod -a"
$SSH "depmod -a $REL && echo DEPMOD_OK"

if [ "$LOAD" -eq 1 ]; then
	echo "== modprobe wmt_drv"
	$SSH 'modprobe -v wmt_drv 2>&1; sleep 2; dmesg | grep -iE "wmt|consys" | tail -n 40'
	echo "== modprobe wlan_drv_gen3"
	$SSH 'modprobe -v wlan_drv_gen3 2>&1; sleep 1; dmesg | tail -n 30'
fi

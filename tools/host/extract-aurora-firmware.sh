#!/bin/sh
# Extract the MT6631 (CONSYS_6771) firmware blobs for the T1100 from the
# Aurora vendor RPM into a local directory, then push them to the tablet.
#
# Why this way: the blobs are proprietary, so they are not kept in this
# repository. They do exist inside the Aurora adaptation package that ships
# the vendor partition image:
#
#   offline-repos/5.2.1.200/adaptation/mashtab_t1/
#       droid-system-vendor-mashtab_t1-<ver>.noarch.rpm   (147 MB)
#         ./vendor/firmware/WIFI_RAM_CODE_6759             480704 B  (WLAN fw)
#         ./vendor/firmware/soc3_0_ram_mcu_e1_hdr.bin       165344 B  (MCU rom patch)
#         ./vendor/firmware/soc3_0_ram_bt_1_1_hdr.bin       671988 B  (BT fw)
#         ./vendor/firmware/WMT_SOC.cfg                        119 B  (text cfg)
#         ./vendor/firmware/BT_FW.cfg                          410 B  (text cfg)
#         ./vendor/firmware/ROMv4_be_patch_1_{0,1}_hdr.bin           (rom patch v4)
#
# The three soc3_0_ram_mcu_*_hdr.bin files are byte identical
# (md5 009c135ece1838e1955435cb35d0d4a6), so the eco suffix in the name does
# not select different content; the port reads ..._e1_hdr.bin.
#
# Usage:
#   tools/host/extract-aurora-firmware.sh [--deploy HOST]
#
# Without --deploy it only fills $OUT (default build/firmware-aurora).
set -eu

REPO_SRC=${REPO_SRC:-/home/leo/Aurora_All/offline-repos}
VER=${VER:-5.2.1.200}
OUT=${OUT:-build/firmware-aurora}
DEPLOY_HOST=

while [ $# -gt 0 ]; do
	case "$1" in
	--deploy) DEPLOY_HOST=$2; shift 2 ;;
	--deploy=*) DEPLOY_HOST=${1#--deploy=}; shift ;;
	*) echo "usage: $0 [--deploy HOST]" >&2; exit 2 ;;
	esac
done

RPM=$(ls "$REPO_SRC/$VER"/adaptation/mashtab_t1/droid-system-vendor-mashtab_t1-*.noarch.rpm 2>/dev/null | head -1)
[ -n "$RPM" ] || { echo "vendor rpm not found under $REPO_SRC/$VER" >&2; exit 1; }
echo "rpm: $RPM"

mkdir -p "$OUT"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# cpio wants the leading "./" forms exactly as stored in the package
( cd "$WORK" && rpm2cpio "$RPM" | cpio -idm --quiet \
	./vendor/firmware/WIFI_RAM_CODE_6759 \
	./vendor/firmware/soc3_0_ram_mcu_e1_hdr.bin \
	./vendor/firmware/soc3_0_ram_bt_1_1_hdr.bin \
	./vendor/firmware/WMT_SOC.cfg \
	./vendor/firmware/BT_FW.cfg \
	./vendor/firmware/ROMv4_be_patch_1_0_hdr.bin \
	./vendor/firmware/ROMv4_be_patch_1_1_hdr.bin )

cp "$WORK"/vendor/firmware/* "$OUT"/
( cd "$OUT" && md5sum * )

if [ -n "$DEPLOY_HOST" ]; then
	echo "deploying to $DEPLOY_HOST:/lib/firmware"
	scp -q "$OUT"/WIFI_RAM_CODE_6759 "$OUT"/soc3_0_ram_mcu_e1_hdr.bin \
		"$OUT"/WMT_SOC.cfg "$OUT"/BT_FW.cfg \
		"$DEPLOY_HOST:/lib/firmware/"
	echo "done"
fi

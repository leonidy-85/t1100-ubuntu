#!/bin/sh
# consys-spm-seq.sh — walk the MT6771 CONNSYS power domain from the AP side with
# the SPM register sequence of the vendor driver, without touching the driver.
#
# Runs ON the tablet (needs /usr/local/bin/mempeek, /dev/mem, root).
#
# Why this exists: the vendor consys power-on has two implementations selected
# by CONSYS_PWR_ON_OFF_API_AVAILABLE (common_main/platform/include/mt6771.h):
#
#   =1  clk_prepare_enable(clk_scp_conn_main)   -- needs the vendor "conn" clock
#       from its own "mediatek,scpsys" clock provider, which mainline does not
#       have (devm_clk_get_optional() returns NULL, and clk_enable(NULL) is a
#       successful no-op), so nothing at all happens.
#   =0  the raw SPM sequence below, copied from mt6771.c:consys_hw_power_ctrl().
#
# This script replays the =0 variant so its effect can be measured with nothing
# but mempeek.  Register offsets/bits: vendor common_main/platform/include/
# mt6771.h (SPM base 0x10006000, infracfg 0x10001000, AP_RGU 0x10007000).
#
#   T1   = 0x1000632c  SPM CONN_TOP1_PWR_CTRL   bit0 rst_b, bit1 iso_en,
#                                               bit2 pwr_on, bit3 pwr_on_s,
#                                               bit4 clk_dis, bit8 sram_pd,
#                                               bit30 top2 ack
#   ACK  = 0x10006180  PWR_CONN_ACK            bit1
#   ACKS = 0x10006184                          bit1
#   PROT = 0x100012a4  TOPAXI_PROT_EN          bit13|bit14 = CONN bus protect
#   RGU  = 0x10007018  CONN CPU SW reset       bit12 + key 0x88 in [31:24]
#
# usage: consys-spm-seq.sh [dump|on|off]

MP=${MP:-/usr/local/bin/mempeek}
T1=0x1000632c
ACK=0x10006180
ACKS=0x10006184
PROT=0x100012a4
RGU=0x10007018
CHIPID=0x18070008
CPUPCR=0x18070160
WFDMA=0x180f0000

rd() { $MP --mmap "$1" 1 | sed 's/.*=//'; }
wr() { $MP --write "$1" "$2" >/dev/null; }
poke() { $MP --poke "$1" "$2" "$3" >/dev/null; }

poll_bit() {   # poll_bit <addr> <bit> <tries> -> 0 if the bit came up
	a=$1; b=$2; n=$3
	m=$((1 << b))
	while [ "$n" -gt 0 ]; do
		v=$(rd "$a")
		[ $(( v & m )) -ne 0 ] && return 0
		sleep 0.001 2>/dev/null || sleep 1
		n=$((n - 1))
	done
	return 1
}

dump() {
	printf 'T1   %s = %s\n'   $T1   "$(rd $T1)"
	printf 'ACK  %s = %s\n'   $ACK  "$(rd $ACK)"
	printf 'ACKS %s = %s\n'   $ACKS "$(rd $ACKS)"
	printf 'PROT %s = %s\n'   $PROT "$(rd $PROT)"
	printf 'RGU  %s = %s\n'   $RGU  "$(rd $RGU)"
	printf 'CHIPID %s = %s\n' $CHIPID "$(rd $CHIPID)"
	printf 'CPUPCR %s = %s\n' $CPUPCR "$(rd $CPUPCR)"
	printf 'WFDMA  %s = %s %s\n' $WFDMA "$(rd $WFDMA)" "$(rd $((WFDMA + 4)))"
}

on() {
	echo "== before"; dump
	# 2./3. power on CONN_TOP1 (hardware handshake, then the shadow bit)
	poke $T1 0x0c 0xffffffff
	echo "T1 after pwr_on: $(rd $T1)"
	poll_bit $ACK 1 5000 || echo "WARN: PWR_CONN_ACK bit1 did not come up"
	poll_bit $ACKS 1 5000 || echo "WARN: PWR_CONN_ACK_S bit1 did not come up"
	echo "ACK=$(rd $ACK) ACKS=$(rd $ACKS)"
	# 6. conn_clk_dis = 0
	poke $T1 0x0 0xffffffef
	# 7. 1 us
	# 9. release isolation, 10. release CPU reset
	poke $T1 0x1 0xfffffffd
	# disable CONN AXI bus protect (bits 13,14 of 0x100012a4)
	poke $PROT 0x0 0xffff9fff
	# top2 ack lives in T1[30]
	poll_bit $T1 30 5000 || echo "WARN: CONN_TOP2 ack (T1[30]) did not come up"
	# ROM patch deselect value the vendor driver writes right after chip id
	wr 0x18070600 0x1702a4
	echo "== after"; dump
}

off() {
	# reverse order of consys_hw_power_ctrl(enable=0)
	poke $PROT 0x6000 0xffffffff
	poke $T1 0x0 0xfffffffe        # rst_b = 0
	poke $T1 0x2 0xffffffff        # iso_en = 1
	poke $T1 0x10 0xffffffff       # clk_dis = 1
	poke $T1 0x0 0xfffffff3        # pwr_on / pwr_on_s = 0
	echo "== after off"; dump
}

case "$1" in
	""|dump) dump ;;
	on)  on ;;
	off) off ;;
	*) echo "usage: $0 [dump|on|off]" >&2; exit 2 ;;
esac

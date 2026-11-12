#!/bin/sh
# T1100 M24: is the BTIF register window writable at all?
#
# The M23 result ("STP packet leaves, no answer") assumed writes to the BTIF
# window land. They do not: every register reads back its reset/LK value after
# a write, from the driver (writel) and from /dev/mem alike. This script proves
# it and records the control cases, so the state of the block can be compared
# between boots (or against the stock kernel).
#
# Usage on the device:  sh btif-probe.sh > /root/btif-probe.txt
# Needs /root/mempeek2 (tools/mempeek, static aarch64, --mmap/--write).
# Read/write only to BTIF, irtx, eem_fsm, AP-DMA windows and the two INFRACFG
# gate registers -- nothing is enabled or reset by this script.

M=${MEMPEEK:-/root/mempeek2}
rd() { $M --mmap "$1" 1 | sed 's/.*=//'; }
wr() { $M --write "$1" "$2" >/dev/null 2>&1; }

echo "== uname: $(uname -r)"
echo "== BTIF reset values (regs 0x00..0x6c, 4B step)"
a=$((0x1100c000)); end=$((0x1100c06c))
while [ "$a" -le "$end" ]; do
	printf "BTIF[0x%03x] = %s\n" $((a - 0x1100c000)) "$(rd $(printf 0x%x "$a"))"
	a=$((a + 4))
done

echo "== write test: does any BTIF register take a value?"
for off in 0x004 0x054 0x060 0x068; do
	a=$((0x1100c000 + off))
	before=$(rd $a)
	wr $a 0xa5a5a5a5
	after=$(rd $a)
	printf "BTIF[0x%03x] before=%s wrote=0xa5a5a5a5 after=%s %s\n" \
		$off "$before" "$after" \
		"$([ "$before" = "$after" ] && echo WRITE-DROPPED || echo WRITE-LANDED)"
done

echo "== TX FIFO test: 40 THR writes must drop THRE (LSR bit5) if writes land"
i=0
while [ $i -lt 40 ]; do wr 0x1100c000 0x55; i=$((i + 1)); done
echo "LSR after 40 THR writes = $(rd 0x1100c014)  (0x60 = THRE still set)"

echo "== controls (same access path, other blocks)"
for pair in "irtx:0x1100d000" "eem_fsm:0x1100b000" "btif_txdma:0x11000a8c"; do
	name=${pair%%:*}
	a=${pair##*:}
	before=$(rd $a)
	wr $a 0x00000004
	after=$(rd $a)
	printf "%-14s %s before=%s after=%s\n" "$name" "$a" "$before" "$after"
done

echo "== BTIF clock gate (INFRACFG_AO IFR0, clk-mt6771.c:1173, bit 31)"
echo "sta 0x10001090 = $(rd 0x10001090)   (bit31 = infra_btif)"
echo "== BTIF/APDMA SW reset banks (expect 0)"
for a in 0x10001120 0x10001130 0x10001140 0x10001150; do
	echo "$a = $(rd $a)"
done
# gate control: clear, read back, restore (clk-mt6771.c: bit31 of IFR0)
echo "== infracfg gate write control (set 0x80 / clr 0x84 / sta 0x90, bit31)"
echo "sta before      = $(rd 0x10001090)"
wr 0x10001084 0x80000000
echo "sta after CLR31 = $(rd 0x10001090)"
wr 0x10001080 0x80000000
echo "sta after SET31 = $(rd 0x10001090)"
echo "== AXI bus protect"
echo "PROTECTEN 0x100012a0 = $(rd 0x100012a0)"
echo "PROTECTSTA1 0x100012a8 = $(rd 0x100012a8)"
echo "== CONSYS (is the chip up? cpupcr 0x18070160, chipid 0x18070008)"
echo "chipid=$(rd 0x18070008) cpupcr=$(rd 0x18070160)"

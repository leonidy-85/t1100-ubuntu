#!/bin/sh
# efuse-thermal-decode.sh — найти раскладку thermal-калибровки MT6771 в efuse.
#
# Читает efuse через nvmem-устройство mtk-efuse (read-only) и проверяет каждое
# 32-битное слово как начало трёхсловного блока калибровки в раскладке
# MEDIATEK_THERMAL_V1 (mainline auxadc_thermal.c), которая бит-в-бит совпадает
# с вендорской для MT6771 (mtk_tc.c: ВСЕГДА buf0 = слово 100 = адрес 0x190,
# buf1 = слово 101 = 0x194, buf2 = слово 102 = 0x198; проверка —
# offset = 4 * devinfo_index).
#
# Критерии кандидата (вендорская валидация mtk_tc.c):
#   buf0 bit0 (ADC_CALI_EN) = 1
#   degc_cali 1..63, adc_ge 265..758, каждый vts 0..484
#
# Запуск на планшете:  sh /usr/local/bin/efuse-thermal-decode.sh
# (или из recovery: nvmem-устройства там нет, нужна загруженная система)

set -e

DEV=""
for f in /sys/bus/nvmem/devices/*/nvmem; do
	[ -r "$f" ] || continue
	case "$f" in
	*efuse*) DEV="$f"; break ;;
	esac
	[ -z "$DEV" ] && DEV="$f"
done

if [ -z "$DEV" ]; then
	echo "efuse: nvmem-устройство не найдено" >&2
	exit 1
fi
echo "efuse: $DEV ($(cat "$DEV" | wc -c) байт)"

od -An -v -tu4 -w4 "$DEV" | awk '
function bit(x, off, mask) { return int(x / 2 ^ off) % 2 ^ mask }
{
	for (i = 1; i <= NF; i++) w[n++] = $i
}
END {
	printf "%-8s %-6s %-6s %-5s %-5s %-4s %-4s %-4s %-4s %-4s %-4s %-4s %-4s\n",
		"offset", "valid", "degc", "adcge", "adcoe", "vts1", "vts2", "vts3",
		"vts4", "vts5", "vtsABB", "slope", "sign"
	found = 0
	for (i = 0; i + 2 < n; i++) {
		a = w[i]; b = w[i + 1]; c = w[i + 2]
		valid = bit(a, 0, 1)
		degc = bit(a, 1, 6)
		adcge = bit(b, 22, 10)
		if (!valid) continue
		if (degc < 1 || degc > 63) continue
		if (adcge < 265 || adcge > 758) continue
		v1 = bit(a, 17, 9); v2 = bit(a, 8, 9); v3 = bit(b, 0, 9)
		v4 = bit(c, 23, 9); v5 = bit(c, 5, 9); va = bit(c, 14, 9)
		if (v1 > 484 || v2 > 484 || v3 > 484 || v4 > 484 || v5 > 484 || va > 484)
			continue
		printf "0x%03x%s %-6d %-6d %-6d %-5d %-5d %-4d %-4d %-4d %-4d %-4d %-4d %-4d\n",
			i * 4, (i * 4 == 400 ? " *" : "  "), valid, degc, adcge,
			bit(b, 12, 10), v1, v2, v3, v4, v5, va,
			bit(a, 26, 6), bit(a, 7, 1)
		found++
		if (i * 4 == 400) {
			printf "\n  MT6771 (слово 100 = 0x190), разбор по полям:\n"
			printf "    buf0 (0x190) = 0x%08x  degc_cali=%d adc_cali_en=%d slope=%d sign=%d\n",
				a, degc, valid, bit(a, 26, 6), bit(a, 7, 1)
			printf "    buf1 (0x194) = 0x%08x  adc_ge=%d adc_oe=%d vts3=%d tsmc_id=%d\n",
				b, adcge, bit(b, 12, 10), v3, bit(b, 9, 1))
			printf "    buf2 (0x198) = 0x%08x  vts4=%d vts5=%d vtsABB=%d\n",
				c, v4, v5, va)
		}
	}
	printf "\nкандидатов: %d\n", found
	if (found == 0)
		printf "ВНИМАНИЕ: ни один блок не прошёл валидацию — искать другой чип/индекс\n"
}'

echo
echo "== сырые слова вокруг 0x180 (MT8183) и 0x190 (ожидаемый MT6771):"
dd if="$DEV" bs=1 skip=384 count=32 2>/dev/null | od -Ad -tx4

/* Test payload: entry point at file offset 0x80000 instead of 0.
 *
 * Hypothesis: MTK `lk` on this board jumps to (load address + 0x80000) -- the
 * text_offset convention of the stock 4.14 kernel -- regardless of what the
 * Image header says. Every image we built so far has its entry at offset 0,
 * which would make lk start executing garbage, crash and reset.
 *
 * This image is padded to 0x80000 and puts the real code there. It stops the
 * TOPRGU watchdog, drops a marker into the MTK ram_console DRAM area, then
 * halts. A hang (no reset loop) proves the hypothesis.
 */
	.section .text
	.global _start
_start:
	b	header_end		/* entry at offset 0, unused in this test */
	.word	0
	.quad	0x80000
	.quad	0			/* image_size: patched by build.sh */
	.quad	0xa
	.quad	0, 0, 0
	.ascii	"ARM\x64"
	.word	0
header_end:

	/* pad up to 0x80000 */
	.fill	0x80000 - (. - _start), 1, 0

real:
	adr	x19, real

	/* marker: 0x54400000 = "T1100PLD" + runtime address */
	movz	x20, #0x0000
	movk	x20, #0x5440, lsl #16
	movz	w21, #0x3154
	movk	w21, #0x3031, lsl #16
	str	w21, [x20]
	movz	w22, #0x4c50
	movk	w22, #0x2144, lsl #16
	str	w22, [x20, #4]
	str	x19, [x20, #8]

	/* same marker into SRAM ram_console (0x11d000 + 0x400) */
	movz	x23, #0xd000
	movk	x23, #0x0011, lsl #16
	add	x23, x23, #0x400
	str	w21, [x23]
	str	w22, [x23, #4]
	str	x19, [x23, #8]

	/* stop TOPRGU */
	movz	x21, #0x7000
	movk	x21, #0x1000, lsl #16
	ldr	w22, [x21]
	and	w22, w22, #0xfffffffe
	mov	w23, #0x2200
	orr	w22, w22, w23, lsl #16
	str	w22, [x21]

	dsb	sy
loop:
	wfi
	b	loop

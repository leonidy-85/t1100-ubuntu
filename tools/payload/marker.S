/* arm64 payload: publish "I ran, at address X" into the MTK persistent
 * ram_console and halt.
 *
 * Motivation: no UART, display path unproven. The ram_console/ramoops region
 * at 0x54410000 is not cleared by lk or by a later kernel boot (proven: stock
 * recovery still dumps a console log from a boot hours old). A persistent_ram
 * buffer written here is readable later from /proc/last_kmsg (recovery) or
 * /sys/fs/pstore (Aurora).
 *
 * Layout at 0x54410000 (struct persistent_ram_buffer):
 *   0x00 u32 sig   = 0x43474244 ("DBGC")
 *   0x04 u32 start = 0
 *   0x08 u32 size  = 40
 *   0x0c           = "T1100PLD 0x" + 16 hex digits of the runtime address
 */
	.section .text
	.global _start
_start:
	b	real
	.word	0
	.quad	0x80000
	.quad	0		/* image_size: patched by build.sh */
	.quad	0xa
	.quad	0, 0, 0
	.ascii	"ARM\x64"
	.word	0

real:
	adr	x19, real		/* runtime address */

	movz	x20, #0x0000
	movk	x20, #0x5441, lsl #16	/* 0x54410000 */

	movz	w21, #0x4244		/* "DBGC" */
	movk	w21, #0x4347, lsl #16
	str	w21, [x20]
	str	wzr, [x20, #4]

	movz	w21, #0x3154		/* "T110" */
	movk	w21, #0x3031, lsl #16
	str	w21, [x20, #0x0c]
	movz	w21, #0x4c50		/* "PLD " */
	movk	w21, #0x2044, lsl #16
	str	w21, [x20, #0x10]
	movz	w21, #0x7830		/* "0x" */
	str	w21, [x20, #0x14]

	/* 16 hex digits, most significant first, at 0x18..0x27 */
	mov	w22, #15
hexloop:
	lsr	x23, x19, x22
	and	w23, w23, #0xf
	cmp	w23, #9
	b.hi	hexletter
	add	w23, w23, #0x30
	b	hexstore
hexletter:
	add	w23, w23, #0x57
hexstore:
	mov	w24, #15
	sub	w24, w24, w22
	add	x25, x20, #0x18
	add	x25, x25, x24
	strb	w23, [x25]
	subs	w22, w22, #1
	b.pl	hexloop

	mov	w24, #40		/* 0x0c + 16 + 12? -> text is 12 + 16 */
	str	w24, [x20, #8]

	/* stop TOPRGU so the board stays put */
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

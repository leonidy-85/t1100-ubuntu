/* Minimal arm64 "kernel" for boot-chain probing.
 * Runs with MMU off at whatever address LK loaded it to.
 * Writes "T1100PLD" + 8-byte little-endian runtime address into the ramoops
 * console zones (persistent_ram header), paints a white block in LK's
 * framebuffer, then halts.
 */
	.section .text
	.global _start
_start:
	b	real
	.word	0
	.quad	0x80000		/* text_offset: mimic stock kernel */
	.quad	0		/* image_size (patched later) */
	.quad	0xa		/* flags */
	.quad	0, 0, 0
	.ascii	"ARM\x64"
	.word	0

real:
	adr	x19, real		/* runtime address */

	/* stop TOPRGU watchdog handed over by LK: WDT_MODE &= ~EN | KEY */
	ldr	x21, =0x10007000
	ldr	w22, [x21]
	and	w22, w22, #0xfffffffe
	mov	w23, #0x2200
	orr	w22, w22, w23, lsl #16
	str	w22, [x21]

	adr	x20, zones
1:	ldr	x21, [x20], #8
	cbz	x21, 2f
	mov	w22, #0x4244
	movk	w22, #0x4347, lsl #16	/* 0x43474244 "DBGC" */
	str	w22, [x21]
	str	wzr, [x21, #4]
	mov	w23, #16
	str	w23, [x21, #8]
	adr	x24, magic
	ldr	x25, [x24]
	add	x26, x21, #12
	str	x25, [x26], #8
	str	x19, [x26]
	b	1b
2:
	/* plain marker in DRAM ram_console area (0x54400000) */
	ldr	x21, =0x54400000
	adr	x24, magic
	ldr	x25, [x24]
	str	x25, [x21]
	str	x19, [x21, #8]

	/* paint 128 KiB of white at the LK framebuffer */
	ldr	x21, =0x7cd80000
	mov	x22, #0xffff
	movk	x22, #0xffff, lsl #16
	movk	x22, #0xffff, lsl #32
	movk	x22, #0xffff, lsl #48
	mov	x23, #0x4000		/* 16384 * 8 bytes = 128 KiB */
3:	str	x22, [x21], #8
	subs	x23, x23, #1
	b.ne	3b

4:	wfi
	b	4b

	.align 3
zones:
	.quad	0x54410000		/* mainline single console zone */
	.quad	0x54460000		/* vendor 4.14 cprz */
	.quad	0x544a0000		/* vendor 4.14 bprz */
	.quad	0			/* terminator */
magic:
	.ascii	"T1100PLD"

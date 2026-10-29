/* Minimal arm64 payload: prove the boot chain and *read back* the runtime
 * address via the bootloader framebuffer.
 *
 * Why: the T1100 has no UART. The previous probe (refs/probe-payload) showed
 * that `lk` loads and jumps to our image, but the runtime address was written
 * to RAM and lost on reset. Here the same information is painted on screen:
 *
 *   - the screen is cleared to dark grey,
 *   - 36 blocks (16x16 px, 20 px pitch, starting at x=10,y=10) encode
 *     (runtime_address >> 12) LSB-first: white = 1, dark = 0;
 *   - a fixed reference row of 8 blocks encodes 0xAA at y=60 (sanity check);
 *   - the same pattern is painted at both candidate framebuffer bases
 *     (0x7cd80000 — stock reserved-memory, 0x7cb80000 — upstream WIP DTS).
 *
 * A single photo of the screen then tells us:
 *   - did `lk` jump to us at all (any pattern visible),
 *   - which framebuffer base is the live one,
 *   - the exact load address (aligned or not).
 *
 * Runs with MMU off; position independent (adr only).
 */
	.section .text
	.global _start
_start:
	b	real
	.word	0
	.quad	0x80000		/* text_offset: mimic the stock 4.14 kernel */
	.quad	0		/* image_size: patched by build.sh */
	.quad	0xa		/* flags: 4K pages, LE */
	.quad	0, 0, 0
	.ascii	"ARM\x64"
	.word	0

real:
	adr	x19, real
	lsr	x19, x19, #12		/* page index of the runtime address */
	adr	x20, bases
	mov	x22, #0
next_base:
	ldr	x21, [x20, x22, lsl #3]
	cbz	x21, done

	/* clear 160 rows (160 * 6400 = 1024000 bytes) to dark grey */
	mov	x0, x21
	mov	w1, #160
	movz	w2, #0x2020
	movk	w2, #0x0020, lsl #16
bgy:	mov	w3, #1600
bpx:	str	w2, [x0], #4
	subs	w3, w3, #1
	b.ne	bpx
	subs	w1, w1, #1
	b.ne	bgy

	/* encode (addr >> 12), bit i at x = 10 + 20*i, y = 10 */
	mov	w4, #0
bitloop:
	cmp	w4, #36
	b.hs	bits_done
	lsr	x5, x19, x4
	tst	x5, #1
	b.eq	bit_next
	bl	fill_block		/* x0 = base, w1 = x, w2 = y, w3 = colour */
bit_next:
	add	w4, w4, #1
	b	bitloop

bits_done:
	/* reference row: 8 blocks encoding 0xAA at y = 60 */
	mov	w4, #0
refloop:
	cmp	w4, #8
	b.hs	ref_done
	mov	w6, #0xaa
	lsr	w6, w6, w4
	tst	w6, #1
	b.eq	ref_next
	mov	x0, x21
	mov	w1, #10
	mov	w3, #20
	madd	w1, w4, w3, w1		/* x = 10 + 20*i */
	mov	w2, #60
	movn	w3, #0
	bl	fill_block
ref_next:
	add	w4, w4, #1
	b	refloop
ref_done:
	add	x22, x22, #1
	b	next_base

done:
	wfi
	b	done

/* fill_block: x0 = fb base, w1 = x, w2 = y, w3 = colour (ARGB) */
fill_block:
	mov	w7, #6400
	mul	w7, w2, w7
	add	w7, w7, w1, lsl #2
	add	x8, x0, x7
	mov	w9, #16
1:	mov	w10, #16
	mov	x11, x8
2:	str	w3, [x11], #4
	subs	w10, w10, #1
	b.ne	2b
	mov	w12, #6400
	add	x8, x8, x12
	subs	w9, w9, #1
	b.ne	1b
	ret

	.section .rodata
	.align 3
bases:
	.quad	0x7cd80000	/* stock mblock-11-framebuffer */
	.quad	0x7cb80000	/* adomerle/linux-mediatek board DTS */
	.quad	0

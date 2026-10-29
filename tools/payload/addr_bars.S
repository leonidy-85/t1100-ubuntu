/* arm64 payload: find out (a) whether lk really runs us, (b) which framebuffer
 * base is live, (c) at which address we were loaded, (d) keep the board alive
 * long enough to look at the screen.
 *
 * Screen layout afterwards:
 *   - whole screen painted with a solid colour per candidate fb base:
 *       base A (0x7cd80000, stock reserved-memory) -> RED
 *       base B (0x7cb80000, upstream WIP board DTS) -> GREEN
 *     whichever colour is visible identifies the live framebuffer;
 *   - top-left: 36 blocks (16x16, pitch 20) = bits of (runtime_addr >> 12),
 *     LSB first, white = 1;
 *   - below: 8 reference blocks encoding 0xAA (0,1,0,1,...).
 *
 * The TOPRGU watchdog is stopped first, otherwise lk's watchdog resets the
 * board before anyone can read the screen.
 */
	.section .text
	.global _start
_start:
	b	real
	.word	0
	.quad	0x80000		/* text_offset: mimic the stock 4.14 kernel */
	.quad	0		/* image_size: patched by build.sh */
	.quad	0xa		/* flags */
	.quad	0, 0, 0
	.ascii	"ARM\x64"
	.word	0

real:
	/* stop TOPRGU: WDT_MODE &= ~EN, key 0x2200 in [31:16] */
	ldr	x21, =0x10007000
	ldr	w22, [x21]
	and	w22, w22, #0xfffffffe
	mov	w23, #0x2200
	orr	w22, w22, w23, lsl #16
	str	w22, [x21]

	adr	x19, real
	lsr	x19, x19, #12		/* page index of the runtime address */

	/* whole screen at base A = red */
	ldr	x0, =0x7cd80000
	movz	w2, #0xff00, lsl #16	/* 0x00ff0000 */
	bl	fill_screen
	/* whole screen at base B = green */
	ldr	x0, =0x7cb80000
	movz	w2, #0xff00		/* 0x0000ff00 */
	bl	fill_screen

	adr	x20, bases
	mov	x22, #0
next_base:
	ldr	x21, [x20, x22, lsl #3]
	cbz	x21, hang

	/* address bits: 36 blocks, x = 10 + 20*i, y = 10 */
	mov	w4, #0
bitloop:
	cmp	w4, #36
	b.hs	refrow
	lsr	x5, x19, x4
	tst	x5, #1
	b.eq	bit_next
	mov	x0, x21
	mov	w1, #10
	mov	w3, #20
	madd	w1, w4, w3, w1
	mov	w2, #10
	movn	w3, #0
	bl	fill_block
bit_next:
	add	w4, w4, #1
	b	bitloop

refrow:
	mov	w4, #0
refloop:
	cmp	w4, #8
	b.hs	base_done
	mov	w6, #0xaa
	lsr	w6, w6, w4
	tst	w6, #1
	b.eq	ref_next
	mov	x0, x21
	mov	w1, #10
	mov	w3, #20
	madd	w1, w4, w3, w1
	mov	w2, #60
	movn	w3, #0
	bl	fill_block
ref_next:
	add	w4, w4, #1
	b	refloop

base_done:
	add	x22, x22, #1
	b	next_base

hang:
	wfi
	b	hang

/* fill_screen: x0 = fb base, w2 = colour; 1600x2176 px por 160 rows */
fill_screen:
	mov	x9, x0
	mov	w1, #160
1:	mov	w3, #1600
	mov	x5, x9
2:	str	w2, [x5], #4
	subs	w3, w3, #1
	b.ne	2b
	mov	w6, #6400
	add	x9, x9, x6
	subs	w1, w1, #1
	b.ne	1b
	ret

/* fill_block: x0 = fb base, w1 = x, w2 = y, w3 = colour */
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

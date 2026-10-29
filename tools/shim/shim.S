/* arm64 boot shim for the T1100 (MT6771): relocate the real Image to a
 * 2 MiB aligned address before jumping to it.
 *
 * Why: mainline emits text_offset = 0, which per the arm64 boot protocol
 * requires the image to be placed at a 2 MiB aligned address. MTK `lk` loads
 * the boot.img kernel at the address from the boot header (0x40080000 by
 * default, i.e. base + 0x80000), which is not aligned. Everything the kernel
 * prints appears only after the early page tables are up, so a failure there
 * is completely silent on a board with no UART.
 *
 * How it works: this shim is assembled *with the real kernel appended*
 * (`.incbin`), so `lk` decompresses shim+kernel into RAM and jumps to the
 * shim's entry. The shim copies the kernel to DEST (2 MiB aligned), cleans
 * the caches, restores x0 (DTB pointer) and branches to the copy.
 *
 * Alignment of the copy destination and the kernel's own expectations are
 * both satisfied: _text == DEST, which is 2 MiB aligned.
 */
	.section .text
	.global _start
_start:
	b	real
	.word	0
	.quad	0x80000		/* text_offset: lk friendly */
	.quad	0		/* image_size: patched by build.sh */
	.quad	0xa		/* flags */
	.quad	0, 0, 0
	.ascii	"ARM\x64"
	.word	0

	.equ	SHIM_DEST, 0x44000000	/* 2 MiB aligned, clear of DTB 0x54000000 */

real:
	mov	x20, x0			/* preserve DTB pointer from lk */

	adrp	x21, kern_begin		/* source (runtime, position independent) */
	add	x21, x21, :lo12:kern_begin
	adrp	x22, kern_end
	add	x22, x22, :lo12:kern_end
	mov	x23, #SHIM_DEST

	/* copy 16 bytes at a time; dest and source do not overlap */
1:	ldp	x25, x26, [x21], #16
	stp	x25, x26, [x23], #16
	cmp	x21, x22
	b.lo	1b

	/* clean the copied range to the point of coherency */
	mov	x24, #SHIM_DEST
	adrp	x21, kern_begin
	add	x21, x21, :lo12:kern_begin
	adrp	x22, kern_end
	add	x22, x22, :lo12:kern_end
	sub	x22, x22, x21		/* length */
	add	x22, x22, x24		/* end address */
2:	dc	civac, x24
	add	x24, x24, #64
	cmp	x24, x22
	b.lo	2b

	dsb	sy
	isb

	mov	x0, x20			/* DTB for the real kernel */
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	mov	x16, #SHIM_DEST
	br	x16

	.balign 8
kern_begin:
	.incbin KERNEL_BIN
kern_end:

/*
 * Copyright (C) 2015 MediaTek Inc.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

#include <linux/mm.h>
#include <linux/sched.h>
#include <linux/uaccess.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/platform_device.h>
#include <linux/cdev.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/sched.h>
#include <linux/wait.h>
#include <linux/spinlock.h>
#include <linux/delay.h>
/* #include <linux/earlysuspend.h> */
#include <linux/mm.h>
#include <linux/vmalloc.h>
#include <linux/dma-mapping.h>
#include <linux/slab.h>
/* #include <linux/aee.h> */
#include <linux/timer.h>
#include <linux/cache.h>
/* #include <linux/printk.h> */
#include <linux/highmem.h>

#ifdef pr_fmt
#undef pr_fmt
#endif
#define pr_fmt(fmt) "["KBUILD_MODNAME"]" fmt

static int vcodec_va_to_pfn_pfnmap(unsigned long va, unsigned long *pfn)
{
	struct vm_area_struct *vma;
	struct follow_pfnmap_args args;
	int ret = -EINVAL;

	mmap_read_lock(current->mm);
	vma = find_vma(current->mm, va);
	if (!vma || va < vma->vm_start)
		goto out;

	memset(&args, 0, sizeof(args));
	args.vma = vma;
	args.address = va;
	ret = follow_pfnmap_start(&args);
	if (ret)
		goto out;

	*pfn = args.pfn;
	follow_pfnmap_end(&args);
	ret = 0;
out:
	mmap_read_unlock(current->mm);
	return ret;
}

static int vcodec_va_to_pfn_gup(unsigned long va, unsigned long *pfn)
{
	struct page *page = NULL;
	int ret;

	ret = pin_user_pages_fast(va & PAGE_MASK, 1, 0, &page);
	if (ret != 1)
		return -EFAULT;

	*pfn = page_to_pfn(page);
	unpin_user_page(page);
	return 0;
}

/*
 * Mainline 6.12 replacement for MTK's pmem_user_v2p_video().
 *
 * The vendor driver only uses the returned physical address as a stable
 * per-instance handle (HW lock ownership, DVFS job key).  Handle both
 * PFNMAP/IO mappings (ION/dma-buf) and ordinary user pages.
 */
unsigned long pmem_user_v2p_video(unsigned long va)
{
	unsigned long page_offset = va & (PAGE_SIZE - 1);
	unsigned long pfn = 0;

	if (!current || !current->mm) {
		pr_info("[ERROR] %s, current/mm is NULL!\n", __func__);
		return 0;
	}

	if (vcodec_va_to_pfn_pfnmap(va, &pfn) &&
	    vcodec_va_to_pfn_gup(va, &pfn)) {
		pr_info_ratelimited("[ERROR] v2p: va=0x%lx not mapped\n", va);
		return 0;
	}

	return (pfn << PAGE_SHIFT) | page_offset;
}
#ifndef VCODEC_LIVE_TEST
EXPORT_SYMBOL(pmem_user_v2p_video);
#endif

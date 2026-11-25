/* SPDX-License-Identifier: GPL-2.0 */
/*
 * mtk_port_414.h -- 4.14 -> 6.12 kernel API shims for the vendor MediaTek
 * connectivity stack (WMT + wlan gen3).
 *
 * Force-included into every vendor translation unit by the Kbuild wrappers
 * (scripts/remote/wifi-kbuild/common.Kbuild, wlan.Kbuild). Only *kernel API removals* are
 * shimmed here -- MTK-only subsystems (PMIC, clkbuf, EMI MPU, RTC 32k) are
 * stubbed where they are called, with their own TODO, not here.
 *
 * Based on MediaTek/Motorola GPL-2.0 sources (connectivity-common 3ff67212,
 * wlan-core-gen3 249649d8); the shims themselves are ours.
 */
#ifndef __MTK_WIFI_PORT_414_H__
#define __MTK_WIFI_PORT_414_H__

#include <linux/types.h>
#include <linux/version.h>
#include <linux/time64.h>
#include <linux/ktime.h>
#include <linux/timekeeping.h>
#include <linux/rtc.h>

/*
 * struct timeval / do_gettimeofday() are not visible to kernel code since
 * 5.x: <uapi/linux/time.h> declares the struct under #ifndef __KERNEL__, and
 * do_gettimeofday() was removed in 5.6 (ktime_get_real_ts64() replaces it).
 *
 * The vendor stack uses timeval purely as a {sec, usec} pair (log timestamps,
 * packet jitter measurement), so a local definition plus an inline wrapper is
 * semantically identical to what 4.14 did:
 *
 *   void do_gettimeofday(struct timeval *tv)
 *   {
 *           struct timespec64 ts;
 *           ktime_get_real_ts64(&ts);
 *           tv->tv_sec = ts.tv_sec;
 *           tv->tv_usec = ts.tv_nsec / NSEC_PER_USEC;
 *   }
 */
struct timeval {
	__kernel_old_time_t tv_sec;	/* seconds */
	__kernel_suseconds_t tv_usec;	/* microseconds */
};

static inline void mtk_port_gettimeofday(struct timeval *tv)
{
	struct timespec64 ts;

	ktime_get_real_ts64(&ts);
	tv->tv_sec = ts.tv_sec;
	tv->tv_usec = ts.tv_nsec / NSEC_PER_USEC;
}

#define do_gettimeofday(tv)		mtk_port_gettimeofday(tv)

/* rtc_time_to_tm() -> rtc_time64_to_tm() (4.20+): same conversion, 64-bit in. */
#define rtc_time_to_tm(sec, tm)		rtc_time64_to_tm((time64_t)(sec), (tm))

/*
 * MTK RTC "32k to GPS/BT" helper (drivers/misc/mediatek/rtc/rtc-mt6xxx.c in
 * the vendor tree). Mainline has no equivalent: the 32k gate is handled by
 * the clk framework. Used by common_detect/wmt_detect_pwr.c and
 * common_main/platform/wmt_plat_alps.c.
 *
 * TODO(power-on): verify on hardware that CONSYS still gets its 32k reference
 * -- if not, this has to become a CCF clock gate instead of a no-op.
 */
#define RTC_GPIO_USER_GPS		0
static inline int rtc_gpio_enable_32k(int user)
{
	(void)user;
	return 0;
}

/*
 * 7.3 fbdev notifier no longer defines FB_EVENT_BLANK (only FB_REGISTERED /
 * FB_UNREGISTERED).  The WMT early-suspend hook only cares about blank
 * events, so give it an unused id: the callback stays registered but inert.
 */
#ifndef FB_EVENT_BLANK
#define FB_EVENT_BLANK			0x07
#endif

#endif /* __MTK_WIFI_PORT_414_H__ */

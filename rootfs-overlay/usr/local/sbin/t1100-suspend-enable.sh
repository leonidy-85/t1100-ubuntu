#!/bin/sh
# One-time setup for the T1100 rootfs: enable the standard systemd sleep
# targets.  They are masked in the stock image because suspend was not usable.
set -e
systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target

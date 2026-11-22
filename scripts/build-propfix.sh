#!/usr/bin/env bash
#
# build-propfix.sh — собрать ARM32 bionic-шим libpropfix.so и положить его
# в rootfs-overlay, чтобы он разворачивался вместе с остальной системой.
#
#   scripts/build-propfix.sh
#
# Шим нужен потому, что в chroot /opt/bionic нет Android property-сервиса:
# без него mnld читает пустой persist.vendor.connsys.chipid и выбирает
# generic DSP-образ (GPS не выдаёт измерений).
#
# Env:
#   BUILD_HOST (default l@172.17.141.124)
#   BUILD_PASS (default 0)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.124}"
BUILD_PASS="${BUILD_PASS:-0}"
REL="opt/bionic/vendor/lib/libpropfix.so"
OUT="$REPO_ROOT/rootfs-overlay/$REL"

SSH=(sshpass -p "$BUILD_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
SCP=(sshpass -p "$BUILD_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "== source -> $BUILD_HOST"
"${SCP[@]}" "$REPO_ROOT/tools/device/t1100-propfix.c" "$BUILD_HOST:/tmp/t1100-propfix.c"

echo "== compile (armhf, -nostdlib: bionic linker)"
"${SSH[@]}" "$BUILD_HOST" \
	'arm-linux-gnueabihf-gcc -shared -fPIC -nostdlib -O2 -o /tmp/libpropfix.so /tmp/t1100-propfix.c'

mkdir -p "$(dirname "$OUT")"
"${SCP[@]}" "$BUILD_HOST:/tmp/libpropfix.so" "$OUT"

echo "== $(sha256sum "$OUT" | cut -c1-16)… $(stat -c%s "$OUT") bytes -> ${OUT#$REPO_ROOT/}"

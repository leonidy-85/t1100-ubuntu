#!/usr/bin/env bash
#
# build-btif-remote.sh — собрать BTIF-драйвер MT6771 (M23) на build-хосте.
#
# M23 (см. docs/wifi-port-log.md §44): STP-транспорт для WMT на MT6771 — это
# BTIF (`btif@1100c000`). Публичный mainline-порт BTIF лежит в дереве Rabbit
# (mt6765) и правится только патчем: драйвер требует DT-узел и клоки
# `btifc`/`apdmac`, которых в mainline 6.12 для MT6771 нет. Наш слой
# (scripts/remote/m23-btif/) даёт ему platform device, базы/IRQ из параметров
# модуля (значения из стокового DT), прямой доступ к гейтам INFRACFG_AO и
# пару самопроверок.
#
# Использование:
#   scripts/build-btif-remote.sh              # разложить + собрать
#   scripts/build-btif-remote.sh --prepare    # только разложить/пропатчить
#
# Env: BUILD_HOST (l@172.17.141.172), BUILD_PASS (0), BTIF_DIR (/home/l/m23-btif),
#      KERNEL_OUT (/home/l/t1100-merge2-out), JOBS.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_HOST="${BUILD_HOST:-l@172.17.141.172}"
BUILD_PASS="${BUILD_PASS:-0}"
BTIF_DIR="${BTIF_DIR:-/home/l/m23-btif}"
BTIF_GLUE="${BTIF_GLUE:-${BTIF_DIR}-glue}"
KERNEL_OUT="${KERNEL_OUT:-/home/l/t1100-merge2-out}"
JOBS="${JOBS:-}"

command -v sshpass >/dev/null || { echo "нужен sshpass" >&2; exit 1; }
command -v rsync   >/dev/null || { echo "нужен rsync" >&2; exit 1; }

SSH=(sshpass -p "${BUILD_PASS}" ssh -o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${BUILD_HOST}")
RSYNC=(rsync -a --delete -e "sshpass -p ${BUILD_PASS} ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null")

JOBS="${JOBS:-$("${SSH[@]}" nproc)}"

echo "== rsync: glue + патч BTIF =="
# The glue lives *next to* $BTIF_DIR, not inside it: the remote script rsyncs
# the pristine BTIF tree into $BTIF_DIR with --delete, which would wipe a
# glue/ subdirectory on every run.
"${RSYNC[@]}" "${REPO_ROOT}/scripts/remote/m23-btif/" "${BUILD_HOST}:${BTIF_GLUE}/" >/dev/null
"${SSH[@]}" "mkdir -p '${BTIF_GLUE}/patches' && cp '${BTIF_GLUE}/0010-btif-mt6771-glue.patch' '${BTIF_GLUE}/patches/'" </dev/null

if [ "${1:-}" = "--prepare" ]; then ARG=--prepare-only; else ARG=""; fi

"${SSH[@]}" "BTIF_DIR='${BTIF_DIR}' GLUE='${BTIF_GLUE}' KERNEL_OUT='${KERNEL_OUT}' JOBS='${JOBS}' \
	bash -s ${ARG}" < "${REPO_ROOT}/scripts/remote/build-btif-remote.sh"

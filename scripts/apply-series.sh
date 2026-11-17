#!/bin/sh
# Применить серию патчей проекта к дереву ядра (для сборки «как прошивка»).
#
#   scripts/apply-series.sh <worktree> [--from 0053] [--dry-run]
#
# Зачем: `../linux-t1100` — это база 6.12.114 + то, что успели закоммитить
# (на 18.11 — коммиты до 0052, т.е. 13.11). Патчи 0053…0078 лежат только в
# `patches/`, и ядро, которое реально прошито на планшете, собрано из дерева
# с ними. Скрипт накатывает серию на новую ветку/worktree.
#
# Особенности:
#  - патчи в `patches/` — обычные diff'ы (без From/Subject), поэтому `git apply`,
#    а не `git am`;
#  - DTS-патчи пропускаются при конфликте: в этом проекте DTB при перепаковке
#    boot берётся из прошивки, а не из дерева (см. docs/browser.md не при чём —
#    см. docs/panfrost-plan.md, раздел 18.11, и docs/STATUS.md 18.11);
#  - 0060 и 0074 конфликтуют с базой 13.11 и разрешены вручную: после скрипта
#    они помечаются как SKIP, их правки нужно брать из ветки, где они уже
#    разрешены (или применять `patch -p1 -F3` и править .rej руками).
set -eu

TREE=${1:?usage: apply-series.sh <worktree> [--from NNNN] [--dry-run]}
shift
FROM=
DRY=0
while [ $# -gt 0 ]; do
	case "$1" in
	--from) FROM=$2; shift ;;
	--dry-run) DRY=1 ;;
	*) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
	esac
	shift
done

REPO=$(cd "$(dirname "$0")/.." && pwd)
SERIES="$REPO/patches/series"
[ -d "$TREE" ] || { echo "нет дерева: $TREE" >&2; exit 1; }

started=0
applied=0
skipped_dts=0
skipped=0
while IFS= read -r p; do
	case "$p" in ''|\#*) continue ;; esac
	num=${p%%-*}
	if [ -n "$FROM" ] && [ "$num" \< "$FROM" ]; then continue; fi
	started=1
	f="$REPO/patches/$p"
	[ -f "$f" ] || { echo "нет патча: $f" >&2; exit 1; }
	if [ "$DRY" = 1 ]; then
		git -C "$TREE" apply --check "$f" 2>/dev/null && echo "ok   $p" || echo "check-fail $p"
		continue
	fi
	if git -C "$TREE" apply --index "$f" 2>/dev/null; then
		applied=$((applied + 1)); echo "ok   $p"
	elif git -C "$TREE" apply --index --exclude='arch/arm64/boot/dts/*' "$f" 2>/dev/null; then
		applied=$((applied + 1)); skipped_dts=$((skipped_dts + 1))
		echo "ok*  $p (DTS-часть пропущена)"
	else
		skipped=$((skipped + 1)); echo "SKIP $p (конфликт — разрешать вручную)"
	fi
done < "$SERIES"

echo "итог: применено $applied (из них без DTS: $skipped_dts), конфликтов $skipped"
[ "$skipped" -eq 0 ] || echo "внимание: конфликтующие патчи надо разрешить вручную (0060, 0074)" >&2

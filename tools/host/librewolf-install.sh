#!/bin/sh
# Установка браузера LibreWolf на планшет (arm64 .deb, без snap).
#
#   tools/host/librewolf-install.sh              # репозиторий + ключ + пакет + user.js
#   tools/host/librewolf-install.sh --prefs-only # только user.js в профили
#
# Зачем не Ubuntu-пакеты: `firefox` и `chromium-browser` в 26.04 — заглушки,
# которые тянут snap; snapd на планшете падает на монтировании squashfs
# (в ядре только CONFIG_SQUASHFS_ZLIB, образы snap сжаты xz/zstd).
# Подробности и остальные грабли — docs/browser.md.
#
# Хост — $T1100_HOST (по умолчанию 10.42.66.66), доступ root по ключу.
# Ключ репозитория сверяется по отпечатку 662E3CDD6FE329002D0CA5BB40339DD82B12EF16.
set -eu
HOST=${T1100_HOST:-10.42.66.66}
MODE=full
[ "${1:-}" = "--prefs-only" ] && MODE=prefs
SSHOPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PREFS="$REPO/configs/librewolf-user.js"
KEYRING_SHA=8398142ed02480bfa19192308016c0cc8b4a87d0ec821c4e23decf6f11ce4560
KEY_FPR=662E3CDD6FE329002D0CA5BB40339DD82B12EF16

[ -f "$PREFS" ] || { echo "нет $PREFS" >&2; exit 1; }

if [ "$MODE" = full ]; then
	echo "== репозиторий LibreWolf и ключ"
	ssh $SSHOPT "root@$HOST" '
		set -eu
		export DEBIAN_FRONTEND=noninteractive
		command -v gpg >/dev/null || apt-get install -y --no-install-recommends gnupg
		install -d -m 0755 /etc/apt/keyrings
		python3 -c "import urllib.request;open(\"/etc/apt/keyrings/librewolf.gpg\",\"wb\").write(urllib.request.urlopen(\"https://repo.librewolf.net/keyring.gpg\",timeout=60).read())"
		echo "sha256: $(sha256sum /etc/apt/keyrings/librewolf.gpg | cut -d" " -f1)"
		gpg --show-keys --with-fingerprint /etc/apt/keyrings/librewolf.gpg | sed -n 2p
		echo "deb [signed-by=/etc/apt/keyrings/librewolf.gpg] https://repo.librewolf.net librewolf main" \
			> /etc/apt/sources.list.d/librewolf.list
	'
	echo "== проверка ключа"
	ssh $SSHOPT "root@$HOST" "set -eu
		sha=\$(sha256sum /etc/apt/keyrings/librewolf.gpg | cut -d' ' -f1)
		[ \"\$sha\" = \"$KEYRING_SHA\" ] || { echo \"sha256 ключа не тот: \$sha\" >&2; exit 1; }
		gpg --show-keys --with-fingerprint /etc/apt/keyrings/librewolf.gpg | tr -d ' ' | grep -qi '$KEY_FPR' \
			|| { echo 'отпечаток ключа не совпал' >&2; exit 1; }
		echo 'ключ и отпечаток совпали'"

	echo "== apt-get install librewolf (~150 МБ загрузки, ~450 МБ на диске)"
	ssh $SSHOPT "root@$HOST" 'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y librewolf' 2>&1 | tail -5
fi

echo "== user.js в профили LibreWolf"
scp -q $SSHOPT "$PREFS" "root@$HOST:/tmp/librewolf-user.js"
ssh $SSHOPT "root@$HOST" '
	set -eu
	n=0
	for p in /root/.config/librewolf/librewolf/*/; do
		case "$p" in
		*"Profile Groups"*) continue ;;
		*firefox-mpris*) continue ;;
		esac
		[ -f "$p/prefs.js" ] || [ -f "$p/times.json" ] || continue
		cp -f /tmp/librewolf-user.js "$p/user.js"
		n=$((n+1))
		echo "  $p"
	done
	[ "$n" -gt 0 ] || { echo "профилей не найдено — сначала запусти librewolf один раз" >&2; exit 1; }
	dpkg -l librewolf | tail -1
'

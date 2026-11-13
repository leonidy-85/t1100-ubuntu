#!/usr/bin/env bash
#
# check-root-login.sh — проверить (и при --fix снять) PAM-запреты входа root.
#
# Зачем: на этом rootfs root-сессия — рабочая (автологин SDDM, рабочий стол под
# root), но в нескольких PAM-службах живёт правило upstream, которое отказывает
# root ДО проверки пароля:
#
#     auth required pam_succeed_if.so user != root quiet_success
#
# Оно уже дважды всплывало (экран блокировки `kde`, экран входа `sddm`) и
# возвращается при переразвёртывании пакетов/оверлея. Подробности и история —
# docs/root-login-pam.md.
#
# Использование:
#   tools/host/check-root-login.sh [host]          # только проверка
#   tools/host/check-root-login.sh --fix [host]    # закомментировать активные запреты
#
# Что проверяет:
#   1. активные (не закомментированные) запреты `user != root` в /etc/pam.d и
#      в vendor-каталоге /usr/lib/pam.d (Debian/Ubuntu кладут часть служб туда);
#   2. состояние аккаунта: passwd -S root (P = пароль есть, L = заблокирован);
#   3. тень: пустой/`!`/`*` хеш = войти по паролю нельзя;
#   4. автологин SDDM (иначе нужен рабочий вход через greeter — а это PAM sddm).
set -eu

FIX=0
if [ "${1:-}" = "--fix" ]; then FIX=1; shift; fi
HOST=${1:-10.42.66.66}

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$HOST"

echo "== $HOST: активные запреты входа root в PAM"
BLOCKS=$($SSH 'grep -rnE "^[[:space:]]*(auth|account)[[:space:]].*pam_succeed_if.*user[[:space:]]*!=[[:space:]]*root" \
	/etc/pam.d /usr/lib/pam.d 2>/dev/null || true')
if [ -n "$BLOCKS" ]; then
	echo "$BLOCKS"
else
	echo "нет — PAM root не блокирует"
fi

echo "== аккаунт"
$SSH 'printf "passwd -S: "; passwd -S root 2>&1; printf "shadow:    "; getent shadow root | cut -d: -f2 | cut -c1-12'

echo "== автологин SDDM"
$SSH 'grep -rn "Autologin" -A2 /etc/sddm.conf /etc/sddm.conf.d/* 2>/dev/null | grep -E "User=|Session=" || echo "автологин не настроен"'

if [ "$FIX" = 1 ] && [ -n "$BLOCKS" ]; then
	echo "== снимаю запреты (с бэкапом *.bak-$(date +%Y%m%d))"
	$SSH 'for f in $(grep -rlE "^[[:space:]]*(auth|account)[[:space:]].*pam_succeed_if.*user[[:space:]]*!=[[:space:]]*root" \
		/etc/pam.d /usr/lib/pam.d 2>/dev/null); do
		cp -a "$f" "$f.bak-$(date +%Y%m%d)"
		sed -i -E "s|^([[:space:]]*)((auth|account)[[:space:]].*pam_succeed_if.*user[[:space:]]*!=[[:space:]]*root.*)$|# t1100: root разрешён (check-root-login.sh)\n# \2|" "$f"
		echo "поправлен $f"
	done'
	echo "== повторная проверка"
	$SSH 'grep -rnE "^[[:space:]]*(auth|account)[[:space:]].*pam_succeed_if.*user[[:space:]]*!=[[:space:]]*root" \
		/etc/pam.d /usr/lib/pam.d 2>/dev/null || echo "чисто"'
	echo
	echo "ВАЖНО: правки нужно положить в rootfs-overlay (см. docs/root-login-pam.md),"
	echo "иначе следующее переразвёртывание пакетов/оверлея вернёт запрет."
fi

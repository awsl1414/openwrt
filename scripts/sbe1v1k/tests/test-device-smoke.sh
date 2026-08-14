#!/bin/sh
# Optional on-device smoke checks for a flashed SBE1V1K bring-up image.
#
#   SBE_HOST=192.168.1.1 bash scripts/sbe1v1k/tests/test-device-smoke.sh
#   bash scripts/sbe1v1k/tests/test-device-smoke.sh root@192.168.1.1
#
# Skips (exit 0) when the host is unreachable so CI/host runs stay green.
set -eu

target=${1:-${SBE_HOST:-root@192.168.1.1}}
case "$target" in
*@*) ;;
*) target="root@$target" ;;
esac

host=${target#*@}
ssh_opts='-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5'

if ! ping -c 1 -W 2 "$host" >/dev/null 2>&1 && \
   ! ping -c 1 -t 2 "$host" >/dev/null 2>&1; then
	echo "device-smoke: skip (host $host unreachable)"
	exit 0
fi

if ! ssh $ssh_opts "$target" 'true' >/dev/null 2>&1; then
	echo "device-smoke: skip (ssh to $target failed)"
	exit 0
fi

pass=0
fail=0

ok() {
	pass=$((pass + 1))
	printf '  PASS %s\n' "$1"
}

bad() {
	fail=$((fail + 1))
	printf '  FAIL %s\n' "$1" >&2
}

remote() {
	# Intentionally unquoted ssh_opts word-splitting for multiple -o flags.
	# shellcheck disable=SC2086
	ssh $ssh_opts "$target" "$@"
}

board=$(remote 'cat /tmp/sysinfo/board_name 2>/dev/null || true')
if [ "$board" = 'askey,sbe1v1k' ]; then
	ok "board_name=$board"
else
	bad "board_name expected askey,sbe1v1k got '$board'"
fi

if remote 'grep -q askey_sbe1v1k /etc/openwrt_release 2>/dev/null || grep -qi sbe1v1k /tmp/sysinfo/model 2>/dev/null'; then
	ok "release/model mentions SBE"
else
	# model file alone is enough when board_name matched
	if [ "$board" = 'askey,sbe1v1k' ]; then
		ok "model check soft-ok via board_name"
	else
		bad "release/model does not mention SBE"
	fi
fi

# Web UI: luci-ssl → uhttpd on 80 and/or 443
if remote 'netstat -lnt 2>/dev/null | grep -qE \":(80|443) \" || ss -lnt 2>/dev/null | grep -qE \":(80|443) \"'; then
	ok "uhttpd listening on 80/443"
else
	bad "no listener on 80/443 (luci-ssl missing?)"
fi

if remote 'netstat -lnt 2>/dev/null | grep -q \":22 \" || ss -lnt 2>/dev/null | grep -q \":22 \"'; then
	ok "dropbear/ssh on 22"
else
	bad "ssh not listening"
fi

# 2.4 GHz default AP should be enabled after board.d / uci-defaults
wifi_2g=$(remote 'uci -q show wireless 2>/dev/null | grep "\.band=.2g." | head -n1 || true')
if [ -n "$wifi_2g" ]; then
	ok "wireless has 2g device"
else
	bad "no 2g wifi-device in UCI"
fi

disabled_2g=$(remote '
. /lib/functions.sh
config_load wireless
found=0
en=0
check() {
	local s=$1 device mode band dis
	config_get mode "$s" mode
	[ "$mode" = ap ] || return 0
	config_get device "$s" device
	config_get band "$device" band
	[ "$band" = 2g ] || return 0
	found=1
	config_get dis "$s" disabled 0
	if [ "$dis" = 0 ] || [ -z "$dis" ]; then
		en=1
	fi
}
config_foreach check wifi-iface
echo "$found:$en"
')
case "$disabled_2g" in
1:1) ok "2.4 GHz AP enabled (disabled=0)" ;;
1:0) bad "2.4 GHz AP present but disabled" ;;
*) bad "2.4 GHz AP iface not found ($disabled_2g)" ;;
esac

if remote 'iw phy >/dev/null 2>&1 && iw phy | grep -q Wiphy'; then
	ok "iw phy present"
else
	bad "iw phy missing"
fi

# Option B: per-radio permanent MAC identity (ath12k multi-radio / WSI)
if remote 'test -f /usr/share/hostap/radio-mac.uc'; then
	ok "radio-mac.uc installed"
else
	bad "radio-mac.uc missing on device"
fi

if remote 'test -f /usr/share/hostap/phy-setup-lock.uc'; then
	ok "phy-setup-lock.uc installed"
else
	bad "phy-setup-lock.uc missing on device"
fi

mac_map=$(remote '
set -e
# Prefer renamed board phy; fall back to phy0.
phy=
for c in /sys/class/ieee80211/wl0 /sys/class/ieee80211/phy0; do
	if [ -f "$c/addresses" ]; then
		phy=$c
		break
	fi
done
if [ -z "$phy" ]; then
	echo "no-addresses"
	exit 0
fi
naddr=$(grep -c . "$phy/addresses" || true)
nmac=$(uci -q show wireless | grep -c "\.hwmac=" || true)
nradio=$(uci -q show wireless | grep -c "=wifi-device" || true)
echo "$naddr:$nmac:$nradio"
')
case "$mac_map" in
no-addresses)
	# Bring-up without ath12k addresses yet — soft skip.
	ok "per-radio addresses not ready (skip hwmac map check)"
	;;
[1-9]*:[1-9]*:[1-9]*)
	naddr=${mac_map%%:*}
	rest=${mac_map#*:}
	nmac=${rest%%:*}
	nradio=${rest#*:}
	if [ "$nmac" -ge "$naddr" ] && [ "$nradio" -ge "$naddr" ]; then
		ok "wifi-device hwmac covers addresses ($mac_map)"
	else
		bad "hwmac/radio count low vs addresses ($mac_map); run: wifi config"
	fi
	;;
*)
	bad "unexpected hwmac map probe ($mac_map)"
	;;
esac

# Firmware / cal stubs expected for ath12k
if remote 'test -f /lib/firmware/ath12k/QCN9274/hw2.0/board-2.bin'; then
	ok "ath12k board-2.bin present"
else
	bad "missing ath12k board-2.bin"
fi

printf 'device-smoke (%s): %s passed, %s failed\n' "$target" "$pass" "$fail"
[ "$fail" -eq 0 ]

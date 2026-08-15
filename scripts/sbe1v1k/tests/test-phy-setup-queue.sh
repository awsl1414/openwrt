#!/bin/sh
# Host tests for Tier-2 multi-radio hostapd serialization (phy-setup-queue).
set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tests_dir/../../.." && pwd)
queue_uc="$repo_root/package/network/services/hostapd/files/phy-setup-queue.uc"
hostapd_uc="$repo_root/package/network/services/hostapd/files/hostapd.uc"
mac80211_sh="$repo_root/package/network/config/wifi-scripts/files/lib/netifd/wireless/mac80211.sh"
mac80211_ucode="$repo_root/package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh"
wifi_hostapd="$repo_root/package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/hostapd.uc"
wifi_common="$repo_root/package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/common.uc"
old_lock="$repo_root/package/network/config/wifi-scripts/files/usr/share/hostap/phy-setup-lock.uc"

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

expect_eq() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		bad "$1 (got='$2' want='$3')"
	fi
}

[ -f "$queue_uc" ] && ok "phy-setup-queue.uc present" || bad "phy-setup-queue.uc present"
[ ! -f "$old_lock" ] && ok "phy-setup-lock.uc removed" || bad "phy-setup-lock.uc removed"

grep -q 'phy-setup-queue.uc' "$repo_root/package/network/services/hostapd/Makefile" && \
	ok "hostapd Makefile installs phy-setup-queue.uc" || \
	bad "hostapd Makefile installs phy-setup-queue.uc"

grep -q 'from "phy-setup-queue"' "$hostapd_uc" && ok "hostapd.uc imports phy-setup-queue" || bad "hostapd.uc imports phy-setup-queue"
grep -q 'function phy_setup_run' "$hostapd_uc" && ok "hostapd.uc has phy_setup_run" || bad "hostapd.uc has phy_setup_run"
grep -q 'req.defer()' "$hostapd_uc" && ok "config_set defers ubus reply" || bad "config_set defers ubus reply"
grep -q 'should_phy_setup_settle' "$hostapd_uc" && ok "settle gated by helper" || bad "settle gated by helper"
grep -q 'remove_iface' "$hostapd_uc" && grep -q 'phy_setup_abort_active' "$hostapd_uc" && \
	ok "supersede tears down iface" || bad "supersede tears down iface"
grep -q 'Sync teardown' "$hostapd_uc" && ok "config_reset is sync" || bad "config_reset is sync"

# Only config_set uses the queue (not reload/apsta/mld).
cfg_uses=$(grep -c 'phy_setup_run(' "$hostapd_uc" || true)
# function def + config_set call = 2
if [ "$cfg_uses" -eq 2 ]; then
	ok "phy_setup_run only for config_set"
else
	bad "phy_setup_run call sites unexpected (count=$cfg_uses)"
fi

if grep -q 'phy-setup-lock\|acquire_hostapd_phy_lock\|PHY_SETUP_LOCK' "$mac80211_sh" "$mac80211_ucode"; then
	bad "wifi-scripts still reference phy-setup-lock"
else
	ok "wifi-scripts have no phy-setup-lock"
fi

grep -q 'ubus_call_hostapd_config_set' "$mac80211_sh" && ok "shell long timeout helper" || bad "shell long timeout helper"
grep -q 'ubus -t 300 call hostapd config_set' "$mac80211_sh" && ok "shell 300s only for config_set" || bad "shell 300s only for config_set"
if grep -q 'ubus -t 300 call "\$@"' "$mac80211_sh"; then
	bad "shell must not use 300s for all ubus"
else
	ok "shell default ubus not 300s"
fi

grep -q 'connect(null, 300)' "$wifi_hostapd" && ok "ucode 300s for hostapd config_set" || bad "ucode 300s for hostapd config_set"
if grep -q 'connect(null, 300)' "$wifi_common"; then
	bad "ucode global ubus must not be 300s"
else
	ok "ucode global ubus default timeout"
fi

if grep -qE 'export function (coalesce_phy_setup_queue|sort_phy_setup_queue)' "$queue_uc"; then
	bad "coalesce/sort must stay private"
else
	ok "coalesce/sort not exported"
fi

grep -q 'export function should_phy_setup_settle' "$queue_uc" && ok "should_phy_setup_settle exported" || bad "should_phy_setup_settle exported"

if ! command -v ucode >/dev/null 2>&1; then
	ok "ucode helper tests skipped (no ucode)"
else
	out=$(WIFI_HOSTAPD_PHY_SETUP=0 ucode - <<EOF
import { phy_setup_queue_enabled, needs_phy_setup_queue, normalize_radio } from "${queue_uc}";
print(phy_setup_queue_enabled() ? "on" : "off");
print(needs_phy_setup_queue(0) ? "need" : "skip");
print(normalize_radio("1"));
EOF
) || out="ucode-failed"
	expect_eq "disable + normalize" "$(printf '%s' "$out" | tr '\n' ' ' | sed 's/ *$//')" "off skip 1"

	out=$(ucode - <<EOF
import {
	needs_phy_setup_queue, is_phy_setup_steady, should_phy_setup_settle,
	normalize_radio, enqueue_phy_setup_sorted
} from "${queue_uc}";
print(needs_phy_setup_queue("2") ? "need2" : "skip2");
print(should_phy_setup_settle("ENABLED") ? "se" : "nse");
print(should_phy_setup_settle("DISABLED") ? "sd" : "nsd");
print(should_phy_setup_settle("NO_IR") ? "sn" : "nsn");
print(is_phy_setup_steady(false, "NO_IR") ? "noir" : "nonoir");
let q = enqueue_phy_setup_sorted(
	[ { name: "wl0.1", radio: 1 } ],
	{ name: "wl0.0", radio: "0" });
print(join(",", map(q, (j) => j.name)));
EOF
) || out="ucode-failed"
	expect_eq "helpers" "$(printf '%s' "$out" | tr '\n' ' ' | sed 's/ *$//')" \
		"need2 se nsd nsn noir wl0.0,wl0.1"
fi

printf 'phy-setup-queue: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

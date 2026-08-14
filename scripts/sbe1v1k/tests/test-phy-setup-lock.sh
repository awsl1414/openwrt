#!/bin/sh
# Host tests for multi-radio hostapd setup serialization (Option B).
#
# Single policy + lock implementation: phy-setup-lock.uc
# Shell and ucode backends must call that module (no parallel nl/mkdir logic).
#
set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tests_dir/../../.." && pwd)
lock_uc="$repo_root/package/network/config/wifi-scripts/files/usr/share/hostap/phy-setup-lock.uc"
mac80211_sh="$repo_root/package/network/config/wifi-scripts/files/lib/netifd/wireless/mac80211.sh"
mac80211_ucode="$repo_root/package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh"

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

# --- 1. Contracts / wiring ------------------------------------------------

grep -q 'export function needs_phy_setup_lock' "$lock_uc" && ok "export needs_phy_setup_lock" || bad "export needs_phy_setup_lock"
grep -q 'export function acquire_hostapd_phy_lock' "$lock_uc" && ok "export acquire_hostapd_phy_lock" || bad "export acquire_hostapd_phy_lock"
grep -q 'export function try_acquire_phy_setup_lock' "$lock_uc" && ok "export try_acquire" || bad "export try_acquire"
grep -q 'export function release_phy_setup_lock' "$lock_uc" && ok "export release" || bad "export release"
grep -q 'WIFI_PHY_SETUP_SETTLE' "$lock_uc" && ok "settle seam" || bad "settle seam"
grep -q 'WIFI_PHY_SETUP_LOCK_DIR' "$lock_uc" && ok "lock dir seam" || bad "lock dir seam"
grep -q 'never (total disable)' "$lock_uc" && ok "docs MULTI_RADIO=0 total disable" || bad "docs MULTI_RADIO=0"

if grep -Eiq 'band_range|resolve_radio_index|freq_range|radio_band' "$lock_uc"; then
	bad "phy-setup-lock must not include band-resolve"
else
	ok "no band-resolve in phy-setup-lock"
fi

# nl80211 multi check lives only in the module
grep -q 'NL80211_CMD_GET_WIPHY' "$lock_uc" && ok "nl80211 multi check in module" || bad "nl80211 multi check in module"
if grep -q 'NL80211_CMD_GET_WIPHY' "$mac80211_ucode" "$mac80211_sh"; then
	bad "nl80211 multi check duplicated in backends"
else
	ok "backends have no nl80211 multi duplicate"
fi

grep -q 'needs_phy_setup_lock\|acquire_hostapd_phy_lock' "$mac80211_ucode" && ok "ucode uses module gate" || bad "ucode uses module gate"
grep -q 'release_phy_setup_lock' "$mac80211_ucode" && ok "ucode releases lock" || bad "ucode releases lock"

grep -q 'acquire_hostapd_phy_lock' "$mac80211_sh" && ok "shell calls acquire_hostapd_phy_lock" || bad "shell calls acquire_hostapd_phy_lock"
grep -q 'mac80211_phy_setup_lock_acquire' "$mac80211_sh" && ok "shell acquire helper" || bad "shell acquire helper"
grep -q 'mac80211_phy_setup_lock_release' "$mac80211_sh" && ok "shell release helper" || bad "shell release helper"

if grep -n 'hostapd_set_config' -A40 "$mac80211_sh" | grep -q 'mac80211_phy_setup_lock_release 0'; then
	ok "shell failure path skips settle"
else
	bad "shell failure path skips settle"
fi

hostapd_uc="$repo_root/package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/hostapd.uc"
if grep -n 'hostapd.setup' -A5 "$mac80211_ucode" | grep -q 'release_phy_setup_lock(phy_setup_lock, ok ? null : 0)'; then
	ok "ucode failure path skips settle"
else
	bad "ucode failure path skips settle"
fi
if grep -n 'config_set' -A12 "$hostapd_uc" | grep -q 'return true' && \
   grep -n 'HOSTAPD_START_FAILED' -A2 "$hostapd_uc" | grep -q 'return false'; then
	ok "hostapd.setup returns success bool"
else
	bad "hostapd.setup returns success bool"
fi

if grep -n 'wifi-.*setup-lock' "$mac80211_ucode" "$mac80211_sh" | grep -v phy-setup-lock | grep -q mkdir; then
	bad "inline mkdir setup-lock still present"
else
	ok "no inline mkdir setup-lock duplicate"
fi

grep -q 'PHY_SETUP_LOCK_SCRIPT' "$mac80211_sh" && ok "shell PHY_SETUP_LOCK_SCRIPT seam" || bad "shell PHY_SETUP_LOCK_SCRIPT seam"

# --- 2. Behaviour (requires ucode + nl80211) ------------------------------

if ! command -v ucode >/dev/null 2>&1; then
	ok "ucode tests skipped (ucode not installed)"
elif ! ucode -e 'import * as nl80211 from "nl80211"' >/dev/null 2>&1; then
	ok "ucode tests skipped (no nl80211 module)"
else
	work=$(mktemp -d)
	trap 'rm -rf "$work"' EXIT
	mkdir -p "$work/sys/phy0" "$work/locks"

	printf 'aa:bb:cc:dd:ee:01\n' >"$work/sys/phy0/addresses"
	out=$(IEEE80211_SYSFS="$work/sys" WIFI_PHY_SETUP_LOCK_DIR="$work/locks" WIFI_PHY_SETUP_SETTLE=0 \
		ucode - <<EOF
import { phy_is_multi_radio, needs_phy_setup_lock, acquire_hostapd_phy_lock } from "${lock_uc}";
print(phy_is_multi_radio("phy0") ? "multi" : "single");
print(needs_phy_setup_lock("phy0") ? "need" : "skip");
let p = acquire_hostapd_phy_lock("phy0");
print(p == null ? "nolock" : "locked");
EOF
)
	# single address: phy_is_multi false; needs may still be true if host has real nl phys named phy0 — force off nl via MULTI? 
	# On host without matching wiphy, nl returns false → skip.
	expect_eq "single-radio gate" "$(printf '%s' "$out" | tr '\n' ' ' | sed 's/ *$//')" "single skip nolock"

	printf 'aa:bb:cc:dd:ee:01\naa:bb:cc:dd:ee:02\naa:bb:cc:dd:ee:03\n' >"$work/sys/phy0/addresses"
	out=$(IEEE80211_SYSFS="$work/sys" WIFI_PHY_SETUP_LOCK_DIR="$work/locks" WIFI_PHY_SETUP_SETTLE=0 \
		WIFI_PHY_SETUP_LOCK_WAIT=2 ucode - <<EOF
import {
	phy_is_multi_radio, acquire_hostapd_phy_lock, release_phy_setup_lock, phy_setup_lock_path
} from "${lock_uc}";
print(phy_is_multi_radio("phy0") ? "multi" : "single");
let p = acquire_hostapd_phy_lock("phy0");
print(p != null ? "got" : "fail");
release_phy_setup_lock(p, 0);
EOF
)
	expect_eq "multi-radio detected" "$(printf '%s\n' "$out" | sed -n '1p')" "multi"
	expect_eq "acquire lock" "$(printf '%s\n' "$out" | sed -n '2p')" "got"
	[ ! -d "$work/locks/wifi-phy0.setup-lock" ] && ok "release removed lock dir" || bad "release removed lock dir"

	out=$(WIFI_PHY_SETUP_MULTI_RADIO=1 WIFI_PHY_SETUP_LOCK_DIR="$work/locks" WIFI_PHY_SETUP_SETTLE=0 \
		ucode - <<EOF
import { try_acquire_phy_setup_lock } from "${lock_uc}";
let p = try_acquire_phy_setup_lock("bad phy;rm -rf");
print(p == null ? "reject" : "bad");
EOF
)
	expect_eq "reject unsafe phy name" "$out" "reject"

	rm -f "$work/sys/phy0/addresses"
	out=$(WIFI_PHY_SETUP_MULTI_RADIO=1 WIFI_PHY_SETUP_LOCK_DIR="$work/locks" WIFI_PHY_SETUP_SETTLE=0 \
		IEEE80211_SYSFS="$work/sys" ucode - <<EOF
import { acquire_hostapd_phy_lock, release_phy_setup_lock, needs_phy_setup_lock } from "${lock_uc}";
print(needs_phy_setup_lock("phy0") ? "need" : "skip");
let p = acquire_hostapd_phy_lock("phy0");
print(p != null ? "forced" : "fail");
release_phy_setup_lock(p, 0);
EOF
)
	expect_eq "MULTI_RADIO=1 forces lock" "$(printf '%s' "$out" | tr '\n' ' ' | sed 's/ *$//')" "need forced"

	# Total disable even with multi addresses
	printf 'aa:bb:cc:dd:ee:01\naa:bb:cc:dd:ee:02\n' >"$work/sys/phy0/addresses"
	out=$(WIFI_PHY_SETUP_MULTI_RADIO=0 IEEE80211_SYSFS="$work/sys" WIFI_PHY_SETUP_LOCK_DIR="$work/locks" \
		WIFI_PHY_SETUP_SETTLE=0 ucode - <<EOF
import { needs_phy_setup_lock, acquire_hostapd_phy_lock } from "${lock_uc}";
print(needs_phy_setup_lock("phy0") ? "need" : "skip");
let p = acquire_hostapd_phy_lock("phy0");
print(p == null ? "nolock" : "locked");
EOF
)
	expect_eq "MULTI_RADIO=0 total disable" "$(printf '%s' "$out" | tr '\n' ' ' | sed 's/ *$//')" "skip nolock"
fi

printf 'phy-setup-lock: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

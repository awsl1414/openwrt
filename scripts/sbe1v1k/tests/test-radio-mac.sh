#!/bin/sh
# Host tests for per-radio hwmac ↔ radio index (Option B).
#
# Single implementation under test: radio-mac.uc
# Shell mac80211_resolve_radio must call that module (no parallel grep math).
#
set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tests_dir/../../.." && pwd)
radio_mac="$repo_root/package/network/config/wifi-scripts/files/usr/share/hostap/radio-mac.uc"
mac80211_sh="$repo_root/package/network/config/wifi-scripts/files/lib/netifd/wireless/mac80211.sh"
mac80211_uc="$repo_root/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

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

# --- 1. API / contracts ---------------------------------------------------

grep -q 'export function radio_index_by_mac' "$radio_mac" && ok "export radio_index_by_mac" || bad "export radio_index_by_mac"
grep -q 'export function read_phy_addresses' "$radio_mac" && ok "export read_phy_addresses" || bad "export read_phy_addresses"
grep -q 'export function normalize_mac' "$radio_mac" && ok "export normalize_mac" || bad "export normalize_mac"
grep -q 'export function fill_missing_band_from_board' "$radio_mac" && ok "export fill_missing_band_from_board" || bad "export fill_missing_band_from_board"
grep -q 'export function board_band_defaults' "$radio_mac" && ok "export board_band_defaults" || bad "export board_band_defaults"
grep -q 'export function radio_htmode' "$radio_mac" && ok "export radio_htmode" || bad "export radio_htmode"
grep -q 'BOARD_JSON' "$radio_mac" && ok "BOARD_JSON test seam" || bad "BOARD_JSON test seam"
grep -q 'addresses\[i\]' "$radio_mac" && ok "documents addresses[i] ↔ radio index" || bad "addresses[i] contract comment"
grep -q 'hwmac' "$radio_mac" && ok "documents hwmac UCI field" || bad "hwmac UCI field docs"
grep -q 'Allowed UCI repair' "$radio_mac" && ok "documents UCI band repair boundary" || bad "documents UCI band repair boundary"

# No band→index resolution / path matching.  fill_missing_band_* is UCI repair only.
if grep -Eiq 'freq_range|path_match|phy_path|resolve_sysfs' "$radio_mac"; then
	bad "radio-mac.uc must not grow path/freq_range fallbacks"
elif grep -Eiq 'radio_index_by_mac.*band|resolve.*by.*band' "$radio_mac"; then
	bad "radio-mac.uc must not resolve index by band"
else
	ok "radio-mac.uc has no path/band-index fallbacks"
fi

grep -q 'config_add_string hwmac' "$mac80211_sh" && ok "shell registers hwmac" || bad "shell registers hwmac"
grep -q 'RADIO_MAC_SCRIPT' "$mac80211_sh" && ok "shell resolve uses RADIO_MAC_SCRIPT" || bad "shell RADIO_MAC_SCRIPT"
grep -q 'radio_index_by_mac' "$mac80211_sh" && ok "shell resolve calls radio_index_by_mac" || bad "shell calls radio_index_by_mac"
grep -q 'mac80211_persist_repaired_band' "$mac80211_sh" && ok "shell persist helper" || bad "shell persist helper"
if grep -n 'mac80211_persist_repaired_band' -A12 "$mac80211_sh" | grep -q 'A-Za-z0-9_'; then
	ok "shell persist validates section name"
else
	bad "shell persist validates section name"
fi
if grep -n 'wireless_set_up' -A2 "$mac80211_sh" | grep -q 'mac80211_persist_repaired_band'; then
	ok "shell persists band after wireless_set_up"
else
	bad "shell persists band after wireless_set_up"
fi

mac80211_ucode="$repo_root/package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh"
grep -q 'persist_repaired_band' "$mac80211_ucode" && ok "ucode persist helper" || bad "ucode persist helper"
if grep -n 'netifd.set_up' -A3 "$mac80211_ucode" | grep -q 'persist_repaired_band'; then
	ok "ucode persists band after set_up"
else
	bad "ucode persists band after set_up"
fi

# No divergent line-number grep resolve left.
if grep -n 'mac80211_resolve_radio' -A20 "$mac80211_sh" | grep -q 'grep -nixFi'; then
	bad "shell still has grep -nixFi resolve (must use radio-mac.uc)"
else
	ok "shell resolve has no grep -nixFi duplicate"
fi

# find_phy: macaddr → macaddress only; hwmac → addresses
if grep -n '\[ -n "\$macaddr" \]' -A6 "$mac80211_sh" | head -n8 | grep -q 'addresses'; then
	bad "find_phy macaddr must not scan addresses (use hwmac)"
else
	ok "find_phy macaddr is macaddress-only"
fi
grep -n '\[ -n "\$hwmac" \]' -A5 "$mac80211_sh" | grep -q 'addresses' \
	&& ok "find_phy hwmac scans addresses" || bad "find_phy hwmac scans addresses"

grep -q 'find_device_by_hwmac' "$mac80211_uc" && ok "mac80211.uc find_device_by_hwmac" || bad "find_device_by_hwmac"
grep -q 'find_legacy_device' "$mac80211_uc" && ok "mac80211.uc find_legacy_device" || bad "find_legacy_device"
grep -q "uci_set(name, \"hwmac\"" "$mac80211_uc" && ok "mac80211.uc writes hwmac" || bad "writes hwmac"
grep -q 'radio_htmode' "$mac80211_uc" && ok "mac80211.uc uses radio_htmode" || bad "mac80211.uc uses radio_htmode"
if grep -q 'import { normalize_mac, radio_htmode }' "$mac80211_uc"; then
	ok "mac80211.uc imports radio_htmode from radio-mac"
else
	bad "mac80211.uc imports radio_htmode from radio-mac"
fi
if grep -q '^function radio_htmode' "$mac80211_uc" || grep -q '^const htmode_order' "$mac80211_uc"; then
	bad "mac80211.uc must not keep local radio_htmode duplicate"
else
	ok "mac80211.uc has no local radio_htmode duplicate"
fi

if grep -q "uci_set(name, \"macaddr\"" "$mac80211_uc" || grep -q "\.macaddr='" "$mac80211_uc"; then
	bad "mac80211.uc must not set wifi-device.macaddr for identity"
else
	ok "mac80211.uc does not stamp device macaddr"
fi

if grep -A15 'function find_legacy_device' "$mac80211_uc" | grep -q 'normalize_mac(s.hwmac)'; then
	ok "legacy adopt skips sections with hwmac"
else
	bad "legacy adopt must skip sections with hwmac"
fi

# --- 2. radio-mac.uc behavior (requires ucode) ----------------------------

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT INT TERM
phy_dir="$work/phy0"
mkdir -p "$phy_dir"
printf '%s\n' \
	'aa:bb:cc:dd:ee:01' \
	'' \
	'AA:BB:CC:DD:EE:02' \
	'not-a-mac' \
	'aa:bb:cc:dd:ee:03' >"$phy_dir/addresses"

run_radio_mac() {
	IEEE80211_SYSFS="$work" RADIO_MAC_SCRIPT="$radio_mac" ucode - <<EOF
import { normalize_mac, read_phy_addresses, radio_index_by_mac, phy_has_hwmac } from "${radio_mac}";
print(normalize_mac("AA:BB:CC:DD:EE:01") + "\n");
print(normalize_mac("bad") == null ? "null" : "x");
print("\n");
print(join(",", read_phy_addresses("phy0")) + "\n");
print(radio_index_by_mac("phy0", "aa:bb:cc:dd:ee:02") + "\n");
print(radio_index_by_mac("phy0", "aa:bb:cc:dd:ee:03") + "\n");
print(radio_index_by_mac("phy0", "de:ad:be:ef:00:00") == null ? "null" : "x");
print("\n");
print(phy_has_hwmac("phy0", "aa:bb:cc:dd:ee:01") ? "yes" : "no");
print("\n");
EOF
}

if command -v ucode >/dev/null 2>&1; then
	ucode_out=$(run_radio_mac) || ucode_out=""
	printf '%s\n' "$ucode_out" | sed -n '1p' | grep -qx 'aa:bb:cc:dd:ee:01' \
		&& ok "ucode normalize_mac" || bad "ucode normalize_mac"
	printf '%s\n' "$ucode_out" | sed -n '2p' | grep -qx 'null' \
		&& ok "ucode normalize rejects junk" || bad "ucode normalize rejects junk"
	# Blank/junk lines dropped → indices 0,1,2 for the three valid MACs
	printf '%s\n' "$ucode_out" | sed -n '3p' | grep -qx 'aa:bb:cc:dd:ee:01,aa:bb:cc:dd:ee:02,aa:bb:cc:dd:ee:03' \
		&& ok "ucode read filters blank/junk" || bad "ucode read filters ($ucode_out)"
	printf '%s\n' "$ucode_out" | sed -n '4p' | grep -qx '1' \
		&& ok "ucode index MAC02 -> 1" || bad "ucode index MAC02"
	printf '%s\n' "$ucode_out" | sed -n '5p' | grep -qx '2' \
		&& ok "ucode index MAC03 -> 2" || bad "ucode index MAC03"
	printf '%s\n' "$ucode_out" | sed -n '6p' | grep -qx 'null' \
		&& ok "ucode miss -> null" || bad "ucode miss"
	printf '%s\n' "$ucode_out" | sed -n '7p' | grep -qx 'yes' \
		&& ok "ucode phy_has_hwmac" || bad "ucode phy_has_hwmac"

	# Source production mac80211_resolve_radio (no local reimplementation).
	# shellcheck disable=SC1090
	eval "$(sed -n '/^mac80211_resolve_radio()/,/^}/p' "$mac80211_sh")"

	export IEEE80211_SYSFS="$work"
	export RADIO_MAC_SCRIPT="$radio_mac"

	phy=phy0
	hwmac='AA:BB:CC:DD:EE:02'
	radio=99
	mac80211_resolve_radio
	expect_eq "shell resolve matches ucode (MAC02->1)" "$radio" "1"

	hwmac='aa:bb:cc:dd:ee:03'
	radio=99
	mac80211_resolve_radio
	expect_eq "shell resolve matches ucode (MAC03->2)" "$radio" "2"

	hwmac='de:ad:be:ef:00:00'
	radio=7
	mac80211_resolve_radio
	expect_eq "shell resolve miss leaves radio" "$radio" "7"

	printf '%s\n' \
		'aa:bb:cc:dd:ee:03' \
		'aa:bb:cc:dd:ee:01' \
		'aa:bb:cc:dd:ee:02' >"$phy_dir/addresses"
	hwmac='aa:bb:cc:dd:ee:01'
	radio=99
	mac80211_resolve_radio
	expect_eq "shell resolve after shuffle MAC01->1" "$radio" "1"

	# board.json band repair (BOARD_JSON seam)
	cat >"$work/board.json" <<'JSON'
{
  "wlan": {
    "wl0": {
      "info": {
        "bands": {
          "5G": { "ht": true, "he": true, "eht": true, "max_width": 160 }
        },
        "radios": [
          {
            "index": 2,
            "hwmac": "aa:bb:cc:dd:ee:02",
            "bands": { "5G": { "default_channel": 36 } }
          }
        ]
      }
    }
  }
}
JSON
	band_out=$(BOARD_JSON="$work/board.json" RADIO_MAC_SCRIPT="$radio_mac" ucode - <<EOF
import { board_band_defaults, fill_missing_band_from_board, radio_htmode } from "${radio_mac}";
let d = board_band_defaults("AA:BB:CC:DD:EE:02");
print((d?.band ?? "null") + "\n");
print((d?.channel ?? "null") + "\n");
print((d?.htmode ?? "null") + "\n");
let cfg = { hwmac: "aa:bb:cc:dd:ee:02" };
print(fill_missing_band_from_board(cfg) ? "yes" : "no");
print("\n");
print(cfg.band + "," + cfg.channel + "," + cfg.htmode + "\n");
print(fill_missing_band_from_board(cfg) ? "yes" : "no");
print("\n");
print(radio_htmode("2G", { he: true, eht: true, max_width: 40 }) + "\n");
print(board_band_defaults("de:ad:be:ef:00:00") == null ? "null" : "x");
print("\n");
EOF
) || band_out=""
	printf '%s\n' "$band_out" | sed -n '1p' | grep -qx '5g' \
		&& ok "ucode board_band_defaults band" || bad "ucode board_band_defaults band ($band_out)"
	printf '%s\n' "$band_out" | sed -n '2p' | grep -qx '36' \
		&& ok "ucode board_band_defaults channel" || bad "ucode board_band_defaults channel"
	printf '%s\n' "$band_out" | sed -n '3p' | grep -qx 'EHT80' \
		&& ok "ucode board_band_defaults htmode cap 80" || bad "ucode board_band_defaults htmode"
	printf '%s\n' "$band_out" | sed -n '4p' | grep -qx 'yes' \
		&& ok "ucode fill_missing_band applies" || bad "ucode fill_missing_band applies"
	printf '%s\n' "$band_out" | sed -n '5p' | grep -qx '5g,36,EHT80' \
		&& ok "ucode fill_missing_band values" || bad "ucode fill_missing_band values"
	printf '%s\n' "$band_out" | sed -n '6p' | grep -qx 'no' \
		&& ok "ucode fill_missing_band idempotent" || bad "ucode fill_missing_band idempotent"
	printf '%s\n' "$band_out" | sed -n '7p' | grep -qx 'EHT20' \
		&& ok "ucode radio_htmode 2G width 20" || bad "ucode radio_htmode 2G"
	printf '%s\n' "$band_out" | sed -n '8p' | grep -qx 'null' \
		&& ok "ucode board_band_defaults miss" || bad "ucode board_band_defaults miss"
else
	ok "ucode tests skipped (ucode not installed)"
fi

# --- 3. config mapping decision table (hwmac) -----------------------------

normalize_mac() {
	echo "$1" | tr 'A-Z' 'a-z' | grep -E '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$' || true
}

# name|band|radio|hwmac|phy
find_by_hwmac() {
	want=$(normalize_mac "$1")
	[ -n "$want" ] || return 0
	printf '%s\n' "$sections" | while IFS='|' read -r name band radio hwmac phy; do
		got=$(normalize_mac "$hwmac")
		[ "$got" = "$want" ] && echo "$name" && break
	done
}

find_legacy() {
	want_band=$1
	want_phy=$2
	printf '%s\n' "$sections" | while IFS='|' read -r name band radio hwmac phy; do
		[ -z "$(normalize_mac "$hwmac")" ] || continue
		[ "$band" = "$want_band" ] || continue
		[ "$phy" = "$want_phy" ] || continue
		echo "$name"
		break
	done
}

sections=$(printf '%s\n' \
	'radio0|2g|0|aa:bb:cc:dd:ee:01|wl0' \
	'radio1|5g|1|aa:bb:cc:dd:ee:02|wl0' \
	'radio2|6g|2|aa:bb:cc:dd:ee:03|wl0')

expect_eq "map hit hwmac01 -> radio0" "$(find_by_hwmac 'AA:BB:CC:DD:EE:01')" "radio0"
expect_eq "map miss unknown" "$(find_by_hwmac 'de:ad:be:ef:00:00')" ""
expect_eq "shuffle still binds 2g" "$(find_by_hwmac 'aa:bb:cc:dd:ee:01')" "radio0"

sections=$(printf '%s\n' \
	'radio0|2g|0||wl0' \
	'radio1|5g|1|aa:bb:cc:dd:ee:02|wl0')
expect_eq "legacy adopts empty 2g" "$(find_legacy 2g wl0)" "radio0"
expect_eq "legacy refuses occupied 5g" "$(find_legacy 5g wl0)" ""

printf 'radio-mac: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

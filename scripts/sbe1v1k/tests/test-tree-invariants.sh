#!/bin/sh
# Host-side invariants for the SBE1V1K bring-up tree (no device required).
set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tests_dir/../../.." && pwd)
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

require_file() {
	if [ -f "$repo_root/$1" ]; then
		ok "file $1"
	else
		bad "missing $1"
	fi
}

require_grep() {
	file=$1
	pattern=$2
	label=$3
	if grep -qE "$pattern" "$repo_root/$file"; then
		ok "$label"
	else
		bad "$label (no match in $file)"
	fi
}

cd "$repo_root"

require_file "target/linux/qualcommbe/dts/ipq9570-sbe1v1k.dts"
require_file "package/firmware/ipq-wifi/src/board-askey_sbe1v1k.qcn9274"
require_file "target/linux/qualcommbe/ipq95xx/base-files/etc/hotplug.d/firmware/11-ath12k-caldata"
require_file "target/linux/qualcommbe/ipq95xx/base-files/lib/upgrade/platform.sh"
require_file "target/linux/qualcommbe/ipq95xx/base-files/etc/uci-defaults/99-askey-sbe1v1k-enable-2g-wifi"
require_file "scripts/sbe1v1k/minimal.config"
require_file "scripts/sbe1v1k/build-arch.sh"
require_file "package/kernel/mac80211/patches/ath12k/400-wifi-ath12k-set-per-radio-MAC-address-from-DT.patch"
require_file "target/linux/qualcommbe/patches-6.18/0362-net-ethernet-qualcomm-ppe-fix-rx-dma-mapping-direction.patch"
require_file "target/linux/qualcommbe/patches-6.18/0410-net-ethernet-qualcomm-ppe-fix-freed-skb-reuse-in-rx-reaping.patch"

require_grep "target/linux/qualcommbe/image/ipq95xx.mk" \
	'Device/askey_sbe1v1k' \
	"Device/askey_sbe1v1k in ipq95xx.mk"
require_grep "target/linux/qualcommbe/image/ipq95xx.mk" \
	'TARGET_DEVICES \+= askey_sbe1v1k' \
	"TARGET_DEVICES includes askey_sbe1v1k"
require_grep "target/linux/qualcommbe/ipq95xx/base-files/etc/board.d/02_network" \
	'ucidef_set_wireless \"2g\"' \
	"board.d seeds 2.4 GHz wireless defaults"
require_grep "target/linux/qualcommbe/ipq95xx/base-files/etc/board.d/02_network" \
	'ucidef_add_wlan' \
	"board.d registers multi-path wlan"
require_grep "target/linux/qualcommbe/ipq95xx/base-files/lib/upgrade/platform.sh" \
	'askey,sbe1v1k' \
	"platform.sh handles askey,sbe1v1k"
require_grep "scripts/sbe1v1k/minimal.config" \
	'^CONFIG_TARGET_qualcommbe_ipq95xx_DEVICE_askey_sbe1v1k=y' \
	"seed enables DEVICE askey_sbe1v1k"
require_grep "scripts/sbe1v1k/minimal.config" \
	'^CONFIG_PACKAGE_luci-ssl=y' \
	"seed enables luci-ssl"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'prune_stale_feed_symlinks' \
	"build-arch prunes stale feed symlinks"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'^USE_PROXY=0$' \
	"build-arch proxy defaults off"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'PROXY_PORT="\$\{PROXY_PORT:-7897\}"' \
	"build-arch default proxy port 7897"
require_grep "package/kernel/mac80211/Makefile" \
	'^PKG_RELEASE:=' \
	"mac80211 PKG_RELEASE present"

if command -v bash >/dev/null 2>&1; then
	if bash -n "$repo_root/scripts/sbe1v1k/build-arch.sh"; then
		ok "build-arch.sh bash -n"
	else
		bad "build-arch.sh bash -n"
	fi
else
	ok "build-arch.sh bash -n skipped (no bash)"
fi

printf 'tree-invariants: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

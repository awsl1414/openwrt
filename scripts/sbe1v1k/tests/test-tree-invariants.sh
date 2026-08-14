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
	if grep -qE -e "$pattern" -- "$repo_root/$file"; then
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
require_file "target/linux/qualcommbe/ipq95xx/base-files/usr/bin/sbe1v1k-diag"
require_file "scripts/sbe1v1k/daily.config"
require_file "scripts/sbe1v1k/minimal.config"
require_file "scripts/sbe1v1k/build-arch.sh"
require_file "target/linux/qualcommbe/ipq95xx/base-files/etc/uci-defaults/zz-askey-sbe1v1k-luci-zh"
require_file "package/kernel/mac80211/patches/ath12k/400-wifi-ath12k-set-per-radio-MAC-address-from-DT.patch"
require_file "package/network/config/wifi-scripts/files/usr/share/hostap/radio-mac.uc"
require_file "package/network/config/wifi-scripts/files/usr/share/hostap/phy-setup-lock.uc"
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
require_grep "target/linux/qualcommbe/ipq95xx/base-files/etc/board.d/02_network" \
	'ucidef_set_country \"US\"' \
	"board.d defaults country US"
require_grep "package/base-files/files/bin/config_generate" \
	'lan\) ipad=\$\{ipaddr:-\"192\.168\.255\.1\"\}' \
	"default LAN IP is 192.168.255.1"
require_grep "package/base-files/image-config.in" \
	'default \"192\.168\.255\.1\"' \
	"preinit Kconfig default IP is 192.168.255.1"
require_file "README.zh-CN.md"
require_file "README.en.md"
require_file "README-OpenWrt.md"
require_grep "README.md" \
	'192\.168\.255\.1' \
	"top README documents 192.168.255.1"
require_grep "README.zh-CN.md" \
	'192\.168\.255\.1' \
	"zh-CN README documents 192.168.255.1"
require_grep "README.en.md" \
	'192\.168\.255\.1' \
	"en README documents 192.168.255.1"
require_grep "target/linux/qualcommbe/ipq95xx/base-files/lib/upgrade/platform.sh" \
	'askey,sbe1v1k' \
	"platform.sh handles askey,sbe1v1k"
require_grep "scripts/sbe1v1k/daily.config" \
	'^CONFIG_TARGET_qualcommbe_ipq95xx_DEVICE_askey_sbe1v1k=y' \
	"daily seed enables DEVICE askey_sbe1v1k"
require_grep "scripts/sbe1v1k/daily.config" \
	'^CONFIG_PACKAGE_luci-ssl=y' \
	"daily seed enables luci-ssl"
require_grep "scripts/sbe1v1k/daily.config" \
	'^CONFIG_LUCI_LANG_zh_Hans=y' \
	"daily seed enables LuCI Simplified Chinese"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'SEED_CONFIG="\$\{SEED_CONFIG:-\$SCRIPT_DIR/daily.config\}"' \
	"build-arch defaults to daily.config"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'--minimal' \
	"build-arch supports --minimal"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'^THEMES=0' \
	"build-arch themes default off"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'COMMUNITY_THEME_REPOS' \
	"build-arch lists COMMUNITY_THEME_REPOS"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'init_community_theme_packages' \
	"build-arch derives theme packages from REPOS"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'prune_community_theme_trees' \
	"build-arch prunes theme trees without --themes"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'prune_config_backups' \
	"build-arch rotates .config.bak.*"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'apply_community_themes_config' \
	"build-arch applies themes via --themes"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'e10bd0969c4978ad41495f7e53ac6fd162dda113' \
	"aurora theme commit pinned"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'luci-app-argon-config' \
	"build-arch includes argon-config (official zh via po/zh_Hans)"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'3e099a37c3f71d0de677f1b6b0f4bffd57d91dac' \
	"argon-config commit pinned"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'COMMUNITY_THEME_I18N' \
	"build-arch derives zh-cn i18n only from upstream po/"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'po/zh_Hans' \
	"build-arch detects official zh_Hans before enabling i18n"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'no upstream po/zh_Hans' \
	"build-arch skips zh-cn when upstream has no po"
# Must not hardcode theme-shell i18n (aurora/argon/alpha have no po/); argon-config is OK.
if grep -qE 'luci-i18n-(aurora|argon|alpha)-zh-cn' \
	"$repo_root/scripts/sbe1v1k/build-arch.sh"; then
	bad "build-arch must not hardcode theme-shell luci-i18n-*-zh-cn"
else
	ok "build-arch does not hardcode theme-shell zh-cn i18n"
fi
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'assert_no_community_themes_in_config' \
	"build-arch refuses leftover themes without --themes"
require_grep "scripts/sbe1v1k/build-arch.sh" \
	'theme_i18n_package' \
	"build-arch asserts leftover theme i18n via theme_i18n_package"
# Guard against set -e abort: false ((KEEP_CONFIG)) && … as last stmt in a function.
if grep -nE '^\s*\(\(KEEP_CONFIG\)\)\s*&&' "$repo_root/scripts/sbe1v1k/build-arch.sh" \
	| grep -q .; then
	bad "build-arch must not use ((KEEP_CONFIG)) && as a bare statement"
else
	ok "build-arch avoids ((KEEP_CONFIG)) && under set -e"
fi
# --skip-themes must not exist (opt-in only via --themes)
if grep -qE -e '--skip-themes' "$repo_root/scripts/sbe1v1k/build-arch.sh"; then
	bad "build-arch must not keep --skip-themes"
else
	ok "build-arch has no --skip-themes"
fi
# OpenWrt has no make olddefconfig target (%:: recurses and fails).
if grep -E '^[[:space:]]*make[[:space:]]+olddefconfig' "$repo_root/scripts/sbe1v1k/build-arch.sh" \
	| grep -qvE '^[[:space:]]*#'; then
	bad "build-arch must use make defconfig, not olddefconfig"
else
	ok "build-arch does not call make olddefconfig"
fi
# No hand-maintained package list parallel to REPOS (only empty init + derive).
if grep -nE '^COMMUNITY_THEME_PACKAGES=\(' "$repo_root/scripts/sbe1v1k/build-arch.sh" \
	| grep -v 'COMMUNITY_THEME_PACKAGES=()' | grep -q .; then
	bad "COMMUNITY_THEME_PACKAGES must be derived from REPOS, not a second list"
else
	ok "COMMUNITY_THEME_PACKAGES derived from REPOS only"
fi
# daily seed must not force community themes / theme config apps
if grep -qE \
	-e '^CONFIG_PACKAGE_luci-theme-(aurora|argon|alpha)=y' \
	-e '^CONFIG_PACKAGE_luci-app-(argon|alpha)-config=y' \
	"$repo_root/scripts/sbe1v1k/daily.config"; then
	bad "daily.config must not enable community themes (use --themes)"
else
	ok "daily.config has no community theme packages"
fi
# Prefer if ((#I18N)); then …; fi over ((#)) && under set -e.
if grep -nE 'COMMUNITY_THEME_I18N\[@\]\)\)\s*&&' \
	"$repo_root/scripts/sbe1v1k/build-arch.sh" | grep -q .; then
	bad "build-arch must not use ((#COMMUNITY_THEME_I18N)) && under set -e"
else
	ok "build-arch uses if for COMMUNITY_THEME_I18N under set -e"
fi
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
require_grep "package/network/config/wifi-scripts/Makefile" \
	'^PKG_RELEASE:=6$' \
	"wifi-scripts PKG_RELEASE after dropping setup band repair"
require_file "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch"
require_grep "package/network/utils/iwinfo/Makefile" \
	'^PKG_RELEASE:=4$' \
	"libiwinfo PKG_RELEASE for multi-radio UCI hwmac"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'nl80211_phy_idx_from_hwmac' \
	"iwinfo resolves wifi-device via hwmac"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'nl80211_is_hwmac' \
	"iwinfo validates hex hwmac like radio-mac.uc"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'FREQ_RANGE may appear multiple times' \
	"iwinfo filters freqlist by WIPHY_RADIO ranges"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'keep unfiltered phy-wide list' \
	"iwinfo soft-falls back when WIPHY_RADIOS missing"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'nl80211_want_radio' \
	"iwinfo selects radio filter for UCI/netdev"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'nl80211_phy_mac_at' \
	"iwinfo shares addresses[] MAC lookup"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'Never fall back to the lowest ifindex' \
	"phy2ifname does not fall back to wrong radio iface"
require_grep "package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch" \
	'hwmac_out' \
	"uci_ex returns hwmac without second UCI open"
if [ -f "$repo_root/package/network/utils/iwinfo/patches/102-uci-hwmac-phy2ifname-radio.patch" ]; then
	bad "102 patch merged into 101"
else
	ok "no split 102 patch leftover"
fi
if grep -q 'nl80211_uci_want_mac\|nl80211_freqlist_want_radio' \
	"$repo_root/package/network/utils/iwinfo/patches/101-uci-hwmac-freqlist-radio.patch"
then
	bad "old duplicate helpers removed from 101"
else
	ok "no duplicate uci_want_mac/freqlist_want_radio helpers"
fi
require_grep "package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc" \
	'Incomplete sections \(missing band\)' \
	"mac80211.uc repairs missing wifi-device.band on wifi config"
require_grep "package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc" \
	'create_name_order = \[ "2G", "5G", "6G" \]' \
	"mac80211.uc creates radio0=2g radio1=5g radio2=6g"
require_grep "package/network/config/wifi-scripts/files/usr/share/hostap/radio-mac.uc" \
	'export function radio_htmode' \
	"radio-mac.uc exports shared radio_htmode"
require_grep "package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc" \
	'import { normalize_mac, radio_htmode }' \
	"mac80211.uc reuses radio_htmode from radio-mac"
if grep -qE 'fill_missing_band_from_board|board_band_defaults|persist_repaired_band|mac80211_fill_band_from_board' \
	"$repo_root/package/network/config/wifi-scripts/files/usr/share/hostap/radio-mac.uc" \
	"$repo_root/package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh" \
	"$repo_root/package/network/config/wifi-scripts/files/lib/netifd/wireless/mac80211.sh"
then
	bad "setup-time band repair removed (libiwinfo owns freqlist)"
else
	ok "no setup-time band repair leftover"
fi
require_grep "package/network/config/wifi-scripts/files/usr/share/hostap/wifi-detect.uc" \
	'entry\.hwmac' \
	"wifi-detect records per-radio hwmac"
require_grep "package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc" \
	'find_device_by_hwmac' \
	"mac80211.uc matches wifi-device by hwmac"
require_grep "package/network/config/wifi-scripts/files/usr/share/hostap/radio-mac.uc" \
	'IEEE80211_SYSFS' \
	"radio-mac.uc test seam IEEE80211_SYSFS"
require_grep "package/network/config/wifi-scripts/files/lib/netifd/wireless/mac80211.sh" \
	'RADIO_MAC_SCRIPT' \
	"shell resolve uses radio-mac.uc via RADIO_MAC_SCRIPT"
require_grep "package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh" \
	'data\.config\.hwmac' \
	"ucode mac80211 resolves radio from hwmac"
require_grep "package/network/config/wifi-scripts/files-ucode/usr/share/schema/wireless.wifi-device.json" \
	'"hwmac"' \
	"schema documents hwmac"
require_grep "package/network/config/wifi-scripts/files/usr/share/hostap/phy-setup-lock.uc" \
	'needs_phy_setup_lock' \
	"phy-setup-lock.uc exports needs_phy_setup_lock"
require_grep "package/network/config/wifi-scripts/files/usr/share/hostap/phy-setup-lock.uc" \
	'acquire_hostapd_phy_lock' \
	"phy-setup-lock.uc exports acquire_hostapd_phy_lock"
require_grep "package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh" \
	'phy-setup-lock' \
	"ucode mac80211 serializes hostapd via phy-setup-lock"
require_grep "package/network/config/wifi-scripts/files/lib/netifd/wireless/mac80211.sh" \
	'acquire_hostapd_phy_lock' \
	"shell acquire uses acquire_hostapd_phy_lock"
require_grep "package/network/config/wifi-scripts/files/lib/netifd/wireless/mac80211.sh" \
	'PHY_SETUP_LOCK_SCRIPT' \
	"shell hostapd setup uses PHY_SETUP_LOCK_SCRIPT"

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

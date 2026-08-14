'use strict';
/**
 * Multi-radio wiphy: permanent MAC ↔ current radio index.
 *
 * Boundary (this module does NOT):
 *   - pick hardware radio via wifi-device frequency class (Preview 2 /
 *     upstream draft).  Frequency class is capability + hostapd input,
 *     not identity.
 *   - resolve radio index from band, frequency ranges, or device path
 *   - serialize hostapd (see phy-setup-lock.uc)
 *
 * Allowed UCI repair (still keyed by hwmac, not index selection):
 *   - when wifi-device.band was wiped (e.g. LuCI freqlist by section name
 *     fails on multi-radio phys), restore band/channel/htmode from
 *     board.json via the permanent radio MAC.
 *
 * Kernel `/sys/class/ieee80211/<phy>/addresses` lists one permanent MAC per
 * radio, in the same order as `wiphy_radio` indices (ath12k publishes DT
 * per-radio MACs into addresses[i] for radio index i).  That ordering is
 * required: wifi-detect stores addresses[radio.index] as the radio identity.
 *
 * UCI identity field is wifi-device.hwmac (not macaddr — that aliases BSSID).
 * Numeric option radio is refreshed from hwmac on each setup/config.
 *
 * IEEE80211_SYSFS may override the sysfs prefix (host tests only).
 * BOARD_JSON may override /etc/board.json (host tests only).
 */
import { readfile } from "fs";

const ieee80211_root = getenv("IEEE80211_SYSFS") || "/sys/class/ieee80211";
const board_json_path = getenv("BOARD_JSON") || "/etc/board.json";
const board_bands_order = [ "6G", "5G", "2G" ];
const htmode_order = [ "EHT", "HE", "VHT", "HT" ];

/** Shared with mac80211.uc create/sync — keep width caps in one place. */
export function radio_htmode(band_name, band) {
	if (!band)
		return "NOHT";

	let width = band.max_width;
	if (band_name == "2G" || band_name == "2g")
		width = 20;
	else if (width > 80)
		width = 80;

	let htmode = filter(htmode_order, (m) => band[lc(m)])[0];
	return htmode ? htmode + width : "NOHT";
}

export function normalize_mac(mac) {
	if (mac == null)
		return null;
	mac = lc(trim("" + mac));
	return match(mac, /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/) ? mac : null;
}

export function read_phy_addresses(phy) {
	if (!phy)
		return [];

	let raw = trim(readfile(`${ieee80211_root}/${phy}/addresses`) ?? "");
	if (!raw)
		return [];

	return filter(map(split(raw, "\n"), (a) => normalize_mac(a)), (a) => a != null);
}

export function radio_index_by_mac(phy, mac) {
	mac = normalize_mac(mac);
	if (!phy || !mac)
		return null;

	let addrs = read_phy_addresses(phy);
	for (let i = 0; i < length(addrs); i++)
		if (addrs[i] == mac)
			return i;

	return null;
}

/** True if hwmac appears in this phy's addresses[] (any index). */
export function phy_has_hwmac(phy, mac) {
	return radio_index_by_mac(phy, mac) != null;
}

/**
 * Look up band/channel/htmode defaults for a permanent radio MAC from board.json.
 * Used when UCI lost option band (e.g. LuCI frequency widget saved empty
 * because iwinfo freqlist does not accept wifi-device section names).
 */
export function board_band_defaults(hwmac) {
	hwmac = normalize_mac(hwmac);
	if (!hwmac)
		return null;

	let board = json(readfile(board_json_path) ?? "{}");
	for (let _name, phy in board.wlan ?? {}) {
		for (let radio in phy?.info?.radios ?? []) {
			if (normalize_mac(radio.hwmac) != hwmac)
				continue;

			let band_name = filter(board_bands_order, (b) => radio.bands?.[b])[0];
			if (!band_name)
				return null;

			let ch = radio.bands[band_name].default_channel ?? "auto";
			return {
				band: lc(band_name),
				channel: "" + ch,
				htmode: radio_htmode(band_name, phy?.info?.bands?.[band_name])
			};
		}
	}

	return null;
}

/**
 * If config.band is missing, fill band/channel/htmode from board.json via hwmac.
 * Returns true when config was modified.
 */
export function fill_missing_band_from_board(config) {
	if (!config || config.band)
		return false;

	let d = board_band_defaults(config.hwmac);
	if (!d)
		return false;

	config.band = d.band;
	if (config.channel == null || config.channel == "" || config.channel == "0")
		config.channel = d.channel;
	if (!config.htmode && d.htmode)
		config.htmode = d.htmode;

	return true;
}

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
 *   - restore wiped wifi-device.band (libiwinfo must resolve UCI section
 *     names via hwmac + WIPHY_RADIO freqlist; see iwinfo 101 patch)
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
 */
import { readfile } from "fs";

const ieee80211_root = getenv("IEEE80211_SYSFS") || "/sys/class/ieee80211";
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

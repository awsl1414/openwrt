#!/usr/bin/env ucode
import { readfile } from "fs";
import * as uci from 'uci';
import { normalize_mac } from "/usr/share/hostap/radio-mac.uc";

const bands_order = [ "6G", "5G", "2G" ]; /* pick label when one radio lists several bands */
/*
 * First-create wifi-device section order only (radio0=2g, radio1=5g, radio2=6g).
 * Not identity — that is hwmac.  Does not affect setup radio-index resolution.
 */
const create_name_order = [ "2G", "5G", "6G" ];
const htmode_order = [ "EHT", "HE", "VHT", "HT" ];
const ieee80211_root = getenv("IEEE80211_SYSFS") || "/sys/class/ieee80211";

let board = json(readfile("/etc/board.json"));
if (!board.wlan)
	exit(0);

let idx = 0;
let commit;

let config = uci.cursor().get_all("wireless") ?? {};

function path_matches(section_path, path) {
	if (!section_path || !path)
		return false;
	if (type(path) == "array") {
		for (let p in path)
			if (p && substr(section_path, -length(p)) == p)
				return true;
		return false;
	}
	return substr(section_path, -length(path)) == path;
}

function device_on_phy(s, phy_name, path) {
	if (s.phy && s.phy == phy_name)
		return true;
	return path_matches(s.path, path);
}

/* Legacy dedup when per-radio hwmac is unavailable. */
function radio_exists_by_index(path, phy_mac, phy_name, radio) {
	for (let name, s in config) {
		if (s[".type"] != "wifi-device")
			continue;
		if (radio != null && int(s.radio) != radio)
			continue;
		if (s.macaddr && phy_mac && lc(s.macaddr) == lc(phy_mac))
			return name;
		if (device_on_phy(s, phy_name, path))
			return name;
	}
	return null;
}

function find_device_by_hwmac(mac) {
	mac = normalize_mac(mac);
	if (!mac)
		return null;

	for (let name, s in config) {
		if (s[".type"] != "wifi-device")
			continue;
		if (normalize_mac(s.hwmac) == mac)
			return name;
	}
	return null;
}

/*
 * One-shot adoption of a pre-hwmac section: same phy, same band, no hwmac yet.
 * Does not touch sections that already have a permanent hwmac.
 */
function find_legacy_device(phy_name, path, band) {
	for (let name, s in config) {
		if (s[".type"] != "wifi-device")
			continue;
		if (normalize_mac(s.hwmac))
			continue;
		if (lc(s.band ?? "") != band)
			continue;
		if (!device_on_phy(s, phy_name, path))
			continue;
		return name;
	}
	return null;
}

function uci_set(section, option, value) {
	print(`set wireless.${section}.${option}='${value}'\n`);
	config[section][option] = "" + value;
	commit = true;
}

function radio_htmode(band_name, band) {
	let width = band.max_width;
	if (band_name == "2G" || band_name == "2g")
		width = 20;
	else if (width > 80)
		width = 80;

	let htmode = filter(htmode_order, (m) => band[lc(m)])[0];
	if (htmode)
		return htmode + width;
	return "NOHT";
}

function sync_radio_section(name, radio_idx, hwmac, band_name, channel, htmode) {
	let s = config[name];
	if (radio_idx != null && int(s.radio) != radio_idx)
		uci_set(name, "radio", radio_idx);
	if (hwmac && normalize_mac(s.hwmac) != hwmac)
		uci_set(name, "hwmac", hwmac);
	/*
	 * Incomplete sections (missing band) make hostapd fall back to hw_mode=g
	 * with channel 0 — AP-DISABLED on 5/6 GHz radios. Repair from board.json.
	 */
	if (band_name && !s.band)
		uci_set(name, "band", band_name);
	if (channel != null && channel != "" &&
	    (s.channel == null || s.channel == "" || s.channel == "0"))
		uci_set(name, "channel", "" + channel);
	if (htmode && !s.htmode)
		uci_set(name, "htmode", htmode);
}

function default_ssid(band_name) {
	let country, encryption, defaults, num_global_macaddr;

	if (band_name == '6g') {
		country = '00';
		encryption = 'owe';
	} else {
		encryption = 'none';
	}

	if (board.wlan.defaults) {
		defaults = board.wlan.defaults.ssids?.[band_name]?.ssid
			? board.wlan.defaults.ssids?.[band_name]
			: board.wlan.defaults.ssids?.all;
		country = board.wlan.defaults.country;
		if (!country && band_name != '2g')
			defaults = null;
		num_global_macaddr = board.wlan.defaults.ssids?.[band_name]?.mac_count;
	}

	return { country, encryption, defaults, num_global_macaddr };
}

function alloc_radio_name() {
	while (config[`radio${idx}`])
		idx++;
	let name = "radio" + idx;
	idx++;
	return name;
}

function create_radio(phy_name, path, radio, band_name, band, rband, hwmac) {
	let name = alloc_radio_name();
	let s = "wireless." + name;
	let si = "wireless.default_" + name;
	let channel = rband.default_channel ?? "auto";
	let htmode = radio_htmode(band_name, band);

	band_name = lc(band_name);
	let d = default_ssid(band_name);

	let id = `phy='${phy_name}'`;
	if (match(phy_name, /^phy[0-9]/))
		id = `path='${path}'`;

	if (radio.index != null)
		id += `\nset ${s}.radio='${radio.index}'`;
	if (hwmac)
		id += `\nset ${s}.hwmac='${hwmac}'`;

	print(`set ${s}=wifi-device
set ${s}.type='mac80211'
set ${s}.${id}
set ${s}.band='${band_name}'
set ${s}.channel='${channel}'
set ${s}.htmode='${htmode}'
set ${s}.country='${d.country || ''}'
set ${s}.num_global_macaddr='${d.num_global_macaddr || ''}'

set ${si}=wifi-iface
set ${si}.device='${name}'
set ${si}.network='lan'
set ${si}.mode='ap'
set ${si}.ssid='${d.defaults?.ssid || "OpenWrt"}'
set ${si}.encryption='${d.defaults?.encryption || d.encryption}'
set ${si}.key='${d.defaults?.key || ""}'
set ${si}.disabled='${d.defaults ? 0 : 1}'

`);
	config[name] = {
		".type": "wifi-device",
		radio: radio.index != null ? "" + radio.index : null,
		hwmac: hwmac,
		band: band_name,
		phy: phy_name,
		path: match(phy_name, /^phy[0-9]/) ? path : null,
	};
	commit = true;
}

for (let phy_name, phy in board.wlan) {
	let info = phy.info;
	if (!info || !length(info.bands))
		continue;

	let multi = length(info.radios) > 0;
	/* Copy before sort so board.json in-memory order is unchanged. */
	let radios = multi ? map(info.radios, (r) => r) : [{ bands: info.bands }];

	/* Section name order on first create only (habit); sync still keys on hwmac. */
	if (multi && length(radios) > 1)
		sort(radios, (a, b) => {
			let ba = filter(create_name_order, (x) => a.bands?.[x])[0];
			let bb = filter(create_name_order, (x) => b.bands?.[x])[0];
			let ia = ba != null ? index(create_name_order, ba) : 99;
			let ib = bb != null ? index(create_name_order, bb) : 99;
			return ia - ib;
		});

	for (let radio in radios) {
		let band_name = filter(bands_order, (b) => radio.bands[b])[0];
		if (!band_name)
			continue;

		let band = info.bands[band_name];
		let rband = radio.bands[band_name];
		if (!phy.path)
			continue;

		let hwmac = normalize_mac(radio.hwmac);

		if (multi && hwmac) {
			let name = find_device_by_hwmac(hwmac) ?? find_legacy_device(phy_name, phy.path, lc(band_name));
			if (name) {
				sync_radio_section(name, radio.index, hwmac, lc(band_name),
					rband.default_channel ?? "auto", radio_htmode(band_name, band));
				continue;
			}
			create_radio(phy_name, phy.path, radio, band_name, band, rband, hwmac);
			continue;
		}

		/* Single-radio, or multi-radio without addresses[] for this index. */
		let phy_mac = trim(readfile(`${ieee80211_root}/${phy_name}/macaddress`) ?? "");
		if (radio_exists_by_index(phy.path, phy_mac, phy_name, radio.index))
			continue;

		create_radio(phy_name, phy.path, radio, band_name, band, rband, null);
	}
}

if (commit)
	print("commit wireless\n");

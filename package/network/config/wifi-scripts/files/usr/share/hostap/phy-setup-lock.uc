'use strict';
/**
 * Serialize hostapd setup across radios that share one wiphy.
 *
 * Boundary (this module does NOT):
 *   - pick hardware radio via wifi-device frequency class (Preview 2 /
 *     upstream draft); this fork uses radio-mac.uc + wifi-device.hwmac
 *   - reorder or rename wifi-device sections
 *
 * netifd starts each wifi-device in parallel.  On ath12k WSI (one phy, several
 * hardware radios) concurrent hostapd config_set races firmware vdev start —
 * often as 6 GHz "failed to start vdev".  Hold a per-phy lock around
 * hostapd.setup and keep it briefly after return so the firmware can settle.
 *
 * Lock: mkdir(2) on /var/run/wifi-<phy>.setup-lock (atomic).  Stale dirs from
 * killed handlers are cleared after a bounded wait; /var/run is tmpfs.
 *
 * When to lock (single policy for shell + ucode):
 *   WIFI_PHY_SETUP_MULTI_RADIO=0  → never (total disable)
 *   WIFI_PHY_SETUP_MULTI_RADIO=1  → always (host tests)
 *   else → addresses[] has >1 MAC, or nl80211 radios[] length > 1
 *
 * Seams: WIFI_PHY_SETUP_LOCK_DIR, WIFI_PHY_SETUP_SETTLE (default 4),
 * WIFI_PHY_SETUP_LOCK_WAIT (default 30), IEEE80211_SYSFS (via radio-mac.uc).
 */
import { read_phy_addresses } from "/usr/share/hostap/radio-mac.uc";
import * as nl80211 from "nl80211";

const lock_root = getenv("WIFI_PHY_SETUP_LOCK_DIR") || "/var/run";

export function valid_phy_name(phy) {
	return phy != null && match("" + phy, /^[A-Za-z0-9_.-]+$/);
}

function env_int(name, def) {
	let v = getenv(name);
	if (v == null || !match("" + v, /^[0-9]+$/))
		return def;
	return +v;
}

export function phy_setup_settle_seconds() {
	return env_int("WIFI_PHY_SETUP_SETTLE", 4);
}

export function phy_setup_lock_wait_seconds() {
	return env_int("WIFI_PHY_SETUP_LOCK_WAIT", 30);
}

export function phy_setup_lock_path(phy) {
	if (!valid_phy_name(phy))
		return null;
	return `${lock_root}/wifi-${phy}.setup-lock`;
}

/** addresses[] has more than one permanent MAC (same filter as radio-mac.uc). */
export function phy_is_multi_radio(phy) {
	if (!valid_phy_name(phy))
		return false;
	return length(read_phy_addresses(phy)) > 1;
}

function phy_nl_multi_radio(phy_name) {
	if (!valid_phy_name(phy_name))
		return false;

	let phys = nl80211.request(
		nl80211.const.NL80211_CMD_GET_WIPHY,
		nl80211.const.NLM_F_DUMP,
		{ split_wiphy_dump: true }
	);

	for (let phy in phys ?? [])
		if (phy?.wiphy_name == phy_name)
			return length(phy.radios ?? []) > 1;

	return false;
}

/** Unified gate used by both backends. */
export function needs_phy_setup_lock(phy) {
	let force = getenv("WIFI_PHY_SETUP_MULTI_RADIO");
	if (force == "0")
		return false;
	if (force == "1")
		return true;

	return phy_is_multi_radio(phy) || phy_nl_multi_radio(phy);
}

/**
 * Acquire per-phy setup lock.  Does not check multi-radio — caller decides.
 * Returns lock path, or null if name invalid / acquisition failed.
 */
export function try_acquire_phy_setup_lock(phy) {
	let path = phy_setup_lock_path(phy);
	if (!path)
		return null;

	let wait = phy_setup_lock_wait_seconds();
	for (let attempt = 0; attempt < wait; attempt++) {
		if (!system(`mkdir '${path}' 2>/dev/null`))
			return path;
		system("sleep 1");
	}

	/* Stale lock from a killed setup handler. */
	system(`rmdir '${path}' 2>/dev/null`);
	if (!system(`mkdir '${path}' 2>/dev/null`))
		return path;

	return null;
}

/** Acquire when needs_phy_setup_lock(phy). */
export function acquire_hostapd_phy_lock(phy) {
	if (!needs_phy_setup_lock(phy))
		return null;
	return try_acquire_phy_setup_lock(phy);
}

/**
 * Release lock after optional settle delay (ath12k vdev startup lag).
 * settle: omit/null → WIFI_PHY_SETUP_SETTLE (default 4); 0 → no sleep.
 */
export function release_phy_setup_lock(path, settle) {
	if (!path || !match(path, /\.setup-lock$/))
		return;

	if (settle == null)
		settle = phy_setup_settle_seconds();
	else
		settle = +settle;

	if (settle > 0)
		system(`sleep ${settle}`);

	system(`rmdir '${path}' 2>/dev/null`);
}

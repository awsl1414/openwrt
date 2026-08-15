'use strict';
/**
 * Helpers for serializing hostapd config_set across radios on one wiphy.
 *
 * hostapd.uc queues applies per base phy and waits until the iface leaves
 * ACS/HT_SCAN/DFS before starting the next radio.
 *
 * Env:
 *   WIFI_HOSTAPD_PHY_SETUP=0  → disable queue
 */

const POLL_MS = 250;
const SETTLE_MS = 500;
const WARN_EVERY_MS = 120000;

function env_int(name, def) {
	let v = getenv(name);
	if (v == null || !match("" + v, /^[0-9]+$/))
		return def;
	return +v;
}

export function phy_setup_queue_enabled() {
	return getenv("WIFI_HOSTAPD_PHY_SETUP") != "0";
}

/** Coerce ubus/JSON radio to int. Missing / "" / NaN → -1. */
export function normalize_radio(radio) {
	if (radio == null || radio === "")
		return -1;
	let n = +radio;
	if (n != n)
		return -1;
	return n;
}

export function needs_phy_setup_queue(radio) {
	if (!phy_setup_queue_enabled())
		return false;
	return normalize_radio(radio) >= 0;
}

export function phy_setup_poll_ms() {
	return POLL_MS;
}

export function phy_setup_settle_ms() {
	return SETTLE_MS;
}

export function phy_setup_warn_every_ms() {
	return env_int("WIFI_HOSTAPD_PHY_SETUP_WARN_MS", WARN_EVERY_MS);
}

/**
 * Steady = no pending_config and not mid ACS/HT_SCAN/DFS/country update.
 * null / DISABLED / UNINITIALIZED / NO_IR / ENABLED are steady.
 */
export function is_phy_setup_steady(has_pending, state) {
	if (has_pending)
		return false;
	if (state == null || state == "")
		return true;
	return state == "ENABLED" || state == "DISABLED" ||
	       state == "UNINITIALIZED" || state == "NO_IR";
}

/** Only a live AP needs post-bring-up settle before the next radio. */
export function should_phy_setup_settle(state) {
	return state == "ENABLED";
}

function coalesce_queue(queue, job) {
	let out = [];
	for (let j in queue ?? [])
		if (j.name != job.name)
			push(out, j);
	push(out, job);
	return out;
}

function sort_by_radio(queue) {
	let arr = [ ...(queue ?? []) ];
	let n = length(arr);
	for (let i = 0; i < n; i++) {
		for (let j = i + 1; j < n; j++) {
			let ri = normalize_radio(arr[i].radio);
			let rj = normalize_radio(arr[j].radio);
			if (rj < ri) {
				let tmp = arr[i];
				arr[i] = arr[j];
				arr[j] = tmp;
			}
		}
	}
	return arr;
}

/** Coalesce same-name jobs then sort by radio (0 → 1 → 2). */
export function enqueue_phy_setup_sorted(queue, job) {
	return sort_by_radio(coalesce_queue(queue, job));
}

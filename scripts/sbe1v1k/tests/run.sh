#!/usr/bin/env bash
# Run SBE1V1K bring-up host tests (and optional on-device smoke).
#
#   bash scripts/sbe1v1k/tests/run.sh
#   bash scripts/sbe1v1k/tests/run.sh /path/to/*-sysupgrade.bin
#   SBE_HOST=192.168.255.1 bash scripts/sbe1v1k/tests/run.sh --device
#
set -Eeuo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DEVICE=0
IMAGE=""

usage() {
	cat <<EOF
Usage: bash $0 [--device] [sysupgrade.bin]

  (default)   tree invariants + radio-mac + phy-setup-lock + upgrade-validation
  --device    also run on-device smoke (SBE_HOST / root@192.168.255.1)
  IMAGE       optional real sysupgrade.bin passed to upgrade-validation
EOF
}

while (($#)); do
	case "$1" in
	-h|--help) usage; exit 0 ;;
	--device) RUN_DEVICE=1; shift ;;
	--) shift; break ;;
	-*)
		printf 'unknown option: %s\n' "$1" >&2
		exit 1
		;;
	*)
		IMAGE=$1
		shift
		;;
	esac
done

failed=0

run_one() {
	local name=$1
	shift
	printf '\n==> %s\n' "$name"
	if "$@"; then
		printf 'OK %s\n' "$name"
	else
		printf 'FAILED %s\n' "$name" >&2
		failed=1
	fi
}

run_one tree-invariants sh "$TESTS_DIR/test-tree-invariants.sh"
run_one radio-mac sh "$TESTS_DIR/test-radio-mac.sh"
run_one phy-setup-lock sh "$TESTS_DIR/test-phy-setup-lock.sh"

if [[ -n "$IMAGE" ]]; then
	run_one upgrade-validation sh "$TESTS_DIR/test-upgrade-validation.sh" "$IMAGE"
else
	run_one upgrade-validation sh "$TESTS_DIR/test-upgrade-validation.sh"
fi

if ((RUN_DEVICE)); then
	run_one device-smoke sh "$TESTS_DIR/test-device-smoke.sh"
fi

if ((failed)); then
	printf '\nSBE1V1K tests: FAILED\n' >&2
	exit 1
fi
printf '\nSBE1V1K tests: PASSED\n'

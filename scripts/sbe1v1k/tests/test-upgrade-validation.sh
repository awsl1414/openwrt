#!/bin/sh
# Validate askey,sbe1v1k platform_check_image() tar preflight.
# Adapted from Preview 2 sbe1v1k-tests/test-upgrade-validation.sh.
set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$tests_dir/../../.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT INT TERM

board_name() {
	echo 'askey,sbe1v1k'
}

# shellcheck source=/dev/null
. "$repo_root/target/linux/qualcommbe/ipq95xx/base-files/lib/upgrade/platform.sh"

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

# Optional: check a real sysupgrade.bin from the build.
if [ "$#" -gt 0 ]; then
	if platform_check_image "$1"; then
		ok "built image: $1"
	else
		bad "built image rejected: $1"
	fi
fi

mkdir -p "$work_dir/sysupgrade-askey_sbe1v1k"
printf 'BOARD=askey_sbe1v1k\n' >"$work_dir/sysupgrade-askey_sbe1v1k/CONTROL"
dd if=/dev/zero of="$work_dir/sysupgrade-askey_sbe1v1k/kernel" bs=1024 count=16 status=none 2>/dev/null \
	|| dd if=/dev/zero of="$work_dir/sysupgrade-askey_sbe1v1k/kernel" bs=1024 count=16 2>/dev/null
dd if=/dev/zero of="$work_dir/sysupgrade-askey_sbe1v1k/root" bs=1024 count=64 status=none 2>/dev/null \
	|| dd if=/dev/zero of="$work_dir/sysupgrade-askey_sbe1v1k/root" bs=1024 count=64 2>/dev/null
tar -C "$work_dir" -cf "$work_dir/valid.bin" sysupgrade-askey_sbe1v1k

if platform_check_image "$work_dir/valid.bin"; then
	ok "complete archive accepted"
else
	bad "complete archive rejected"
fi

head -c 32768 "$work_dir/valid.bin" >"$work_dir/truncated.bin"
if platform_check_image "$work_dir/truncated.bin"; then
	bad "truncated archive accepted"
else
	ok "truncated archive rejected"
fi

rm -f "$work_dir/sysupgrade-askey_sbe1v1k/root"
tar -C "$work_dir" -cf "$work_dir/missing-root.bin" sysupgrade-askey_sbe1v1k
if platform_check_image "$work_dir/missing-root.bin"; then
	bad "archive missing root accepted"
else
	ok "archive missing root rejected"
fi

printf 'upgrade-validation: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

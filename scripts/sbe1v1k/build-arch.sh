#!/usr/bin/env bash
# Build Askey SBE1V1K OpenWrt on Arch Linux (bring-up / private fork).
#
# Lives in the OpenWrt tree (push/pull with the fork):
#   openwrt/scripts/sbe1v1k/build-arch.sh
#   openwrt/scripts/sbe1v1k/minimal.config
#
# Usage (on Arch, from the openwrt clone):
#   bash scripts/sbe1v1k/build-arch.sh
#   bash scripts/sbe1v1k/build-arch.sh --pull -j 28
#   bash scripts/sbe1v1k/build-arch.sh --skip-deps --keep-config
#
# Do not run as root (OpenWrt refuses root builds).

set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
# scripts/sbe1v1k → openwrt root
OPENWRT_DIR="${OPENWRT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SEED_CONFIG="${SEED_CONFIG:-$SCRIPT_DIR/minimal.config}"
BRANCH="${BRANCH:-dev-sbe1v1k}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
INSTALL_DEPS=1
DO_PULL=0
CLEAN_BUILD=0
DOWNLOAD_ONLY=0
RETRY_SERIAL=0
FEEDS=1
KEEP_CONFIG=0

log() {
	if [[ -t 1 ]]; then
		printf '\n\033[1;32m==> %s\033[0m\n' "$*"
	else
		printf '\n==> %s\n' "$*"
	fi
}

die() {
	if [[ -t 2 ]]; then
		printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
	else
		printf '\nERROR: %s\n' "$*" >&2
	fi
	exit 1
}

usage() {
	cat <<EOF
Usage: bash $0 [options]

Arch Linux build helper for qualcommbe/ipq95xx DEVICE askey_sbe1v1k.

Options:
  -j, --jobs N       Parallel jobs (default: nproc)
      --pull         git fetch/checkout/pull --ff-only on BRANCH before build
      --branch NAME  Branch for --pull (default: $BRANCH)
      --skip-deps    Skip pacman dependency install
      --skip-feeds   Skip feeds update/install
      --keep-config  Reuse existing .config (do not apply seed)
      --clean        make dirclean before configure
      --download-only
                     Stop after make download
      --retry        On parallel world failure, retry once with -j1 V=s
  -h, --help         Show help

Environment:
  OPENWRT_DIR=PATH   OpenWrt tree (default: repository root containing this script)
  SEED_CONFIG=PATH   Config seed (default: scripts/sbe1v1k/minimal.config)
  JOBS=N             Same as --jobs
  BRANCH=NAME        Same as --branch
EOF
}

while (($#)); do
	case "$1" in
	-j|--jobs)
		(($# >= 2)) || die "$1 needs a value"
		JOBS="$2"
		shift 2
		;;
	--pull) DO_PULL=1; shift ;;
	--branch)
		(($# >= 2)) || die "$1 needs a value"
		BRANCH="$2"
		shift 2
		;;
	--skip-deps) INSTALL_DEPS=0; shift ;;
	--skip-feeds) FEEDS=0; shift ;;
	--keep-config) KEEP_CONFIG=1; shift ;;
	--clean) CLEAN_BUILD=1; shift ;;
	--download-only) DOWNLOAD_ONLY=1; shift ;;
	--retry) RETRY_SERIAL=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) die "unknown option: $1" ;;
	esac
done

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"
[[ "$(uname -s)" == Linux ]] || die "run on Linux (Arch build host)"
((EUID != 0)) || die "do not run as root; use a normal user with sudo for deps"
command -v pacman >/dev/null || die "pacman required (Arch Linux)"

[[ -f "$OPENWRT_DIR/Makefile" && -x "$OPENWRT_DIR/scripts/feeds" ]] || \
	die "OPENWRT_DIR is not an OpenWrt tree: $OPENWRT_DIR"
[[ -f "$SEED_CONFIG" ]] || die "seed config missing: $SEED_CONFIG"
[[ "$OPENWRT_DIR" != *[[:space:]]* ]] || die "OpenWrt path must not contain spaces"

install_deps() {
	log "Installing Arch build dependencies (sudo pacman)"
	local -a packages=(
		base-devel
		autoconf automake bison flex gawk gettext git gperf
		libtool ncurses openssl
		patch pkgconf python python-setuptools
		rsync time unzip wget which
		swig quilt
		libxslt zstd xz elfutils
		bc perl
	)
	if pacman -Q zlib-ng-compat >/dev/null 2>&1; then
		log "zlib-ng-compat present; skipping zlib package"
	else
		packages+=(zlib)
	fi
	sudo pacman -Syu --needed --noconfirm "${packages[@]}" \
		|| die "pacman dependency install failed"
}

apply_seed_config() {
	if ((KEEP_CONFIG)); then
		[[ -f .config ]] || die "--keep-config requires an existing .config"
		log "Keeping existing .config (--keep-config)"
		make olddefconfig 2>/dev/null || make defconfig
	else
		log "Applying seed config → defconfig (askey_sbe1v1k)"
		if [[ -f .config ]]; then
			local bak=".config.bak.$(date +%Y%m%d-%H%M%S)"
			cp -a .config "$bak"
			log "Backed up previous .config → $bak"
		fi
		cp "$SEED_CONFIG" .config
		make defconfig
	fi
	grep -q '^CONFIG_TARGET_qualcommbe_ipq95xx_DEVICE_askey_sbe1v1k=y' .config || \
		die "DEVICE askey_sbe1v1k not enabled in .config; check seed / --keep-config"
}

git_pull_ff() {
	log "git pull --ff-only ($BRANCH)"
	export GIT_PAGER=cat PAGER=cat
	if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
		die "working tree is dirty; commit/stash or clean before --pull"
	fi
	git fetch origin
	git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1 \
		|| die "remote branch origin/$BRANCH not found (push from the porting machine first)"
	git checkout "$BRANCH"
	git pull --ff-only origin "$BRANCH" \
		|| die "git pull --ff-only failed (diverged history?)"
	printf 'Now at: '; git rev-parse --short HEAD
}

cd "$OPENWRT_DIR"

log "OpenWrt: $OPENWRT_DIR"
printf 'Jobs: %s\nBranch: %s\nSeed: %s\n' "$JOBS" "$BRANCH" "$SEED_CONFIG"
printf 'Git: '; git rev-parse --short HEAD 2>/dev/null || true
printf 'Disk: '; df -h . | awk 'NR==2 {print $4 " free on " $6}'

((INSTALL_DEPS)) && install_deps
((DO_PULL)) && git_pull_ff

available_kib="$(df -Pk . | awk 'NR==2 {print $4}')"
if [[ "$available_kib" =~ ^[0-9]+$ ]] && ((available_kib < 20 * 1024 * 1024)); then
	die "need ~20+ GiB free (have $((available_kib / 1024 / 1024)) GiB)"
fi

if ((CLEAN_BUILD)); then
	log "make dirclean"
	make dirclean
	if ((KEEP_CONFIG)); then
		die "--clean removes .config; do not combine with --keep-config"
	fi
fi

if ((FEEDS)); then
	log "feeds update / install"
	./scripts/feeds update -a
	./scripts/feeds install -a
fi

apply_seed_config

if ((DOWNLOAD_ONLY)); then
	log "make download (-j$JOBS)"
	make -j"$JOBS" download
	log "download-only done"
	exit 0
fi

log "make download (-j$JOBS)"
make -j"$JOBS" download

log "make world (-j$JOBS)"
set +e
make -j"$JOBS" world
rc=$?
if ((rc != 0)) && ((RETRY_SERIAL)); then
	log "parallel build failed (exit $rc); retry make -j1 V=s (--retry)"
	make -j1 V=s world
	rc=$?
fi
set -e
((rc == 0)) || die "build failed (exit $rc)"

OUT="$(make -s val.BIN_DIR 2>/dev/null || true)"
[[ -n "$OUT" ]] || OUT="bin/targets/qualcommbe/ipq95xx"
log "Build OK. Artifacts under: $OPENWRT_DIR/$OUT"
ls -lh "$OUT"/*askey_sbe1v1k* 2>/dev/null || ls -lh "$OUT" | head -40

cat <<EOF

Next (device):
  initramfs:  …-askey_sbe1v1k-initramfs-uImage.itb   (TFTP / first boot)
  sysupgrade: …-askey_sbe1v1k-squashfs-sysupgrade.bin
  factory:    …-askey_sbe1v1k-squashfs-factory.bin   (if produced)

EOF

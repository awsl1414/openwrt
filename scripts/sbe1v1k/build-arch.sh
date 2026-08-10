#!/usr/bin/env bash
# Build Askey SBE1V1K OpenWrt on Arch Linux (bring-up / private fork).
#
# Scope: minimal device image (feeds + seed defconfig + make world).
# Not a Dedrimer-style product build (no iStore/Argon/large seed).
#
# Workflow: edit/commit on the porting machine → push → on Arch:
#   cd openwrt && bash scripts/sbe1v1k/build-arch.sh --pull -j"$(nproc)"
#
# Also:
#   bash scripts/sbe1v1k/build-arch.sh --skip-deps --keep-config -j28
#   bash scripts/sbe1v1k/build-arch.sh --download-only
#
# Do not run as root (OpenWrt refuses root builds). Use sudo only for pacman.

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# This file lives at scripts/sbe1v1k/; repo root is two levels up.
OPENWRT_DIR="${OPENWRT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SEED_CONFIG="${SEED_CONFIG:-$SCRIPT_DIR/minimal.config}"
BRANCH="${BRANCH:-dev-sbe1v1k}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
INSTALL_DEPS=1
DO_PULL=0
CLEAN_BUILD=0
DOWNLOAD_ONLY=0
RETRY_SERIAL=0 # off by default: -j1 V=s retry is slow; pass --retry to enable
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
  -j, --jobs N       Parallel jobs (default: nproc); also -jN / --jobs=N
      --pull         git fetch/checkout/merge --ff-only on BRANCH before build
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

# Accept both "-j 28" and make-style "-j28" (from -j"$(nproc)").
while (($#)); do
	case "$1" in
	-j|--jobs)
		(($# >= 2)) || die "$1 needs a value"
		JOBS="$2"
		shift 2
		;;
	-j[0-9]*)
		JOBS="${1#-j}"
		shift
		;;
	--jobs=*)
		JOBS="${1#--jobs=}"
		shift
		;;
	--pull) DO_PULL=1; shift ;;
	--branch)
		(($# >= 2)) || die "$1 needs a value"
		BRANCH="$2"
		shift 2
		;;
	--branch=*)
		BRANCH="${1#--branch=}"
		shift
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
# OpenWrt buildsystem breaks on paths with spaces.
[[ "$OPENWRT_DIR" != *[[:space:]]* ]] || die "OpenWrt path must not contain spaces"

install_deps() {
	log "Installing Arch build dependencies (sudo pacman)"
	command -v sudo >/dev/null || die "sudo is required for dependency install (or use --skip-deps)"
	# base-devel already provides autoconf/automake/bison/flex/gcc/make/patch/pkgconf/...
	# List only extras commonly needed beyond that group.
	local -a packages=(
		base-devel
		git gperf ncurses openssl
		python python-setuptools
		rsync time unzip wget
		swig quilt
		libxslt zstd elfutils
		bc perl
	)
	# CachyOS (and some Arch setups) ship zlib via zlib-ng-compat; avoid conflict.
	if pacman -Q zlib-ng-compat >/dev/null 2>&1; then
		log "zlib-ng-compat present; skipping zlib package"
	else
		packages+=(zlib)
	fi
	# -Sy refreshes package DB; do not use -Syu (full system upgrade) here.
	sudo pacman -Sy --needed --noconfirm "${packages[@]}" \
		|| die "pacman dependency install failed"
}

apply_seed_config() {
	if ((KEEP_CONFIG)); then
		# Iterative builds: keep menuconfig tweaks; only refresh defaults.
		[[ -f .config ]] || die "--keep-config requires an existing .config"
		log "Keeping existing .config (--keep-config)"
		make olddefconfig || die "make olddefconfig failed; fix .config or drop --keep-config"
	else
		# Cold / reproducible bring-up: force device profile from minimal.config.
		log "Applying seed config → defconfig (askey_sbe1v1k)"
		if [[ -f .config ]]; then
			local bak=".config.bak.$(date +%Y%m%d-%H%M%S)"
			cp -a .config "$bak"
			log "Backed up previous .config → $bak"
		fi
		cp "$SEED_CONFIG" .config
		make defconfig
	fi
	# defconfig must leave the SBE profile selected or images will be wrong/missing.
	grep -q '^CONFIG_TARGET_qualcommbe_ipq95xx_DEVICE_askey_sbe1v1k=y' .config || \
		die "DEVICE askey_sbe1v1k not enabled in .config; check seed / --keep-config"
}

git_pull_ff() {
	# Fast-forward only: never create merge commits on the build host.
	log "git fetch/merge --ff-only ($BRANCH)"
	export GIT_PAGER=cat PAGER=cat
	if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
		die "working tree is dirty; commit/stash or clean before --pull"
	fi
	git fetch origin
	git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1 \
		|| die "remote branch origin/$BRANCH not found (push from the porting machine first)"
	git checkout "$BRANCH"
	# fetch already ran; merge avoids a second network round-trip from git pull.
	git merge --ff-only "origin/$BRANCH" \
		|| die "git merge --ff-only failed (diverged history?)"
	printf 'Now at: '; git rev-parse --short HEAD
}

cd "$OPENWRT_DIR"

log "OpenWrt: $OPENWRT_DIR"
printf 'Jobs: %s\nBranch: %s\nSeed: %s\n' "$JOBS" "$BRANCH" "$SEED_CONFIG"
printf 'Git: '; git rev-parse --short HEAD 2>/dev/null || true
printf 'Disk: '; df -h . | awk 'NR==2 {print $4 " free on " $6}'

((INSTALL_DEPS)) && install_deps
((DO_PULL)) && git_pull_ff

# Cold toolchain + kernel builds need tens of GiB; fail early if the disk is tight.
available_kib="$(df -Pk . | awk 'NR==2 {print $4}')"
if [[ "$available_kib" =~ ^[0-9]+$ ]] && ((available_kib < 20 * 1024 * 1024)); then
	die "need ~20+ GiB free (have $((available_kib / 1024 / 1024)) GiB)"
fi

# dirclean deletes .config; refuse the contradictory flag combo before wiping.
if ((CLEAN_BUILD)) && ((KEEP_CONFIG)); then
	die "--clean removes .config; do not combine with --keep-config"
fi
if ((CLEAN_BUILD)); then
	log "make dirclean"
	make dirclean
fi

if ((FEEDS)); then
	log "feeds update / install"
	./scripts/feeds update -a
	./scripts/feeds install -a
fi

apply_seed_config

# Single download pass (shared by --download-only and full world builds).
log "make download (-j$JOBS)"
make -j"$JOBS" download
if ((DOWNLOAD_ONLY)); then
	log "download-only done"
	exit 0
fi

log "make world (-j$JOBS)"
# Keep set +e around world/retry so a failed make still yields rc for messaging.
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

# make world can succeed while the wrong profile was built; require SBE images.
shopt -s nullglob
arts=("$OUT"/*askey_sbe1v1k*)
shopt -u nullglob
((${#arts[@]} > 0)) || die "build finished but no *askey_sbe1v1k* artifacts in $OUT"
ls -lh "${arts[@]}"

# Typical names for TFTP / sysupgrade:
#   *-askey_sbe1v1k-initramfs-uImage.itb
#   *-askey_sbe1v1k-squashfs-sysupgrade.bin
#   *-askey_sbe1v1k-squashfs-factory.bin

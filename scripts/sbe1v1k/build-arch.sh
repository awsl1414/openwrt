#!/usr/bin/env bash
# Build Askey SBE1V1K OpenWrt on Arch Linux (private fork).
#
# Default seed: scripts/sbe1v1k/daily.config (LuCI SSL + zh-cn + daily tools).
# Slim bring-up: --minimal → scripts/sbe1v1k/minimal.config.
# Community themes (aurora/argon/alpha): OFF by default; pass --themes to fetch+enable.
# Not a Dedrimer-style product build (no iStore/Docker seed).
#
# Workflow: edit/commit on the porting machine → push → on Arch:
#   cd openwrt && bash scripts/sbe1v1k/build-arch.sh --pull -j"$(nproc)"
#
# Also:
#   bash scripts/sbe1v1k/build-arch.sh --themes --pull -j"$(nproc)"
#   bash scripts/sbe1v1k/build-arch.sh --minimal -j"$(nproc)"
#   bash scripts/sbe1v1k/build-arch.sh --seed /path/to.config …
#   bash scripts/sbe1v1k/build-arch.sh --skip-deps --keep-config -j28
#   bash scripts/sbe1v1k/build-arch.sh --download-only
#   bash scripts/sbe1v1k/build-arch.sh --proxy                 # 127.0.0.1:7897
#   bash scripts/sbe1v1k/build-arch.sh --proxy-host 10.0.0.1 --proxy-port 7890
#   bash scripts/sbe1v1k/build-arch.sh --skip-tests
#
# Host tests (no full build):
#   bash scripts/sbe1v1k/tests/run.sh
#   SBE_HOST=192.168.255.1 bash scripts/sbe1v1k/tests/run.sh --device
#
# Do not run as root (OpenWrt refuses root builds). Use sudo only for pacman.

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# This file lives at scripts/sbe1v1k/; repo root is two levels up.
OPENWRT_DIR="${OPENWRT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SEED_CONFIG="${SEED_CONFIG:-$SCRIPT_DIR/daily.config}"
BRANCH="${BRANCH:-dev-sbe1v1k}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
INSTALL_DEPS=1
DO_PULL=0
CLEAN_BUILD=0
DOWNLOAD_ONLY=0
RETRY_SERIAL=0 # off by default: -j1 V=s retry is slow; pass --retry to enable
FEEDS=1
THEMES=0 # opt-in: pass --themes to fetch+enable community LuCI themes
RUN_TESTS=1
KEEP_CONFIG=0

# Proxy off by default. Enable with --proxy / --proxy-host / --proxy-port / --proxy=URL.
USE_PROXY=0
PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
PROXY_PORT="${PROXY_PORT:-7897}"
# If set (env or --proxy URL), used as-is; otherwise http://$PROXY_HOST:$PROXY_PORT.
PROXY_URL="${PROXY_URL:-}"

# Community LuCI themes (single-package repos → package/<name>, not feeds.conf).
# Format: name|git-url|pinned-commit
# Enabled only with --themes (default build uses bootstrap from luci-ssl).
# Alpha hard-depends on luci-app-alpha-config.
# Argon Chinese UI for its settings app: jerrykuku/luci-app-argon-config (has po/zh_Hans;
# upstream v2.4.6 ships luci-i18n-argon-config-zh-cn). Theme shells themselves have no po/.
COMMUNITY_THEME_REPOS=(
	'luci-theme-aurora|https://github.com/eamonxg/luci-theme-aurora.git|e10bd0969c4978ad41495f7e53ac6fd162dda113'
	'luci-theme-argon|https://github.com/jerrykuku/luci-theme-argon.git|86c3156bab0ee2b8c91af68b3fa4655f2df51d09'
	'luci-app-argon-config|https://github.com/jerrykuku/luci-app-argon-config.git|3e099a37c3f71d0de677f1b6b0f4bffd57d91dac'
	'luci-theme-alpha|https://github.com/derisamedia/luci-theme-alpha.git|16e0c038c09421236319a4cc369a1f3fc98e1ef4'
	'luci-app-alpha-config|https://github.com/derisamedia/luci-app-alpha-config.git|83fe832a325f9d5c3b434922320e7c1d859f614b'
)

# Filled by init_community_theme_packages from REPOS names (single source of truth).
COMMUNITY_THEME_PACKAGES=()

# Extra CONFIG_PACKAGE_* required when --themes is set (argon/apk).
COMMUNITY_THEME_DEPS=(
	luci-base
	jsonfilter
	wget-ssl
)

# Filled at fetch: luci-i18n-*-zh-cn only when that package tree has po/zh_Hans (official).
# Never invent i18n for aurora/argon/alpha theme shells (no po/ in upstream pins).
COMMUNITY_THEME_I18N=()

# How many .config.bak.* files to keep after seed apply.
CONFIG_BAK_KEEP="${CONFIG_BAK_KEEP:-3}"

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

proxy_endpoint() {
	if [[ -n "$PROXY_URL" ]]; then
		printf '%s' "$PROXY_URL"
	else
		printf 'http://%s:%s' "$PROXY_HOST" "$PROXY_PORT"
	fi
}

usage() {
	cat <<EOF
Usage: bash $0 [options]

Arch Linux build helper for qualcommbe/ipq95xx DEVICE askey_sbe1v1k.

Options:
  -j, --jobs N       Parallel jobs (default: nproc); also -jN / --jobs=N
      --pull         git fetch/checkout/merge --ff-only on BRANCH before build
      --branch NAME  Branch for --pull (default: $BRANCH)
      --seed PATH    Config seed (default: scripts/sbe1v1k/daily.config)
      --minimal      Use scripts/sbe1v1k/minimal.config (slim bring-up)
      --themes       Fetch+enable community themes; zh-cn i18n only if upstream has po/
      --skip-deps    Skip pacman dependency install
      --skip-feeds   Skip feeds update/install
      --skip-tests   Skip post-build scripts/sbe1v1k/tests/run.sh
      --proxy [URL]  Enable proxy (default http://$PROXY_HOST:$PROXY_PORT)
      --proxy-host H Proxy host (implies --proxy; default $PROXY_HOST)
      --proxy-port N Proxy port (implies --proxy; default $PROXY_PORT)
      --no-proxy     Disable proxy (default)
      --keep-config  Reuse existing .config (do not apply seed)
      --clean        make dirclean before configure
      --download-only
                     Stop after make download
      --retry        On parallel world failure, retry once with -j1 V=s
  -h, --help         Show help

Environment:
  OPENWRT_DIR=PATH   OpenWrt tree (default: repository root containing this script)
  SEED_CONFIG=PATH   Config seed (default: scripts/sbe1v1k/daily.config)
  JOBS=N             Same as --jobs
  BRANCH=NAME        Same as --branch
  PROXY_HOST=ADDR    Default proxy host (default: 127.0.0.1)
  PROXY_PORT=N       Default proxy port (default: 7897)
  PROXY_URL=URL      Full proxy URL (overrides host/port when set)
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
	--seed)
		(($# >= 2)) || die "$1 needs a value"
		SEED_CONFIG="$2"
		shift 2
		;;
	--seed=*)
		SEED_CONFIG="${1#--seed=}"
		shift
		;;
	--minimal)
		SEED_CONFIG="$SCRIPT_DIR/minimal.config"
		shift
		;;
	--skip-deps) INSTALL_DEPS=0; shift ;;
	--skip-feeds) FEEDS=0; shift ;;
	--themes) THEMES=1; shift ;;
	--skip-tests) RUN_TESTS=0; shift ;;
	--proxy)
		USE_PROXY=1
		# Optional URL argument: --proxy http://host:port
		if (($# >= 2)) && [[ "$2" != -* ]]; then
			PROXY_URL="$2"
			shift 2
		else
			shift
		fi
		;;
	--proxy=*)
		USE_PROXY=1
		PROXY_URL="${1#--proxy=}"
		shift
		;;
	--proxy-host)
		(($# >= 2)) || die "$1 needs a value"
		PROXY_HOST="$2"
		PROXY_URL="" # host/port take precedence over a stale URL
		USE_PROXY=1
		shift 2
		;;
	--proxy-host=*)
		PROXY_HOST="${1#--proxy-host=}"
		PROXY_URL=""
		USE_PROXY=1
		shift
		;;
	--proxy-port)
		(($# >= 2)) || die "$1 needs a value"
		PROXY_PORT="$2"
		PROXY_URL=""
		USE_PROXY=1
		shift 2
		;;
	--proxy-port=*)
		PROXY_PORT="${1#--proxy-port=}"
		PROXY_URL=""
		USE_PROXY=1
		shift
		;;
	--no-proxy) USE_PROXY=0; shift ;;
	--keep-config) KEEP_CONFIG=1; shift ;;
	--clean) CLEAN_BUILD=1; shift ;;
	--download-only) DOWNLOAD_ONLY=1; shift ;;
	--retry) RETRY_SERIAL=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) die "unknown option: $1" ;;
	esac
done

[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"
[[ "$PROXY_PORT" =~ ^[1-9][0-9]*$ ]] || die "PROXY_PORT must be a positive integer"
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

# Run a command with HTTP(S) proxy env for GitHub / slow mirrors.
# Restores prior proxy-related env afterward so pacman/make stay unaffected.
with_proxy() {
	if ((!USE_PROXY)); then
		"$@"
		return
	fi
	local endpoint
	endpoint="$(proxy_endpoint)"
	local -a saved_vars=(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy)
	local -A saved=()
	local v rc
	for v in "${saved_vars[@]}"; do
		if [[ -n "${!v+x}" ]]; then
			saved["$v"]="${!v}"
		fi
	done
	export http_proxy="$endpoint" https_proxy="$endpoint"
	export HTTP_PROXY="$endpoint" HTTPS_PROXY="$endpoint"
	export ALL_PROXY="$endpoint" all_proxy="$endpoint"
	# Keep set +e so we can restore env even when the command fails.
	set +e
	GIT_CONFIG_COUNT=1 \
		GIT_CONFIG_KEY_0=http.proxy \
		GIT_CONFIG_VALUE_0="$endpoint" \
		"$@"
	rc=$?
	set -e
	for v in "${saved_vars[@]}"; do
		if [[ -n "${saved[$v]+x}" ]]; then
			export "$v=${saved[$v]}"
		else
			unset -v "$v" || true
		fi
	done
	return "$rc"
}

# Clone/pin single-package theme repos into package/<name> so luci.mk PKG_NAME matches.
# Do not put these in feeds.conf.default (root Makefile would become PKG_NAME=<feed>).
# Populates COMMUNITY_THEME_I18N only when upstream ships po/zh_Hans (or po/zh-cn).
theme_i18n_package() {
	case "$1" in
	luci-theme-*) printf 'luci-i18n-%s-zh-cn' "${1#luci-theme-}" ;;
	luci-app-*) printf 'luci-i18n-%s-zh-cn' "${1#luci-app-}" ;;
	*) die "theme_i18n_package: unsupported package name: $1" ;;
	esac
}

# Derive package names from COMMUNITY_THEME_REPOS (avoid a second hand-maintained list).
init_community_theme_packages() {
	local entry name
	COMMUNITY_THEME_PACKAGES=()
	for entry in "${COMMUNITY_THEME_REPOS[@]}"; do
		IFS='|' read -r name _url _sha <<<"$entry"
		[[ -n "$name" && -n "$_url" && -n "$_sha" ]] || die "bad COMMUNITY_THEME_REPOS entry: $entry"
		COMMUNITY_THEME_PACKAGES+=("$name")
	done
	((${#COMMUNITY_THEME_PACKAGES[@]} > 0)) || die "COMMUNITY_THEME_REPOS is empty"
}

# Without --themes, drop leftover clones so they are not scanned into the build.
prune_community_theme_trees() {
	local pkg dest
	((${#COMMUNITY_THEME_PACKAGES[@]})) || init_community_theme_packages
	for pkg in "${COMMUNITY_THEME_PACKAGES[@]}"; do
		dest="package/$pkg"
		[[ -e "$dest" ]] || continue
		if [[ -d "$dest/.git" ]]; then
			log "Removing leftover community theme tree (no --themes): $dest"
			rm -rf -- "$dest"
		else
			die "leftover $dest is not a git clone from this script; remove it or pass --themes"
		fi
	done
}

fetch_community_themes() {
	local entry name url sha dest head i18n
	COMMUNITY_THEME_I18N=()
	if ((USE_PROXY)); then
		log "Fetching pinned community LuCI themes (proxy $(proxy_endpoint))"
	else
		log "Fetching pinned community LuCI themes"
	fi
	mkdir -p package
	for entry in "${COMMUNITY_THEME_REPOS[@]}"; do
		IFS='|' read -r name url sha <<<"$entry"
		[[ -n "$name" && -n "$url" && -n "$sha" ]] || die "bad COMMUNITY_THEME_REPOS entry: $entry"
		dest="package/$name"
		if [[ -d "$dest/.git" ]]; then
			log "Updating $name → $sha"
			git -C "$dest" remote set-url origin "$url"
		else
			[[ ! -e "$dest" ]] || die "refusing to overwrite non-git path: $dest"
			log "Cloning $name → $sha"
			mkdir -p "$dest"
			git -C "$dest" init
			git -C "$dest" remote add origin "$url"
		fi
		with_proxy git -C "$dest" fetch --depth 1 origin "$sha" \
			|| die "failed to fetch $name @$sha from $url"
		git -C "$dest" checkout --detach --force FETCH_HEAD
		git -C "$dest" clean -fdx
		head="$(git -C "$dest" rev-parse HEAD)"
		[[ "$head" == "$sha" ]] || die "$name commit mismatch: got $head want $sha"
		[[ -f "$dest/Makefile" ]] || die "missing Makefile after fetch: $dest"
		# Official Chinese only if upstream ships po/. luci.mk language id is zh_Hans.
		if [[ -d "$dest/po/zh-cn" && ! -e "$dest/po/zh_Hans" ]]; then
			ln -s zh-cn "$dest/po/zh_Hans"
		fi
		if [[ -d "$dest/po/zh_Hans" ]]; then
			i18n="$(theme_i18n_package "$name")"
			COMMUNITY_THEME_I18N+=("$i18n")
			log "$name: official zh_Hans → enable $i18n"
		else
			log "$name: no upstream po/zh_Hans; not enabling theme/app zh-cn i18n"
		fi
	done
}

# Force a Kconfig symbol to =y (drop prior line first).
config_force_y() {
	local sym=$1
	sed -i -E "/^#? ?${sym}([= ].*)?\$/d" .config
	printf '%s=y\n' "$sym" >> .config
}

# Keep only the newest CONFIG_BAK_KEEP backups of .config.
prune_config_backups() {
	local -a baks=()
	local keep="$CONFIG_BAK_KEEP" old
	[[ "$keep" =~ ^[0-9]+$ ]] || keep=3
	mapfile -t baks < <(ls -1t .config.bak.* 2>/dev/null || true)
	((${#baks[@]} > keep)) || return 0
	old=("${baks[@]:keep}")
	log "Pruning ${#old[@]} old .config.bak.* (keep $keep)"
	rm -f -- "${old[@]}"
}

# Opt-in: themes + deps + only upstream-provided zh-cn i18n; hard-fail if missing.
apply_community_themes_config() {
	local pkg
	((${#COMMUNITY_THEME_PACKAGES[@]})) || init_community_theme_packages
	[[ -f .config ]] || die "apply_community_themes_config requires .config"
	[[ -f feeds/luci/luci.mk ]] || \
		die "feeds/luci/luci.mk missing; run feeds update/install before --themes"

	for pkg in "${COMMUNITY_THEME_PACKAGES[@]}"; do
		[[ -f "package/$pkg/Makefile" ]] || die "missing package/$pkg (fetch failed?)"
	done

	log "Enabling community themes + deps (--themes)"
	# Use if (not ((n)) && …): false ((n)) under set -e is fragile in bash.
	if ((${#COMMUNITY_THEME_I18N[@]})); then
		log "Upstream zh-cn i18n: ${COMMUNITY_THEME_I18N[*]}"
		# Needed so luci.mk emits/selects luci-i18n-*-zh-cn for packages that have po/.
		config_force_y CONFIG_LUCI_LANG_zh_Hans
	fi
	for pkg in "${COMMUNITY_THEME_PACKAGES[@]}" "${COMMUNITY_THEME_DEPS[@]}" "${COMMUNITY_THEME_I18N[@]}"; do
		config_force_y "CONFIG_PACKAGE_${pkg}"
	done
	# OpenWrt has no make olddefconfig target; defconfig re-reads .config and
	# fills unset symbols (same path as seed apply).
	make defconfig || die "make defconfig failed after --themes"

	for pkg in "${COMMUNITY_THEME_PACKAGES[@]}" "${COMMUNITY_THEME_DEPS[@]}" "${COMMUNITY_THEME_I18N[@]}"; do
		grep -q "^CONFIG_PACKAGE_${pkg}=y" .config || \
			die "--themes: CONFIG_PACKAGE_${pkg}=y missing after defconfig"
	done
	if ((${#COMMUNITY_THEME_I18N[@]})); then
		grep -q '^CONFIG_LUCI_LANG_zh_Hans=y' .config || \
			die "--themes: CONFIG_LUCI_LANG_zh_Hans=y missing after defconfig (required for i18n)"
	fi
}

# --keep-config without --themes must not leave community themes / their i18n enabled.
assert_no_community_themes_in_config() {
	local pkg i18n
	[[ -f .config ]] || return 0
	((${#COMMUNITY_THEME_PACKAGES[@]})) || init_community_theme_packages
	for pkg in "${COMMUNITY_THEME_PACKAGES[@]}"; do
		if grep -q "^CONFIG_PACKAGE_${pkg}=y" .config; then
			die "CONFIG_PACKAGE_${pkg}=y in .config; pass --themes or remove theme packages"
		fi
		i18n="$(theme_i18n_package "$pkg")"
		if grep -q "^CONFIG_PACKAGE_${i18n}=y" .config; then
			die "CONFIG_PACKAGE_${i18n}=y in .config; pass --themes or clear leftover i18n"
		fi
	done
}

apply_seed_config() {
	if ((KEEP_CONFIG)); then
		[[ -f .config ]] || die "--keep-config requires an existing .config"
		log "Keeping existing .config (--keep-config)"
		make defconfig || die "make defconfig failed; fix .config or drop --keep-config"
	else
		log "Applying seed → defconfig ($(basename "$SEED_CONFIG"))"
		if [[ -f .config ]]; then
			local bak=".config.bak.$(date +%Y%m%d-%H%M%S)"
			cp -a .config "$bak"
			log "Backed up previous .config → $bak"
			prune_config_backups
		fi
		cp "$SEED_CONFIG" .config
		make defconfig
	fi
	grep -q '^CONFIG_TARGET_qualcommbe_ipq95xx_DEVICE_askey_sbe1v1k=y' .config || \
		die "DEVICE askey_sbe1v1k not enabled in .config; check seed / --keep-config"
	if grep -q '^CONFIG_PACKAGE_luci-ssl=y' "$SEED_CONFIG" 2>/dev/null; then
		grep -q '^CONFIG_PACKAGE_luci-ssl=y' .config || \
			die "luci-ssl missing after defconfig; run feeds install (drop --skip-feeds)"
	fi

	# Use if/elif (not `((x)) && fn`): as the last command in a function,
	# a false ((x)) makes the function return 1 and aborts under set -e.
	if ((THEMES)); then
		apply_community_themes_config
	elif ((KEEP_CONFIG)); then
		assert_no_community_themes_in_config
	fi
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
init_community_theme_packages

log "OpenWrt: $OPENWRT_DIR"
printf 'Jobs: %s\nBranch: %s\nSeed: %s\n' "$JOBS" "$BRANCH" "$SEED_CONFIG"
if ((USE_PROXY)); then
	printf 'Proxy: %s\n' "$(proxy_endpoint)"
else
	printf 'Proxy: disabled (use --proxy / --proxy-host / --proxy-port)\n'
fi
if ((THEMES)); then
	printf 'Themes: enabled via --themes (%s)\n' "${COMMUNITY_THEME_PACKAGES[*]}"
else
	printf 'Themes: disabled (pass --themes for aurora/argon/alpha)\n'
fi
if ((RUN_TESTS)); then printf 'Tests: enabled\n'; else printf 'Tests: skipped\n'; fi
printf 'Git: '; git rev-parse --short HEAD 2>/dev/null || true
printf 'Disk: '; df -h . | awk 'NR==2 {print $4 " free on " $6}'

((INSTALL_DEPS)) && install_deps
((DO_PULL)) && with_proxy git_pull_ff

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

# Drop stale package/feeds symlinks left after upstream packages are removed
# (e.g. routing no longer ships bmx7/olsrd → "dependency does not exist" noise).
prune_stale_feed_symlinks() {
	local -a stale=()
	local link
	[[ -d package/feeds ]] || return 0
	while IFS= read -r -d '' link; do
		stale+=("$link")
	done < <(find package/feeds -xtype l -print0 2>/dev/null || true)
	((${#stale[@]})) || return 0
	log "Pruning ${#stale[@]} stale package/feeds symlink(s)"
	printf '  %s\n' "${stale[@]}"
	rm -f -- "${stale[@]}"
}

if ((FEEDS)); then
	log "feeds update / install"
	# feeds update hits git.openwrt.org / GitHub; use the same proxy when enabled.
	with_proxy ./scripts/feeds update -a
	./scripts/feeds install -a
	prune_stale_feed_symlinks
fi

# After feeds so feeds/luci/luci.mk exists when packages are scanned/compiled.
if ((THEMES)); then
	fetch_community_themes
else
	prune_community_theme_trees
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
initramfs=("$OUT"/*askey_sbe1v1k*initramfs*)
sysupgrade=("$OUT"/*askey_sbe1v1k*sysupgrade*)
shopt -u nullglob
((${#arts[@]} > 0)) || die "build finished but no *askey_sbe1v1k* artifacts in $OUT"
((${#initramfs[@]} > 0)) || die "missing initramfs image (*askey_sbe1v1k*initramfs*) in $OUT"
((${#sysupgrade[@]} > 0)) || die "missing sysupgrade image (*askey_sbe1v1k*sysupgrade*) in $OUT"
ls -lh "${arts[@]}"

# Host-side regression checks (upgrade tar preflight + tree invariants).
if ((RUN_TESTS)) && [[ -f "$SCRIPT_DIR/tests/run.sh" ]]; then
	log "Running scripts/sbe1v1k/tests/run.sh"
	bash "$SCRIPT_DIR/tests/run.sh" "${sysupgrade[0]}" \
		|| die "SBE1V1K host tests failed"
elif ((!RUN_TESTS)); then
	log "Skipping host tests (--skip-tests)"
fi

# Typical names for TFTP / sysupgrade:
#   *-askey_sbe1v1k-initramfs-uImage.itb
#   *-askey_sbe1v1k-squashfs-sysupgrade.bin
#   *-askey_sbe1v1k-squashfs-factory.bin

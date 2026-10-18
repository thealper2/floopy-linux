# Shared settings for all build steps. Sourced, not executed.
# Every variable can be overridden from the environment, e.g.:
#   KERNEL_VERSION=6.18.57 JOBS=4 bash build.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Build on the Linux (ext4) filesystem: /mnt/c and /mnt/d are 5-10x slower
# under WSL2 and are not case-sensitive, which breaks the kernel tree.
BUILD_DIR="${BUILD_DIR:-$HOME/floppy-linux-build}"
OUT_DIR="${OUT_DIR:-$REPO_DIR/out}"

# Empty = ask kernel.org for the latest stable release.
KERNEL_VERSION="${KERNEL_VERSION:-}"
BUSYBOX_TAG="${BUSYBOX_TAG:-1_38_0}"

# 32-bit userspace toolchain (Debian/Ubuntu package: gcc-i686-linux-gnu).
CROSS="${CROSS:-i686-linux-gnu-}"
JOBS="${JOBS:-$(nproc)}"

# BusyBox applets (Kconfig symbol names without CONFIG_).
# The first line is the required core; the second is a few cheap extras.
BB_APPLETS="${BB_APPLETS:-ASH SH_IS_ASH CAT DATE ECHO LS VI
  CLEAR MKDIR PWD RM CP MV TOUCH UNAME FEATURE_EDITING}"

FLOPPY_KB=1440

# WSL appends the Windows PATH (spaces, parentheses, slow 9p lookups).
# A clean PATH keeps Kbuild and BusyBox's scripts happy.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

need() {
	for tool in "$@"; do
		command -v "$tool" >/dev/null 2>&1 ||
			die "'$tool' not found. Run: bash scripts/00-deps.sh"
	done
}

# Resolve "latest stable" once and remember it, so later steps agree.
resolve_kernel_version() {
	if [ -z "$KERNEL_VERSION" ] && [ -f "$BUILD_DIR/.kernel-version" ]; then
		KERNEL_VERSION="$(cat "$BUILD_DIR/.kernel-version")"
	fi
	if [ -z "$KERNEL_VERSION" ]; then
		KERNEL_VERSION="$(curl -fsSL https://www.kernel.org/releases.json |
			python3 -c 'import json,sys; print(json.load(sys.stdin)["latest_stable"]["version"])')" ||
			die "Could not query kernel.org. Set KERNEL_VERSION manually."
	fi
	echo "$KERNEL_VERSION" > "$BUILD_DIR/.kernel-version"
	KERNEL_DIR="$BUILD_DIR/linux-$KERNEL_VERSION"
}

human() { numfmt --to=iec --suffix=B "$1"; }

mkdir -p "$BUILD_DIR" "$OUT_DIR"

#!/usr/bin/env bash
# Step 2: build a static, 32-bit BusyBox with only a handful of applets.
#   MENUCONFIG=1 bash scripts/02-busybox.sh   -> also opens menuconfig
source "$(dirname "$0")/common.sh"
need make git "${CROSS}gcc"

BB_DIR="$BUILD_DIR/busybox"
cd "$BUILD_DIR"
if [ ! -d "$BB_DIR" ]; then
	log "Cloning BusyBox $BUSYBOX_TAG"
	git clone --depth 1 --branch "$BUSYBOX_TAG" https://git.busybox.net/busybox "$BB_DIR" || {
		warn "git.busybox.net unreachable, falling back to the release tarball"
		ver="${BUSYBOX_TAG//_/.}"
		wget -c "https://busybox.net/downloads/busybox-$ver.tar.bz2"
		tar xf "busybox-$ver.tar.bz2" && mv "busybox-$ver" "$BB_DIR"
	}
fi
cd "$BB_DIR"

log "make allnoconfig (start with zero applets)"
make allnoconfig >/dev/null

# Set CONFIG_<key>=<value>, replacing whatever allnoconfig wrote.
set_opt() {
	sed -i -e "/^# CONFIG_$1 is not set$/d" -e "/^CONFIG_$1=/d" .config
	echo "CONFIG_$1=$2" >> .config
}

set_opt STATIC y                                  # no shared libc on the floppy
set_opt CROSS_COMPILER_PREFIX "\"$CROSS\""        # i686-linux-gnu-gcc etc.
sed -i '/CONFIG_SH_IS_NONE/d' .config             # "sh" choice -> ash below
for applet in $BB_APPLETS; do
	set_opt "$applet" y
done

# Answer every newly visible sub-option with its default.
make oldconfig < <(yes "") >/dev/null

if [ "${MENUCONFIG:-0}" = 1 ]; then
	make menuconfig
fi

for opt in STATIC $BB_APPLETS; do
	grep -q "^CONFIG_$opt=y" .config || die "CONFIG_$opt did not stick in .config"
done

log "Building BusyBox with $JOBS parallel jobs"
make -j"$JOBS"
make busybox.links >/dev/null   # applet list, used by 03-initramfs.sh

file busybox | grep -q 'ELF 32-bit.*statically linked' ||
	die "busybox is not a static 32-bit binary: $(file busybox)"

cp busybox "$OUT_DIR/busybox"
cp .config "$OUT_DIR/busybox.config"
log "BusyBox ready: $OUT_DIR/busybox ($(human "$(stat -c %s busybox)"))"

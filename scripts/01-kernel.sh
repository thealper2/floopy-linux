#!/usr/bin/env bash
# Step 1: download and build a tiny 32-bit (i386) Linux kernel.
#   MENUCONFIG=1 bash scripts/01-kernel.sh   -> also opens menuconfig
source "$(dirname "$0")/common.sh"
need make gcc curl wget tar xz flex bison bc
resolve_kernel_version

MAJOR="${KERNEL_VERSION%%.*}"
TARBALL="linux-$KERNEL_VERSION.tar.xz"
URL="https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x/$TARBALL"

cd "$BUILD_DIR"
if [ ! -d "$KERNEL_DIR" ]; then
	log "Downloading $URL"
	wget -c "$URL"
	log "Extracting $TARBALL"
	tar xf "$TARBALL"
fi
cd "$KERNEL_DIR"

# ARCH=i386 selects the 32-bit x86 kernel. The kernel does not use libc,
# so the host gcc (with -m32) builds it fine; no cross compiler needed here.
KMAKE=(make ARCH=i386 -j"$JOBS")

log "make tinyconfig (absolute minimum configuration)"
"${KMAKE[@]}" tinyconfig

log "Enabling the options a bootable floppy needs"
./scripts/config --file .config \
	--enable  BLK_DEV_INITRD \
	--set-str INITRAMFS_SOURCE "" \
	--enable  RD_LZMA \
	--disable RD_GZIP --disable RD_BZIP2 --disable RD_XZ \
	--disable RD_LZO  --disable RD_LZ4   --disable RD_ZSTD \
	--enable  PRINTK \
	--enable  BINFMT_ELF \
	--enable  BINFMT_SCRIPT \
	--enable  TTY \
	--enable  VT --enable VT_CONSOLE --enable VGA_CONSOLE \
	--enable  SERIAL_8250 --enable SERIAL_8250_CONSOLE

# Fill in defaults for anything the options above made visible.
"${KMAKE[@]}" olddefconfig

if [ "${MENUCONFIG:-0}" = 1 ]; then
	"${KMAKE[@]}" menuconfig
fi

# Kconfig silently drops options whose dependencies are missing; catch that.
for opt in BLK_DEV_INITRD RD_LZMA PRINTK BINFMT_ELF TTY VT VT_CONSOLE \
           VGA_CONSOLE SERIAL_8250 SERIAL_8250_CONSOLE; do
	grep -q "^CONFIG_$opt=y" .config || die "CONFIG_$opt did not stick in .config"
done
grep -q '^CONFIG_X86_32=y' .config || die "Not a 32-bit config"

log "Building bzImage with $JOBS parallel jobs"
"${KMAKE[@]}" bzImage

cp arch/x86/boot/bzImage "$OUT_DIR/bzImage"
cp .config "$OUT_DIR/kernel.config"
log "Kernel $KERNEL_VERSION ready: $OUT_DIR/bzImage ($(human "$(stat -c %s "$OUT_DIR/bzImage")"))"

#!/usr/bin/env bash
# Step 0: install build dependencies on Debian/Ubuntu (needs sudo).
source "$(dirname "$0")/common.sh"

PACKAGES=(
	build-essential bc bison flex libncurses-dev libssl-dev libelf-dev  # kernel build
	gcc-i686-linux-gnu binutils-i686-linux-gnu libc6-dev-i386-cross     # 32-bit userspace
	cpio xz-utils                                                       # initramfs + lzma
	syslinux syslinux-common mtools dosfstools                          # floppy image
	qemu-system-x86                                                     # testing
	git wget curl python3
)

log "Installing: ${PACKAGES[*]}"
sudo apt-get update
sudo apt-get install -y "${PACKAGES[@]}"

log "Toolchain check"
"${CROSS}gcc" --version | head -1
gcc --version | head -1

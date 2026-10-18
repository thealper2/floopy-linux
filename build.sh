#!/usr/bin/env bash
# Build everything: kernel -> BusyBox -> initramfs -> floppy image.
# Dependencies are installed separately (needs sudo): bash scripts/00-deps.sh
source "$(dirname "$0")/scripts/common.sh"

S="$REPO_DIR/scripts"
bash "$S/01-kernel.sh"
bash "$S/02-busybox.sh"
bash "$S/03-initramfs.sh"
bash "$S/04-floppy.sh"

resolve_kernel_version
log "Done. Linux $KERNEL_VERSION + BusyBox ${BUSYBOX_TAG//_/.}"
ls -l "$OUT_DIR"
echo
echo "Test it:  bash scripts/05-qemu.sh          (kernel + initramfs)"
echo "          bash scripts/05-qemu.sh floppy   (full floppy boot)"

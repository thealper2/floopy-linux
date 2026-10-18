#!/usr/bin/env bash
# Step 4: create a bootable 1.44 MB floppy image (FAT12 + SYSLINUX).
# Works on a plain file, so no root, loop devices or real floppy drive needed.
source "$(dirname "$0")/common.sh"
need syslinux mcopy mdir

IMG="$OUT_DIR/floppy.img"
for f in bzImage init.cpio.lzma; do
	[ -f "$OUT_DIR/$f" ] || die "$OUT_DIR/$f missing. Run the earlier steps first."
done

log "Creating empty ${FLOPPY_KB} KB image"
dd if=/dev/zero of="$IMG" bs=1k count="$FLOPPY_KB" status=none

log "Formatting as FAT12"
if command -v mkfs.vfat >/dev/null; then
	mkfs.vfat -n FLOPLINUX "$IMG" >/dev/null
else
	mformat -i "$IMG" -f "$FLOPPY_KB" -v FLOPLINUX ::
fi

log "Installing SYSLINUX boot sector + ldlinux.sys/ldlinux.c32"
syslinux --install "$IMG"

log "Copying kernel, initramfs and syslinux.cfg"
mcopy -i "$IMG" -o "$OUT_DIR/bzImage" "$OUT_DIR/init.cpio.lzma" \
	"$REPO_DIR/config/syslinux.cfg" ::/ ||
	die "Does not fit on the floppy. See 'Size budget' in README.md."

mdir -i "$IMG" ::/
# mtools groups digits with spaces: "  1 024 bytes free"
free="$(mdir -i "$IMG" ::/ | sed -n 's/ bytes free//p' | tr -d ' ')"
log "Floppy image ready: $IMG ($(human "${free:-0}") free)"

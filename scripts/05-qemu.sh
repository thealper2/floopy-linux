#!/usr/bin/env bash
# Step 5: boot the result in QEMU.
#   bash scripts/05-qemu.sh            kernel + initramfs directly (VGA window)
#   bash scripts/05-qemu.sh floppy     boot floppy.img through SYSLINUX
#   bash scripts/05-qemu.sh serial     no window, console in this terminal
#                                      (quit with Ctrl-A then X)
source "$(dirname "$0")/common.sh"
need qemu-system-i386

MODE="${1:-kernel}"
MEM="${MEM:-32M}"   # Linux 7.x needs ~24M here; 16M hangs after SYSLINUX
QEMU=(qemu-system-i386 -m "$MEM" -no-reboot)

case "$MODE" in
kernel)
	exec "${QEMU[@]}" -kernel "$OUT_DIR/bzImage" -initrd "$OUT_DIR/init.cpio.lzma" \
		-append "rdinit=/sh"
	;;
serial)
	exec "${QEMU[@]}" -nographic -kernel "$OUT_DIR/bzImage" \
		-initrd "$OUT_DIR/init.cpio.lzma" -append "rdinit=/sh console=ttyS0"
	;;
floppy)
	exec "${QEMU[@]}" -drive file="$OUT_DIR/floppy.img",if=floppy,format=raw -boot a
	;;
*)
	die "Unknown mode '$MODE' (use: kernel | serial | floppy)"
	;;
esac

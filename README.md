# Floppy Linux

**English** | [Türkçe](README.tr.md)

A modern Linux kernel and a BusyBox shell on a single **1.44 MB floppy disk**,
built from source with a few small, readable shell scripts. It boots
in QEMU and on real (vintage) PCs through SYSLINUX.

```
BIOS ─► SYSLINUX (boot sector + ldlinux.sys) ─► bzImage (Linux 7.x, tinyconfig)
     ─► init.cpio.lzma unpacked into RAM ─► rdinit=/sh ─► BusyBox ash shell
```

| File               | What it is                                        | Size (Linux 7.2.11, BusyBox 1.38.0) |
| ------------------ | ------------------------------------------------- | ----------------------------------- |
| `out/bzImage`      | 32-bit kernel, `tinyconfig` + a few options       | 799,232 B (≈ 781 KB)                |
| `out/busybox`      | static 32-bit BusyBox (glibc), 15 applets         | ≈ 1.2 MB uncompressed               |
| `out/init.cpio.lzma` | initramfs: BusyBox + hard links, LZMA          | 470,138 B (≈ 460 KB)                |
| `out/floppy.img`   | bootable FAT12 floppy image with all of the above | 1,474,560 B — **8.5 KB free**       |

Tested in QEMU (`qemu-system-i386`), booting both directly and from the
floppy image through SYSLINUX, on both the VGA and the serial console. It
needs **at least ~24 MB RAM**; with 16 MB, Linux 7.x hangs after SYSLINUX.

---

## Contents

1. [Requirements](#requirements)
2. [Quick start](#quick-start)
3. [Repository layout](#repository-layout)
4. [Step by step](#step-by-step)
   1. [Dependencies](#1-dependencies)
   2. [Kernel](#2-linux-kernel-tiny-configuration)
   3. [BusyBox](#3-user-space-busybox)
   4. [initramfs](#4-initramfs)
   5. [Testing in QEMU](#5-testing-in-qemu)
   6. [Floppy image / real media](#6-bootable-floppy--real-media)
5. [Customizing](#customizing)
6. [Size budget](#size-budget)
7. [Troubleshooting](#troubleshooting)
8. [License](#license)

---

## Requirements

- **Windows 10/11 with WSL2 + Ubuntu** (tested on Ubuntu 24.04), or any
  Debian/Ubuntu machine. Other distros work if you install the equivalent
  packages.
- About 2 GB of free disk space and an internet connection (kernel tarball
  ≈ 150 MB, BusyBox git clone).
- To see the QEMU window from WSL you need WSLg (included in Windows 11 and
  recent Windows 10 builds). Without a GUI, use the `serial` mode.

> **Why build inside the Linux filesystem?** The scripts put the sources in
> `~/floppy-linux-build` (WSL's ext4 disk), not in `/mnt/c` or `/mnt/d`.
> Windows drives under WSL2 are much slower and not case-sensitive. The
> kernel tree has files whose names differ only in case
> (`xt_TCPMSS.c` / `xt_tcpmss.c`), so it would break there.
> Only the finished files are copied to `out/` in this repository.

## Quick start

Open **Ubuntu** (WSL) and run:

```bash
git clone https://github.com/<your-user>/floppy-linux.git
cd floppy-linux
bash scripts/00-deps.sh      # once; uses sudo apt-get
bash build.sh                # kernel + BusyBox + initramfs + floppy.img
bash scripts/05-qemu.sh floppy
```

The first build takes a few minutes, mostly downloading and compiling the
kernel. When the shell prompt appears, try:

```sh
# ls /bin
# echo hello; date; uname -a
# vi /hello.txt
```

> The scripts are run with `bash script.sh`, so they work even if Git on
> Windows lost the executable bit. Everything lives in RAM: changes are gone
> after a reboot.

## Repository layout

```
build.sh               runs steps 1-4 in order
config/syslinux.cfg    boot menu written to the floppy
scripts/common.sh      shared settings (versions, paths, applet list)
scripts/00-deps.sh     step 0: apt-get install everything
scripts/01-kernel.sh   step 1: download + tinyconfig + build bzImage
scripts/02-busybox.sh  step 2: clone + allnoconfig + static 32-bit build
scripts/03-initramfs.sh step 3: fs/ tree, hard links, cpio, lzma
scripts/04-floppy.sh   step 4: 1.44 MB FAT12 image + SYSLINUX
scripts/05-qemu.sh     step 5: boot it (kernel | serial | floppy)
out/                   build results (git-ignored)
```

---

## Step by step

Each step is a separate script, so you can rerun or change one step without
starting from scratch. The sections below show what each script does and
explain *why*. You can also type the commands by hand.

### 1. Dependencies

```bash
bash scripts/00-deps.sh
```

which runs:

```bash
sudo apt-get install -y build-essential bc bison flex libncurses-dev libssl-dev libelf-dev \
    gcc-i686-linux-gnu binutils-i686-linux-gnu libc6-dev-i386-cross \
    cpio xz-utils syslinux syslinux-common mtools dosfstools qemu-system-x86 \
    git wget curl python3
```

- `bison`, `flex`, `bc`, `libssl-dev`, `libelf-dev`: needed by the kernel build system.
- `libncurses-dev`: needed for `make menuconfig`.
- `gcc-i686-linux-gnu`: a **32-bit cross compiler** plus a 32-bit glibc. The
  WSL host is x86-64, but the floppy targets 32-bit PCs. BusyBox needs a
  32-bit C library to link against statically, and this package provides one.
- `syslinux`, `mtools`, `dosfstools`: build the floppy image from a plain
  file, with no root access and no loop devices.
- `xz-utils` provides the `lzma` command; `qemu-system-x86` provides `qemu-system-i386`.

### 2. Linux kernel (tiny configuration)

```bash
bash scripts/01-kernel.sh                 # latest stable from kernel.org
KERNEL_VERSION=6.18.57 bash scripts/01-kernel.sh   # or pin a version
MENUCONFIG=1 bash scripts/01-kernel.sh    # also open menuconfig
```

What happens:

```bash
wget https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.11.tar.xz
tar xf linux-7.2.11.tar.xz && cd linux-7.2.11
make ARCH=i386 tinyconfig
./scripts/config --enable BLK_DEV_INITRD --enable RD_LZMA --disable RD_GZIP ... 
make ARCH=i386 olddefconfig
make ARCH=i386 -j$(nproc) bzImage
cp arch/x86/boot/bzImage out/
```

**Why `tinyconfig`?** A distro kernel is tens of megabytes. `tinyconfig`
starts from "everything off", optimizes for size (`-Os`) and uses the
smallest allocator (`SLUB_TINY`). We then turn on only what is needed to
reach a shell:

| Option (menuconfig path)                                                   | Why |
| -------------------------------------------------------------------------- | --- |
| `BLK_DEV_INITRD` — *General setup → Initial RAM filesystem and RAM disk support* | Lets the kernel unpack our `init.cpio.lzma` into RAM as the root filesystem. |
| `RD_LZMA` on, `RD_GZIP/BZIP2/XZ/LZO/LZ4/ZSTD` off — *same menu*            | Each decompressor costs kilobytes; we only ever need LZMA. |
| `PRINTK` — *General setup → Configure standard kernel features (expert users) → Enable support for printk* | Without it the kernel boots silently, and a failed boot shows nothing to debug. |
| `BINFMT_ELF` — *Executable file formats → Kernel support for ELF binaries* | BusyBox is an ELF binary; without this the kernel cannot run *any* program. |
| `BINFMT_SCRIPT` — *same menu, `#!` scripts*                                | Lets you run your own shell scripts. Very small. |
| `TTY`, `VT`, `VT_CONSOLE`, `VGA_CONSOLE` — *Device Drivers → Character devices* | A text console on the screen and keyboard input for the shell. |
| `SERIAL_8250`, `SERIAL_8250_CONSOLE` — *Device Drivers → Character devices → Serial drivers* | Optional COM1 console: used for headless QEMU testing and for old PCs with no working video. Costs 20 KB (bzImage 799,232 → 778,752 B), so it is a candidate to remove if space gets tight. |

`ARCH=i386` builds a 32-bit x86 kernel. The kernel does not use a C
library, so the host `gcc -m32` builds it and no cross compiler is needed
for this step. The script checks `.config` afterwards because Kconfig
**silently drops** options whose dependencies are missing.

The kernel image itself is compressed with **XZ** (the `tinyconfig`
default, `KERNEL_XZ`). On x86, XZ includes a branch-conversion filter that
makes it a few percent smaller than LZMA for executable code.

> **CPU support:** Linux 7.x removed i486 and TSC-less i586 support. The
> lowest CPU type left is `M586TSC` (Intel Pentium). The default here is
> `M686` (Pentium Pro / II and newer), which matches Ubuntu's i686 glibc
> used for BusyBox. If you want an older machine, see
> [Troubleshooting](#troubleshooting).

### 3. User space (BusyBox)

```bash
bash scripts/02-busybox.sh
MENUCONFIG=1 bash scripts/02-busybox.sh   # pick applets interactively
```

What happens:

```bash
git clone --depth 1 --branch 1_38_0 https://git.busybox.net/busybox && cd busybox
make allnoconfig
# in .config:
#   CONFIG_STATIC=y
#   CONFIG_CROSS_COMPILER_PREFIX="i686-linux-gnu-"
#   CONFIG_ASH=y CONFIG_SH_IS_ASH=y CONFIG_CAT=y CONFIG_DATE=y CONFIG_ECHO=y
#   CONFIG_LS=y CONFIG_VI=y  (+ a few cheap extras, see below)
make oldconfig   # defaults for newly visible sub-options
make -j$(nproc)
```

- **`allnoconfig`**: BusyBox has 400+ applets. Starting from zero and
  adding only what we need keeps the binary small.
- **Static linking (`CONFIG_STATIC`)**: the floppy has no `/lib`, no
  `libc.so` and no dynamic loader. A static binary contains everything it
  needs, so the root filesystem can be a single file.
- **`CROSS_COMPILER_PREFIX="i686-linux-gnu-"`**: builds with
  `i686-linux-gnu-gcc` and links against the 32-bit glibc, so the result
  runs on our 32-bit kernel. The script fails if `file busybox` does not say
  `ELF 32-bit ... statically linked`.
- **Applets**: required core `ash`, `cat`, `date`, `echo`, `ls`, `vi`.
  Cheap extras: `clear`, `mkdir`, `pwd`, `rm`, `cp`, `mv`, `touch`,
  `uname`, and command-line editing (arrow keys/history in `ash`). The list
  is `BB_APPLETS` in `scripts/common.sh`.

### 4. initramfs

```bash
bash scripts/03-initramfs.sh
```

What happens:

```bash
mkdir -p fs/bin && cp busybox/busybox fs/ && cd fs
ln busybox sh                       # the hard link the kernel will execute
for a in ls cat echo ...; do ln busybox bin/$a; done
find . -print0 | cpio --null -o --format=newc -R root:root > ../init.cpio
lzma -z -k --lzma1=preset=9e,dict=1MiB ../init.cpio   # -> init.cpio.lzma
```

- **Why hard-link `sh`?** BusyBox is a multi-call binary: it looks at the
  name it was started with (`argv[0]`) to decide which applet to run. The
  kernel is told `rdinit=/sh`, runs `/sh`, and BusyBox starts as the `ash`
  shell. A hard link is just another directory entry for the same file, so
  it uses no extra space on the disk. A copy would double the size.
- **`/bin/*` links**: the same trick for every applet, so you can type
  `ls` instead of `busybox ls`. `ash` searches `/bin` by default.
- **`newc` cpio**: the only archive format the kernel's initramfs unpacker
  understands. `-R root:root` makes the files owned by root instead of
  your WSL user.
- **`/dev/console`**: we do not create it (that would need root). The
  kernel always unpacks a small built-in initramfs containing
  `/dev/console` first, and our archive is unpacked on top of it.
- **LZMA with a 1 MiB dictionary**: `lzma -9` would ask the kernel to
  allocate a 64 MiB dictionary while unpacking, which fails on machines
  with little RAM. Our archive is smaller than 1 MiB, so a 1 MiB dictionary
  compresses it just as well.

### 5. Testing in QEMU

Test before writing real media:

```bash
bash scripts/05-qemu.sh            # = qemu-system-i386 -kernel out/bzImage -initrd out/init.cpio.lzma -append "rdinit=/sh"
bash scripts/05-qemu.sh serial     # no window, console in this terminal; quit with Ctrl-A, X
bash scripts/05-qemu.sh floppy     # boot out/floppy.img via SYSLINUX, exactly like a real PC
MEM=24M bash scripts/05-qemu.sh floppy   # default is 32M; 24M still works, 16M does not
```

A successful boot ends like this:

```
Run /sh as init process

BusyBox v1.38.0 (...) built-in shell (ash)

# uname -a
Linux (none) 7.2.11 #1 PREEMPT ... i686
```

The shell itself is PID 1: there is no `init` behind it. If you type `exit`,
the kernel panics with *"Attempted to kill init"*. That is expected; just
reset the machine.

### 6. Bootable floppy / real media

```bash
bash scripts/04-floppy.sh
```

What happens (all on a plain file, no root needed):

```bash
dd if=/dev/zero of=out/floppy.img bs=1k count=1440
mkfs.vfat -n FLOPLINUX out/floppy.img
syslinux --install out/floppy.img
mcopy -i out/floppy.img out/bzImage out/init.cpio.lzma config/syslinux.cfg ::/
```

`config/syslinux.cfg` boots automatically after 5 seconds:

```
LABEL floppy   -> KERNEL bzImage  APPEND initrd=init.cpio.lzma rdinit=/sh
LABEL serial   -> same, plus console=ttyS0,115200
```

Without a config file you could type the same thing at the `boot:` prompt:
`bzImage initrd=init.cpio.lzma rdinit=/sh`.

#### Writing to a real floppy or USB stick

WSL2 cannot see floppy drives or USB sticks directly. Choose one:

- **On a Linux PC** (replace `/dev/sdX` with the right device and check it
  with `lsblk` first, because this **erases the device**):

  ```bash
  sudo dd if=out/floppy.img of=/dev/sdX bs=1k conv=fsync status=progress
  sync
  ```

  Or do it by hand, like the original guide:

  ```bash
  sudo mkfs.vfat /dev/sdX
  sudo syslinux --install /dev/sdX
  sudo mount /dev/sdX /mnt
  sudo cp out/bzImage out/init.cpio.lzma config/syslinux.cfg /mnt/
  sudo umount /mnt && sync
  ```

- **On Windows**: write `floppy.img` to a (USB) floppy drive with a raw image
  writer such as RawWrite for Windows or `dd` for Windows. For a USB stick,
  Rufus in "DD image" mode works.
- **From WSL2** you can attach a USB device with
  [usbipd-win](https://github.com/dorssel/usbipd-win), then use the Linux
  commands above.
- **Virtual machines**: attach `floppy.img` as a floppy drive in
  VirtualBox, VMware, 86Box or PCem.

---

## Customizing

All settings are in `scripts/common.sh` and can be overridden per run:

| Variable         | Default                     | Meaning |
| ---------------- | --------------------------- | ------- |
| `KERNEL_VERSION` | latest stable (kernel.org)  | e.g. `6.18.57` for an LTS kernel |
| `BUSYBOX_TAG`    | `1_38_0`                    | BusyBox git tag |
| `BB_APPLETS`     | see file                    | Kconfig names of applets to enable |
| `CROSS`          | `i686-linux-gnu-`           | userspace toolchain prefix |
| `JOBS`           | `$(nproc)`                  | parallel make jobs |
| `BUILD_DIR`      | `~/floppy-linux-build`      | where sources are built |
| `MENUCONFIG`     | `0`                         | `1` = open menuconfig in steps 1/2 |

Example: add `free` and `hexdump`, then rebuild only what changed:

```bash
BB_APPLETS="ASH SH_IS_ASH CAT DATE ECHO LS VI FREE HEXDUMP" bash scripts/02-busybox.sh
bash scripts/03-initramfs.sh && bash scripts/04-floppy.sh
```

> The kernel version is remembered in `~/floppy-linux-build/.kernel-version`.
> To update to a newer kernel, delete that file.

## Size budget

A 1.44 MB floppy holds 1,474,560 bytes. With the default settings:

| Item                                         | Bytes      |
| -------------------------------------------- | ---------- |
| FAT12 boot sector, FATs, root directory      | ≈ 17 KB    |
| SYSLINUX 6 (`ldlinux.sys` + `ldlinux.c32`)   | ≈ 175 KB   |
| `bzImage` (Linux 7.2.11)                     | 799,232    |
| `init.cpio.lzma` (BusyBox 1.38.0, glibc)     | 470,138    |
| `syslinux.cfg`                               | 301        |
| **Free**                                     | **8,704**  |

That is a very tight fit. A newer kernel or an extra applet can push it
over the limit, and then `04-floppy.sh` stops with "Disk full". To free
space, try these in order:

1. Remove applets you do not need from `BB_APPLETS`.
2. Remove `SERIAL_8250*` from `01-kernel.sh` (saves 20 KB).
3. Use an older, smaller kernel, e.g. `KERNEL_VERSION=6.6.159` (LTS).
4. Replace glibc with **musl**. Static glibc is the largest single part of
   BusyBox here, and a musl build is usually much smaller. This needs an
   `i686-linux-musl-` toolchain (e.g. from musl.cc); point `CROSS=` at it.
5. Use SYSLINUX 4.x, which has no `ldlinux.c32`, and save about 120 KB.

## Troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| `i686-linux-gnu-gcc: not found` | Run `bash scripts/00-deps.sh`. |
| `CONFIG_xxx did not stick in .config` | A dependency of that option is missing in the new kernel version. Run with `MENUCONFIG=1`, find the option with `/`, and check its *Depends on* line. |
| `Kernel panic - not syncing: No working init found` | Missing `rdinit=/sh`, a broken initramfs, or a BusyBox that is not static/32-bit. Check `file out/busybox`. |
| `Initramfs unpacking failed: ...` / `junk in compressed archive` | The kernel does not have `RD_LZMA`, or the file was compressed with another format. |
| Stops after `Loading init.cpio.lzma... ok`, blinking cursor | Not enough RAM. Linux 7.x needs about 24 MB here; 16 MB hangs. |
| Kernel boots, then nothing on screen | Booted with `console=ttyS0`: use the `floppy` label, or check `VT_CONSOLE`/`VGA_CONSOLE`. |
| `Illegal instruction` right after boot | The CPU is older than i686. Use `M586TSC` in menuconfig *and* a userspace built for i586 (e.g. a musl i586 toolchain). Real i486 machines need an older kernel that still offers `M486`. |
| `Attempted to kill init` | You typed `exit` in the shell, which is PID 1. Reboot. |
| Build is very slow / strange file errors | You are building under `/mnt/c` or `/mnt/d`. Keep `BUILD_DIR` on the WSL filesystem. |
| `$'\r': command not found` | The scripts got Windows (CRLF) line endings. `.gitattributes` prevents this on clone; for existing files run `sed -i 's/\r$//' build.sh scripts/*.sh`. |
| QEMU: `gtk initialization failed` | No GUI in WSL. Use `bash scripts/05-qemu.sh serial`. |

## License

The scripts in this repository are yours to license (MIT is a common
choice; add a `LICENSE` file). The **Linux kernel** and **BusyBox** are
GPL-2.0. If you publish `floppy.img` or `bzImage` (for example as a GitHub
Release), the GPL requires that the matching source is available. Name the
exact versions (shown above and in `out/kernel.config` / `out/busybox.config`)
and link to kernel.org and busybox.net.

Inspired by [FLOPPINUX](https://github.com/w84death/floppinux) by
Krzysztof Krystian Jankowski.

# Floppy Linux

[English](README.md) | **Türkçe**

Tek bir **1.44 MB disket** üzerinde modern bir Linux çekirdeği ve BusyBox
kabuğu. Her şey kaynak koddan, birkaç küçük ve okunabilir shell betiğiyle
derlenir. QEMU'da ve SYSLINUX aracılığıyla gerçek (eski) PC'lerde açılır.

```
BIOS ─► SYSLINUX (boot sektörü + ldlinux.sys) ─► bzImage (Linux 7.x, tinyconfig)
     ─► init.cpio.lzma RAM'e açılır ─► rdinit=/sh ─► BusyBox ash kabuğu
```

| Dosya                | Nedir                                              | Boyut (Linux 7.2.11, BusyBox 1.38.0) |
| -------------------- | -------------------------------------------------- | ------------------------------------ |
| `out/bzImage`        | 32-bit çekirdek, `tinyconfig` + birkaç seçenek     | 799.232 B (≈ 781 KB)                 |
| `out/busybox`        | statik 32-bit BusyBox (glibc), 15 applet           | ≈ 1,2 MB (sıkıştırılmamış)           |
| `out/init.cpio.lzma` | initramfs: BusyBox + hard link'ler, LZMA           | 470.138 B (≈ 460 KB)                 |
| `out/floppy.img`     | yukarıdakilerin hepsini içeren açılabilir FAT12 disket imajı | 1.474.560 B — **8,5 KB boş** |

QEMU'da (`qemu-system-i386`) test edildi. Hem doğrudan çekirdekle hem de
disket imajından SYSLINUX üzerinden, hem VGA hem seri konsolda açıldı.
**En az ~24 MB RAM** gerekir: 16 MB ile Linux 7.x, SYSLINUX'tan sonra takılıyor.

---

## İçindekiler

1. [Gereksinimler](#gereksinimler)
2. [Hızlı başlangıç](#hızlı-başlangıç)
3. [Depo yapısı](#depo-yapısı)
4. [Adım adım](#adım-adım)
   1. [Bağımlılıklar](#1-bağımlılıklar)
   2. [Çekirdek](#2-linux-çekirdeği-tiny-yapılandırma)
   3. [BusyBox](#3-kullanıcı-alanı-busybox)
   4. [initramfs](#4-initramfs)
   5. [QEMU ile test](#5-qemu-ile-test)
   6. [Disket imajı / gerçek ortam](#6-açılabilir-disket--gerçek-ortam)
5. [Özelleştirme](#özelleştirme)
6. [Boyut bütçesi](#boyut-bütçesi)
7. [Sorun giderme](#sorun-giderme)
8. [Lisans](#lisans)

---

## Gereksinimler

- **WSL2 + Ubuntu kurulu Windows 10/11** (Ubuntu 24.04 ile test edildi) ya
  da herhangi bir Debian/Ubuntu makine. Eşdeğer paketleri kurarsanız diğer
  dağıtımlarda da çalışır.
- Yaklaşık 2 GB boş disk alanı ve internet bağlantısı (çekirdek arşivi
  ≈ 150 MB, artı BusyBox git klonu).
- QEMU penceresini WSL'den görmek için WSLg gerekir (Windows 11'de ve yeni
  Windows 10 sürümlerinde hazır gelir). Grafik arayüz yoksa `serial` modunu
  kullanın.

> **Neden Linux dosya sisteminde derliyoruz?** Betikler kaynakları
> `/mnt/c` veya `/mnt/d` yerine `~/floppy-linux-build` dizinine (WSL'in
> ext4 diski) koyar. WSL2 altında Windows sürücüleri çok daha yavaştır ve
> büyük/küçük harf ayrımı yapmaz. Çekirdek ağacında adı yalnızca harf
> büyüklüğüyle ayrılan dosyalar var (`xt_TCPMSS.c` / `xt_tcpmss.c`), bu
> yüzden derleme orada bozulur. Depodaki `out/` dizinine yalnızca bitmiş
> dosyalar kopyalanır.

## Hızlı başlangıç

**Ubuntu** (WSL) terminalini açın ve çalıştırın:

```bash
git clone https://github.com/<kullanici-adiniz>/floppy-linux.git
cd floppy-linux
bash scripts/00-deps.sh      # bir kez; sudo apt-get kullanır
bash build.sh                # çekirdek + BusyBox + initramfs + floppy.img
bash scripts/05-qemu.sh floppy
```

İlk derleme birkaç dakika sürer. Sürenin çoğu çekirdeği indirmek ve
derlemekle geçer. Kabuk istemi (`#`) gelince şunları deneyin:

```sh
# ls /bin
# echo merhaba; date; uname -a
# vi /merhaba.txt
```

> Betikler `bash betik.sh` şeklinde çalıştırılır, bu yüzden Windows'taki
> Git çalıştırma (executable) iznini kaybetse bile sorun çıkmaz. Her şey
> RAM'de çalışır: yeniden başlatınca değişiklikler kaybolur.

## Depo yapısı

```
build.sh                1-4. adımları sırayla çalıştırır
config/syslinux.cfg     diskete yazılan açılış menüsü
scripts/common.sh       ortak ayarlar (sürümler, yollar, applet listesi)
scripts/00-deps.sh      adım 0: gereken her şeyi apt-get ile kurar
scripts/01-kernel.sh    adım 1: indir + tinyconfig + bzImage derle
scripts/02-busybox.sh   adım 2: klonla + allnoconfig + statik 32-bit derleme
scripts/03-initramfs.sh adım 3: fs/ ağacı, hard link'ler, cpio, lzma
scripts/04-floppy.sh    adım 4: 1.44 MB FAT12 imajı + SYSLINUX
scripts/05-qemu.sh      adım 5: çalıştır (kernel | serial | floppy)
out/                    derleme çıktıları (git tarafından yok sayılır)
```

---

## Adım adım

Her adım ayrı bir betik. Böylece her şeyi baştan yapmadan tek bir adımı
yeniden çalıştırabilir ya da değiştirebilirsiniz. Aşağıdaki bölümler her
betiğin ne yaptığını gösterir ve *neden* öyle yaptığını açıklar. Komutları
elle de yazabilirsiniz.

### 1. Bağımlılıklar

```bash
bash scripts/00-deps.sh
```

Bu betik şunu çalıştırır:

```bash
sudo apt-get install -y build-essential bc bison flex libncurses-dev libssl-dev libelf-dev \
    gcc-i686-linux-gnu binutils-i686-linux-gnu libc6-dev-i386-cross \
    cpio xz-utils syslinux syslinux-common mtools dosfstools qemu-system-x86 \
    git wget curl python3
```

- `bison`, `flex`, `bc`, `libssl-dev`, `libelf-dev`: çekirdeğin derleme sistemi bunlara ihtiyaç duyar.
- `libncurses-dev`: `make menuconfig` için gerekir.
- `gcc-i686-linux-gnu`: **32-bit çapraz derleyici** (cross compiler) ve
  32-bit glibc. WSL'deki makine x86-64, ama disket 32-bit PC'leri hedefliyor.
  BusyBox'ı statik bağlamak için 32-bit bir C kütüphanesi gerekir; bu paket
  onu sağlar.
- `syslinux`, `mtools`, `dosfstools`: disket imajını sıradan bir dosya
  üzerinde oluşturur. Root yetkisi ya da loop aygıtı gerekmez.
- `lzma` komutu `xz-utils` paketinden, `qemu-system-i386` ise
  `qemu-system-x86` paketinden gelir.

### 2. Linux çekirdeği (tiny yapılandırma)

```bash
bash scripts/01-kernel.sh                          # kernel.org'daki en son stable sürüm
KERNEL_VERSION=6.18.57 bash scripts/01-kernel.sh   # ya da sabit bir sürüm
MENUCONFIG=1 bash scripts/01-kernel.sh             # menuconfig'i de açar
```

Betiğin yaptıkları:

```bash
wget https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.11.tar.xz
tar xf linux-7.2.11.tar.xz && cd linux-7.2.11
make ARCH=i386 tinyconfig
./scripts/config --enable BLK_DEV_INITRD --enable RD_LZMA --disable RD_GZIP ...
make ARCH=i386 olddefconfig
make ARCH=i386 -j$(nproc) bzImage
cp arch/x86/boot/bzImage out/
```

**Neden `tinyconfig`?** Bir dağıtım çekirdeği onlarca megabayt tutar.
`tinyconfig` "her şey kapalı" durumundan başlar, boyut için optimize eder
(`-Os`) ve en küçük bellek ayırıcıyı (`SLUB_TINY`) kullanır. Sonra
yalnızca bir kabuğa ulaşmak için gerekenleri açıyoruz:

| Seçenek (menuconfig yolu) | Neden |
| ------------------------- | ----- |
| `BLK_DEV_INITRD` — *General setup → Initial RAM filesystem and RAM disk support* | Çekirdeğin `init.cpio.lzma` dosyamızı RAM'e açıp kök dosya sistemi olarak kullanmasını sağlar. |
| `RD_LZMA` açık, `RD_GZIP/BZIP2/XZ/LZO/LZ4/ZSTD` kapalı — *aynı menü* | Her açıcı (decompressor) kilobaytlarca yer kaplar; bize yalnızca LZMA lazım. |
| `PRINTK` — *General setup → Configure standard kernel features (expert users) → Enable support for printk* | Bu olmadan çekirdek sessizce açılır; açılış başarısız olursa hata ayıklamak için hiçbir çıktı görmezsiniz. |
| `BINFMT_ELF` — *Executable file formats → Kernel support for ELF binaries* | BusyBox bir ELF dosyası. Bu seçenek olmadan çekirdek *hiçbir* programı çalıştıramaz. |
| `BINFMT_SCRIPT` — *aynı menü, `#!` betikleri* | Kendi shell betiklerinizi çalıştırmanızı sağlar. Çok küçüktür. |
| `TTY`, `VT`, `VT_CONSOLE`, `VGA_CONSOLE` — *Device Drivers → Character devices* | Ekranda metin konsolu ve kabuk için klavye girişi. |
| `SERIAL_8250`, `SERIAL_8250_CONSOLE` — *Device Drivers → Character devices → Serial drivers* | İsteğe bağlı COM1 konsolu. Ekransız QEMU testleri ve görüntüsü çalışmayan eski PC'ler için kullanılır. 20 KB tutar (bzImage 799.232 → 778.752 B); yer daralırsa ilk çıkarılacak adaydır. |

`ARCH=i386` 32-bit x86 çekirdeği derler. Çekirdek bir C kütüphanesi
kullanmadığı için makinedeki `gcc -m32` onu derleyebilir; bu adımda
çapraz derleyici gerekmez. Betik derlemeden sonra `.config` dosyasını
kontrol eder, çünkü Kconfig bağımlılıkları eksik olan seçenekleri
**sessizce düşürür**.

Çekirdek imajının kendisi **XZ** ile sıkıştırılır (`tinyconfig`
varsayılanı, `KERNEL_XZ`). XZ, x86'da çalıştırılabilir kod için bir
dallanma dönüştürme filtresi (BCJ) içerir ve LZMA'dan birkaç yüzde daha
küçük sonuç verir.

> **CPU desteği:** Linux 7.x, i486 ve TSC'siz i586 desteğini kaldırdı.
> Kalan en düşük CPU tipi `M586TSC` (Intel Pentium). Buradaki varsayılan
> `M686` (Pentium Pro / II ve sonrası); bu, BusyBox için kullanılan
> Ubuntu'nun i686 glibc'siyle uyumlu. Daha eski bir makine hedefliyorsanız
> [Sorun giderme](#sorun-giderme) bölümüne bakın.

### 3. Kullanıcı alanı (BusyBox)

```bash
bash scripts/02-busybox.sh
MENUCONFIG=1 bash scripts/02-busybox.sh   # applet'leri menüden seçmek için
```

Betiğin yaptıkları:

```bash
git clone --depth 1 --branch 1_38_0 https://git.busybox.net/busybox && cd busybox
make allnoconfig
# .config içinde:
#   CONFIG_STATIC=y
#   CONFIG_CROSS_COMPILER_PREFIX="i686-linux-gnu-"
#   CONFIG_ASH=y CONFIG_SH_IS_ASH=y CONFIG_CAT=y CONFIG_DATE=y CONFIG_ECHO=y
#   CONFIG_LS=y CONFIG_VI=y  (+ birkaç ucuz ekstra, aşağıya bakın)
make oldconfig   # yeni görünen alt seçenekler için varsayılanlar
make -j$(nproc)
```

- **`allnoconfig`**: BusyBox'ta 400'den fazla applet var. Sıfırdan
  başlayıp yalnızca gerekenleri eklemek dosyayı küçük tutar.
- **Statik bağlama (`CONFIG_STATIC`)**: diskette `/lib`, `libc.so` ya da
  dinamik yükleyici yok. Statik bir dosya ihtiyaç duyduğu her şeyi
  içinde taşır, böylece kök dosya sistemi tek bir dosyadan oluşabilir.
- **`CROSS_COMPILER_PREFIX="i686-linux-gnu-"`**: `i686-linux-gnu-gcc` ile
  derler ve 32-bit glibc'ye bağlar; sonuç 32-bit çekirdeğimizde çalışır.
  `file busybox` çıktısında `ELF 32-bit ... statically linked`
  yazmıyorsa betik hata vererek durur.
- **Applet'ler**: zorunlu çekirdek `ash`, `cat`, `date`, `echo`, `ls`,
  `vi`. Ucuz ekstralar: `clear`, `mkdir`, `pwd`, `rm`, `cp`, `mv`,
  `touch`, `uname` ve komut satırı düzenleme (`ash`'te ok tuşları ve
  geçmiş). Liste `scripts/common.sh` içindeki `BB_APPLETS` değişkeninde.

### 4. initramfs

```bash
bash scripts/03-initramfs.sh
```

Betiğin yaptıkları:

```bash
mkdir -p fs/bin && cp busybox/busybox fs/ && cd fs
ln busybox sh                       # çekirdeğin çalıştıracağı hard link
for a in ls cat echo ...; do ln busybox bin/$a; done
find . -print0 | cpio --null -o --format=newc -R root:root > ../init.cpio
lzma -z -k --lzma1=preset=9e,dict=1MiB ../init.cpio   # -> init.cpio.lzma
```

- **Neden `sh` için hard link?** BusyBox çok-amaçlı (multi-call) bir
  programdır: hangi applet'i çalıştıracağına, kendisinin hangi adla
  başlatıldığına (`argv[0]`) bakarak karar verir. Çekirdeğe `rdinit=/sh`
  denir, çekirdek `/sh`'yi çalıştırır ve BusyBox `ash` kabuğu olarak
  açılır. Hard link aynı dosyaya işaret eden ikinci bir dizin girdisidir,
  diskte ek yer kaplamaz. Kopyalasaydık boyut iki katına çıkardı.
- **`/bin/*` link'leri**: aynı yöntem her applet için uygulanır; böylece
  `busybox ls` yerine doğrudan `ls` yazabilirsiniz. `ash` varsayılan
  olarak `/bin` dizininde arar.
- **`newc` cpio**: çekirdeğin initramfs açıcısının anladığı tek arşiv
  biçimi. `-R root:root` dosyaların sahibini WSL kullanıcınız yerine root
  yapar.
- **`/dev/console`**: bunu biz oluşturmuyoruz (root yetkisi gerekirdi).
  Çekirdek her zaman önce içinde `/dev/console` bulunan küçük, gömülü bir
  initramfs açar; bizim arşivimiz onun üzerine açılır.
- **1 MiB sözlüklü LZMA**: `lzma -9`, açılış sırasında çekirdekten 64 MiB'lık
  bir sözlük ayırmasını ister; bu da az RAM'li makinelerde başarısız olur.
  Arşivimiz 1 MiB'tan küçük, bu yüzden 1 MiB'lık sözlük aynı oranda sıkıştırır.

### 5. QEMU ile test

Gerçek bir ortama yazmadan önce test edin:

```bash
bash scripts/05-qemu.sh            # = qemu-system-i386 -kernel out/bzImage -initrd out/init.cpio.lzma -append "rdinit=/sh"
bash scripts/05-qemu.sh serial     # pencere yok, konsol bu terminalde; çıkış: Ctrl-A, sonra X
bash scripts/05-qemu.sh floppy     # out/floppy.img'yi SYSLINUX ile açar, tıpkı gerçek bir PC gibi
MEM=24M bash scripts/05-qemu.sh floppy   # varsayılan 32M; 24M çalışıyor, 16M çalışmıyor
```

Başarılı bir açılış şöyle biter:

```
Run /sh as init process

BusyBox v1.38.0 (...) built-in shell (ash)

# uname -a
Linux (none) 7.2.11 #1 PREEMPT ... i686
```

Kabuğun kendisi PID 1: arkasında bir `init` yok. `exit` yazarsanız
çekirdek *"Attempted to kill init"* hatasıyla panic olur. Bu beklenen bir
durum; makineyi yeniden başlatın.

### 6. Açılabilir disket / gerçek ortam

```bash
bash scripts/04-floppy.sh
```

Betiğin yaptıkları (hepsi sıradan bir dosya üzerinde, root gerekmez):

```bash
dd if=/dev/zero of=out/floppy.img bs=1k count=1440
mkfs.vfat -n FLOPLINUX out/floppy.img
syslinux --install out/floppy.img
mcopy -i out/floppy.img out/bzImage out/init.cpio.lzma config/syslinux.cfg ::/
```

`config/syslinux.cfg` 5 saniye sonra kendiliğinden açar:

```
LABEL floppy   -> KERNEL bzImage  APPEND initrd=init.cpio.lzma rdinit=/sh
LABEL serial   -> aynısı, artı console=ttyS0,115200
```

Yapılandırma dosyası olmasaydı aynı şeyi `boot:` istemine elle
yazabilirdiniz: `bzImage initrd=init.cpio.lzma rdinit=/sh`.

#### Gerçek bir diskete ya da USB belleğe yazmak

WSL2 disket sürücülerini ve USB bellekleri doğrudan göremez. Şunlardan
birini seçin:

- **Bir Linux PC'de** (`/dev/sdX` yerine doğru aygıtı yazın ve önce
  `lsblk` ile kontrol edin, çünkü bu işlem **aygıttaki her şeyi siler**):

  ```bash
  sudo dd if=out/floppy.img of=/dev/sdX bs=1k conv=fsync status=progress
  sync
  ```

  Ya da orijinal rehberdeki gibi elle yapın:

  ```bash
  sudo mkfs.vfat /dev/sdX
  sudo syslinux --install /dev/sdX
  sudo mount /dev/sdX /mnt
  sudo cp out/bzImage out/init.cpio.lzma config/syslinux.cfg /mnt/
  sudo umount /mnt && sync
  ```

- **Windows'ta**: `floppy.img`'yi (USB) disket sürücüsüne RawWrite for
  Windows ya da Windows için `dd` gibi ham imaj yazıcılarla yazın. USB
  bellek için Rufus'un "DD imajı" modu çalışır.
- **WSL2'den**: [usbipd-win](https://github.com/dorssel/usbipd-win) ile
  bir USB aygıtını WSL'e bağlayıp yukarıdaki Linux komutlarını
  kullanabilirsiniz.
- **Sanal makineler**: `floppy.img`'yi VirtualBox, VMware, 86Box veya
  PCem'de disket sürücüsü olarak takın.

---

## Özelleştirme

Tüm ayarlar `scripts/common.sh` içinde. Her çalıştırmada ortam
değişkeniyle değiştirilebilir:

| Değişken         | Varsayılan                    | Anlamı |
| ---------------- | ----------------------------- | ------ |
| `KERNEL_VERSION` | en son stable (kernel.org)    | ör. LTS çekirdek için `6.18.57` |
| `BUSYBOX_TAG`    | `1_38_0`                      | BusyBox git etiketi |
| `BB_APPLETS`     | dosyaya bakın                 | açılacak applet'lerin Kconfig adları |
| `CROSS`          | `i686-linux-gnu-`             | kullanıcı alanı derleyici öneki |
| `JOBS`           | `$(nproc)`                    | paralel make işi sayısı |
| `BUILD_DIR`      | `~/floppy-linux-build`        | kaynakların derlendiği yer |
| `MENUCONFIG`     | `0`                           | `1` = 1. ve 2. adımlarda menuconfig'i açar |

Örnek: `free` ve `hexdump` ekleyip yalnızca değişen kısımları yeniden derlemek:

```bash
BB_APPLETS="ASH SH_IS_ASH CAT DATE ECHO LS VI FREE HEXDUMP" bash scripts/02-busybox.sh
bash scripts/03-initramfs.sh && bash scripts/04-floppy.sh
```

> Çekirdek sürümü `~/floppy-linux-build/.kernel-version` dosyasında
> saklanır. Daha yeni bir çekirdeğe geçmek için o dosyayı silin.

## Boyut bütçesi

1.44 MB'lık bir disket 1.474.560 bayt alır. Varsayılan ayarlarla:

| Öğe                                          | Bayt       |
| -------------------------------------------- | ---------- |
| FAT12 boot sektörü, FAT tabloları, kök dizin | ≈ 17 KB    |
| SYSLINUX 6 (`ldlinux.sys` + `ldlinux.c32`)   | ≈ 175 KB   |
| `bzImage` (Linux 7.2.11)                     | 799.232    |
| `init.cpio.lzma` (BusyBox 1.38.0, glibc)     | 470.138    |
| `syslinux.cfg`                               | 301        |
| **Boş**                                      | **8.704**  |

Pay çok dar. Daha yeni bir çekirdek ya da tek bir ek applet sınırı
aşabilir; o zaman `04-floppy.sh` "Disk full" hatasıyla durur. Yer açmak
için sırasıyla şunları deneyin:

1. `BB_APPLETS` listesinden ihtiyacınız olmayan applet'leri çıkarın.
2. `01-kernel.sh` içinden `SERIAL_8250*` seçeneklerini kaldırın (20 KB kazandırır).
3. Daha eski ve küçük bir çekirdek kullanın, ör. `KERNEL_VERSION=6.6.159` (LTS).
4. glibc yerine **musl** kullanın. Burada BusyBox'ın en büyük parçası
   statik glibc; musl ile derleme genellikle çok daha küçük olur. Bunun
   için bir `i686-linux-musl-` derleyici takımı gerekir (ör. musl.cc'den);
   `CROSS=` değişkenini ona yönlendirin.
5. `ldlinux.c32` içermeyen SYSLINUX 4.x'i kullanarak yaklaşık 120 KB kazanın.

## Sorun giderme

| Belirti | Neden / çözüm |
| ------- | ------------- |
| `i686-linux-gnu-gcc: not found` | `bash scripts/00-deps.sh` çalıştırın. |
| `CONFIG_xxx did not stick in .config` | Yeni çekirdek sürümünde o seçeneğin bir bağımlılığı eksik. `MENUCONFIG=1` ile çalıştırın, seçeneği `/` ile bulun ve *Depends on* satırına bakın. |
| `Kernel panic - not syncing: No working init found` | `rdinit=/sh` eksik, initramfs bozuk ya da BusyBox statik/32-bit değil. `file out/busybox` ile kontrol edin. |
| `Initramfs unpacking failed: ...` / `junk in compressed archive` | Çekirdekte `RD_LZMA` yok ya da dosya başka bir biçimle sıkıştırılmış. |
| `Loading init.cpio.lzma... ok` sonrası yanıp sönen imleçte kalıyor | RAM yetersiz. Linux 7.x burada yaklaşık 24 MB istiyor; 16 MB'ta takılıyor. |
| Çekirdek açılıyor ama ekranda hiçbir şey yok | `console=ttyS0` ile açılmış: `floppy` etiketini kullanın ya da `VT_CONSOLE`/`VGA_CONSOLE` seçeneklerini kontrol edin. |
| Açılıştan hemen sonra `Illegal instruction` | İşlemci i686'dan eski. menuconfig'te `M586TSC` seçin *ve* i586 için derlenmiş bir kullanıcı alanı kullanın (ör. musl i586 derleyici takımı). Gerçek i486 makineler için `M486` seçeneği hâlâ bulunan eski bir çekirdek gerekir. |
| `Attempted to kill init` | Kabukta `exit` yazdınız; kabuk PID 1. Yeniden başlatın. |
| Derleme çok yavaş / garip dosya hataları | `/mnt/c` veya `/mnt/d` altında derliyorsunuz. `BUILD_DIR` WSL dosya sisteminde kalmalı. |
| `$'\r': command not found` | Betikler Windows (CRLF) satır sonlarıyla kaydedilmiş. Klonlarken `.gitattributes` bunu önler; mevcut dosyalar için `sed -i 's/\r$//' build.sh scripts/*.sh` çalıştırın. |
| QEMU: `gtk initialization failed` | WSL'de grafik arayüz yok. `bash scripts/05-qemu.sh serial` kullanın. |

## Lisans

Bu depodaki betiklerin lisansını siz seçersiniz (MIT yaygın bir tercih;
bir `LICENSE` dosyası ekleyin). **Linux çekirdeği** ve **BusyBox**
GPL-2.0 lisanslıdır. `floppy.img` veya `bzImage` dosyalarını yayımlarsanız
(ör. bir GitHub Release olarak), GPL ilgili kaynak kodun erişilebilir
olmasını şart koşar. Tam sürümleri belirtin (yukarıda ve
`out/kernel.config` / `out/busybox.config` dosyalarında yazıyor) ve
kernel.org ile busybox.net'e bağlantı verin.

Krzysztof Krystian Jankowski'nin [FLOPPINUX](https://github.com/w84death/floppinux)
projesinden esinlenilmiştir.

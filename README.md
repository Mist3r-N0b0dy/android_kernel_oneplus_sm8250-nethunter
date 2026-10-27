# NetHunter kernel — OnePlus 8T (kebab), crDroid 13.x / Android 17

Fork of [`crdroidandroid/android_kernel_oneplus_sm8250`](https://github.com/crdroidandroid/android_kernel_oneplus_sm8250),
branch `17.0`. The NetHunter work is **ordinary commits on top of upstream**, on
the branch **`nethunter/17.0`** — nothing is carried as a patch series or as
out-of-tree modules: every driver listed below is linked into `vmlinux`.

```bash
git log --oneline upstream/17.0..nethunter/17.0     # 12 commits
git diff upstream/17.0..nethunter/17.0 --stat
```

Two of the twelve are the vendor drop of the external Wi-Fi drivers, kept
**pristine** so the delta stays readable:

```bash
git diff 3907ab4bf..HEAD -- drivers/net/wireless/nethunter/rtl8812au
git diff 178ec22e2..HEAD -- drivers/net/wireless/nethunter/rtl8822bu
```

## Validated

In daily use on a KB2003 (slot `_a`), crDroid 13.x / Android 17, Magisk 31.1.
Last full validation **2026-10-27**:

```
4.19.325-cip135-st19-perf-g66e230426430-Mist3r_N0b0dy  #1 SMP PREEMPT
built with Android clang 12.0.7 (r416183b1), CONFIG_CFI_CLANG + THINLTO
```

| what | how to check on the device | state |
|---|---|---|
| the running kernel is this build | `uname -r`, `/proc/version` | name + `(Mist3r_N0b0dy@nethunter-op8t)` |
| the running config is this tree's | `zcat /proc/config.gz \| grep CONFIG_CC_WERROR` | `=y` (`IKCONFIG`) |
| CFI / LTO enforced | same file, `CFI_CLANG` `CFI_CLANG_SHADOW` `LTO_CLANG` `THINLTO` | all `=y`, `CFI_PERMISSIVE` off |
| 16 USB drivers built in (Wi-Fi, SDR, ethernet) | `ls /sys/bus/usb/drivers` | ath9k_htc, carl9170, dvb_usb_rtl28xxu, mt7601u, mt76x2u, p54usb, r8188eu, rt2500usb, rt2800usb, rtl8150, rtl8187, rtl8192cu, rtl88x2bu, rtl88XXau, rtl8xxxu, zd1211rw |
| p54usb + NCI core | `grep -w p54u_driver /proc/kallsyms`, then `nci_register_device` | both present |
| CAN stack | `ip link add dev vcan0 type vcan` | works |
| USB gadget + HID | `mount -t configfs configfs /sys/kernel/config` then `mkdir …/usb_gadget/g/functions/hid.usb0` | works |
| NFC | `/dev/nq-nci` | present, chip driver `NFC_NQ` |
| netfilter | `iptables -L -n` | chains in place |
| zero-module policy | `wc -l < /proc/modules` | 0 |

Not validated — needs hardware that was not plugged in: monitor mode and frame
injection, Bluetooth, GS_USB, SDR (RTL28xxU), USB-UAS, USB-serial.

## Install

The first public release is **v1.0.0** (2026-10-27). After that, one tag per
crDroid build: a zip only matches the ROM build it was built against.

Requirements: a kebab (OnePlus 8T) on crDroid 13.x / Android 17, and the zip
built or published for **that** crDroid build. The installer patches the
**active slot only**; the other slot keeps whatever it had.

```bash
# 1. keep a way back (in the recovery, which is root):
adb exec-out dd if=/dev/block/by-name/boot_a > boot_a-backup.img

# 2. flash
adb reboot recovery            # Apply update > Apply from ADB
adb sideload NetHunter-Kernel-<release>-kebab-AnyKernel3.zip

# 3. verify after the reboot
uname -r                       # 4.19.325-…-Mist3r_N0b0dy
zcat /proc/config.gz | grep CONFIG_NFC_NCI
```

The recovery log prints the banner and the release details *after* `write_boot`,
so `Done!` lands just below them and the art stays in the log.

**Flashing from the Magisk app does not work, on purpose.** The zip is an
AnyKernel3 kernel, not a Magisk module: Magisk writes a boot image
all-or-nothing and cannot hand it over to the installer. The zip carries a
`module.prop` so that Magisk runs `customize.sh` instead of answering
"This is not a Magisk module", and that script prints the same banner, the same
details, and says to use the recovery. Nothing is installed in that case.

To go back: `fastboot flash boot boot_a-backup.img` (or write the image back
with `dd` from the recovery).

## Build

The tree is **not** built on the phone: it needs an x86_64 host with an LLVM
toolchain for arm64 (Android clang r416183b1 / 12.0.7 or newer), ~16 GB free
and `bison`, `flex`, `bc`, `libssl-dev`, `libelf-dev`, `zip`, `unzip`.

```bash
git clone https://github.com/Mist3r-N0b0dy/android_kernel_oneplus_sm8250-nethunter
cd android_kernel_oneplus_sm8250-nethunter
CLANG_DIR=/path/to/clang/bin ./build.sh
# -> dist/NetHunter-Kernel-<kernel.release>-kebab-AnyKernel3.zip
```

`build.sh` checks the toolchain, merges the three config files, verifies what a
wrong compiler silently drops (`CFI_CLANG`, `LTO_CLANG`, `THINLTO`, the release
string, zero modules) *before* compiling, builds `Image`, then calls
`packaging/build-zip.sh`, which fetches the AnyKernel3 installer once into
`~/.cache/nethunter/AnyKernel3` (outside the tree, pinned by commit).
`--no-zip` stops after the image.

The config is `arch/arm64/configs/nethunter.fragment`, merged on top of
`vendor/kona-perf_defconfig` + `vendor/oplus.config` (both are required: without
`oplus.config`, `schgm-flash.c` fails on an incomplete `struct smb_charger`). A
fragment rather than a saved defconfig, because `CFI_CLANG`, `LTO_CLANG` and
`THINLTO` are decided by the build host's compiler and a defconfig generated
elsewhere loses them without a word. The release string lives there too
(`CONFIG_LOCALVERSION`), so a clone names its kernel by itself.

-Werror is **on** (`CONFIG_CC_WERROR=y`): a warning is a hard error, including
on every line this fork wrote. The only exceptions are four named diagnostic
classes inside the two third-party driver trees, downgraded with `-Wno-error=`
in their own Makefiles. They keep printing — 500 of them, all in vendor code.

## What the commits are for

| Commit | Problem it removes |
|---|---|
| `wireless: build both vendored drivers in-tree` | `-I$(src)/` resolves to `out/…` with `O=out`; 2625 globals duplicated by the two drivers; a macro that overrides a rename |
| `rtl8812au: compile with clang 12 and satisfy CFI` | the aircrack-ng tree assumes a newer toolchain: 31 tasklets declared `void (*)(void *)` where the kernel imposes `void (*)(unsigned long)`, and `rtw_xmit_entry` returning `int` instead of `netdev_tx_t` — invisible to the compiler, fatal to CFI (panic on the first TX) |
| `rtl8822bu: compile with clang 12 and satisfy CFI` | same two classes for the morrownr tree: 51 tasklets, 3 xmit callbacks |
| `vendored drivers: rename the globals two copies share` | as modules their generic globals were alone; in one `vmlinux` the `htc_*` helpers collide with the other `ath` drivers, and `char *ifname = "wlan%d"` is defined by both Realtek drivers (`ld.lld: duplicate symbol: ifname`) |
| `r8188eu: allow CONFIG_R8188EU=y` | its Kconfig had `depends on m`, so `=y` was discarded in silence and the whole `LIB80211` chain stayed modular |
| `nfs: make the client build and link on this vendor tree` | the LineageOS backport keeps the pre-5.0 `readpage_async_filler()` signature, and a sunrpc callback declaration no longer matches its definition once the options are built in |
| `usb: storage: uas: force BOT on the RTL9210` | bridges that advertise UAS and break on the first command queue |

## Following crDroid

```bash
git fetch upstream 17.0
git rebase upstream/17.0          # conflicts here are the whole point
```

If a commit no longer applies because upstream fixed it, **drop it** — the
series is not a museum. Then rebuild, re-validate, and tag one release per
crDroid build.

## Related

- [Boot animation](https://github.com/Mist3r-N0b0dy/Bootanimation-OP8T-Magisk-Module-A17):
  the animation with sound, packaged as a Magisk module independent of this
  kernel.
- Build logs, test matrices and the discarded drafts are **not** here. They are
  our notes, and they stay on our own machines.

# NetHunter kernel — OnePlus 8T (kebab), crDroid 13.x / Android 17

Fork of [`crdroidandroid/android_kernel_oneplus_sm8250`](https://github.com/crdroidandroid/android_kernel_oneplus_sm8250),
branch `17.0`. The NetHunter work is **ordinary commits on top of upstream**,
on the branch **`nethunter/17.0`** — no patch series, no out-of-tree modules:
everything below is linked into `vmlinux`.

```bash
git log --oneline upstream/17.0..nethunter/17.0    # each message says what it fixes
```

Two of those commits are the vendor drop of the external Wi-Fi drivers
(rtl8812au, rtl8822bu), kept **pristine** so the delta stays readable.

## Validated

Daily use on a KB2003 (slot `_a`), crDroid 13.x / Android 17, Magisk 31.1.
Last full validation **2026-10-28**:

```
4.19.325-cip135-st19-perf-g66e230426430-Mist3r_N0b0dy  #1 SMP PREEMPT
Android clang 12.0.7 (r416183b1), CONFIG_CFI_CLANG + THINLTO, CC_WERROR=y
```

| what | how to check on the device | state |
|---|---|---|
| CFI / LTO enforced | `zcat /proc/config.gz \| grep -E 'CFI_CLANG\|THINLTO'` | all `=y`, `CFI_PERMISSIVE` off |
| zero modules | `wc -l < /proc/modules` | 0 |
| 16 USB drivers built in | `ls /sys/bus/usb/drivers` | ath9k_htc, carl9170, dvb_usb_rtl28xxu, mt7601u, mt76x2u, p54usb, r8188eu, rtl8150, rtl8187, rtl8192cu, rtl88x2bu, rtl88XXau, rtl8xxxu, rt2500usb, rt2800usb, zd1211rw |
| monitor mode, internal chip | `echo 4 > /sys/module/wlan/parameters/con_mode` | `wlan0` turns `type monitor` |
| monitor channel hopping | `airodump-ng --band bg wlan0` (no `-c`), 50 s | 5 channels / 33 BSS, no wedged vdev |
| injection, internal chip | `aireplay-ng --test -D wlan0` | 30/30 = 100 %, `Injection is working!` |
| injection, RTL8812AU / RTL8822BU | same, on `rtl88XXau` / `rtl88x2bu` | 25/30 = 83 % / 24/30 = 80 % |
| CAN stack | `ip link add dev vcan0 type vcan` | works |
| NFC, p54usb | `/dev/nq-nci`; `grep -w p54u_driver /proc/kallsyms` | both present |
| USB gadget + HID | configfs `…/usb_gadget/g/functions/hid.usb0` | works |
| Docker networking | `zcat /proc/config.gz \| grep CONFIG_IPVLAN` | `=y` |

Not validated — nothing plugged in: Bluetooth, GS_USB, SDR (RTL28xxU),
USB-UAS, USB-serial. ATH6KL and MWIFIEX build in, but this ROM ships no
firmware for them.

## Monitor mode and frame injection

`echo 4 > /sys/module/wlan/parameters/con_mode` brings `wlan0` up as
`type monitor`, `echo 0 >` gives it back to Android. Three things stood in the
way, all fixed here:

- **the vdev could not hop.** `MAC0` is single-band, so `wma_is_dbs_mandatory()`
  forces SMM -> DBS before any monitor vdev starts, and the psoc restart keeps
  the pdev busy for seconds; a channel change in that window is refused by the
  firmware, and that refusal used to wedge the vdev for the whole session —
  Android's Wi-Fi then only came back on reboot. The mode change now happens
  once per session, a hop is only asked of a vdev in `INIT`/`UP`, and a refusal
  is reported as the end of the restart it sits in, not as `START_REQ_FAIL`.
- **quiet time between hops.** Measured with airodump-ng: 1 s crashes the
  phone, 2 s holds, 3 s and 6 s scan no faster. 2 s ships, so a full
  13-channel sweep takes ~30 s.
- **`iwconfig mode monitor` tripped CFI.** `cfg80211_wext_siwmode()` and
  `giwmode()` took a `u32 *` behind an `(iw_handler)` cast; they now take a
  `union iwreq_data *`, like the rest of wext.

Injection expects a **bare 802.11 frame** (no radiotap): the TX path drops
anything whose `fc_type` is not management.

## Install

**v1.1.0** (2026-10-28) adds monitor mode and injection on the internal chip;
**v1.0.0** (2026-10-27) was the first release. Zips are in
[Releases](../../releases) — one per crDroid build, because a zip only matches
the ROM build it was built against. The installer patches the **active slot
only**, the other one keeps whatever it had.

```bash
# 1. a way back, from the recovery (root):
adb exec-out dd if=/dev/block/by-name/boot_a > boot_a-backup.img

# 2. flash
adb reboot recovery            # Apply update > Apply from ADB
adb sideload NetHunter-Kernel-<release>-kebab-AnyKernel3.zip

# 3. verify after the reboot
uname -r                       # 4.19.325-…-Mist3r_N0b0dy
```

**The Magisk app cannot flash this**, on purpose: it is an AnyKernel3 kernel,
not a module. The zip carries a `module.prop` only so that Magisk runs
`customize.sh` and says to use the recovery; nothing is installed that way.
To go back: `fastboot flash boot boot_a-backup.img`.

## Build

Not on the phone: an x86_64 host, an arm64 LLVM toolchain (Android clang
r416183b1 / 12.0.7 or newer), ~16 GB free, `bison flex bc libssl-dev
libelf-dev zip unzip`.

```bash
git clone https://github.com/Mist3r-N0b0dy/android_kernel_oneplus_sm8250-nethunter
cd android_kernel_oneplus_sm8250-nethunter
CLANG_DIR=/path/to/clang/bin ./build.sh
# -> dist/NetHunter-Kernel-<kernel.release>-kebab-AnyKernel3.zip
```

`build.sh` checks the toolchain, merges `vendor/kona-perf_defconfig` +
`vendor/oplus.config` + `arch/arm64/configs/nethunter.fragment`, verifies what
a wrong compiler drops in silence (`CFI_CLANG`, `LTO_CLANG`, `THINLTO`, the
release string, zero modules) **before** compiling, builds `Image`, then calls
`packaging/build-zip.sh`. `--no-zip` stops after the image.

The config is a fragment rather than a defconfig because `CFI_CLANG`,
`LTO_CLANG` and `THINLTO` are decided by the build host's compiler; the release
string (`CONFIG_LOCALVERSION`) lives there too, so a clone names its own
kernel. `-Werror` is on: a warning is a hard error, including on lines this
fork wrote.

## Following crDroid

```bash
git fetch upstream 17.0
git rebase upstream/17.0          # conflicts here are the whole point
```

If a commit no longer applies because upstream fixed it, **drop it** — the
series is not a museum. Then rebuild, re-validate, and tag one release per
crDroid build.

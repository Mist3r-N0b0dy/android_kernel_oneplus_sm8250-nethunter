#!/bin/sh
# Build the flashable AnyKernel3 zip from a tree that has already been built.
#
#   ./packaging/build-zip.sh                 # uses out/ and dist/
#   AK3=/path/to/AnyKernel3 ./packaging/build-zip.sh
#
# What it does NOT do: compile. The kernel image must already exist at
# out/arch/arm64/boot/Image, produced from this tree with this tree's
# arch/arm64/configs/nethunter.fragment. One tree, one image, one release
# string: the name of the zip, the banner in the recovery log and `uname -r`
# all read the same out/include/config/kernel.release.
#
# AK3 is a checkout of AnyKernel3 (https://github.com/osm0sis/AnyKernel3). It
# is not vendored here: it is ~4 Mio of third-party binaries (busybox,
# magiskboot, ...) that have no business in a kernel fork. It is fetched once,
# automatically, into a cache outside the tree; override with AK3=<dir>.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(dirname "$HERE")
OUT="${OUT:-$TREE/out}"
DIST="${DIST:-$TREE/dist}"
AK3="${AK3:-${XDG_CACHE_HOME:-$HOME/.cache}/nethunter/AnyKernel3}"
AK3_REPO="${AK3_REPO:-https://github.com/osm0sis/AnyKernel3.git}"
# PINNED, and it matters. The installer is part of the release: it gets a
# version, it does not follow upstream blindly.
#
# c072981 = "tools: update magisk utils to v31.1(31100) beta", 2026-10-25. It
# matches the Magisk the phone runs, and its ak3-core.sh is byte-identical to
# the v31.0 one this fork flashed successfully -- only the three binaries and a
# version string change. Verified against this device's own boot_a with
# magiskboot v31.1: unpack ok, repack ok (same header, same KERNEL_SZ/DTB_SZ).
#
# NOT master. bb45b02 ("AK3: signing updates/fixes with latest magiskboot",
# 2026-10-26) replaced the split_boot status handling with
#     [ $? == 1 ] && splitfail=1;
# and that line leaks its own exit status into the `if [ $? != 0 ]` that
# follows: when magiskboot unpack SUCCEEDS, `[ 0 == 1 ]` returns 1 and the next
# test reads it as a failure. Every flash aborts with "Splitting image failed."
# Reproduced on this device's boot_a: master aborts, c072981 does not. That
# was the first attempt at this release, not Magisk 30.7 vs 31.1.
#
# Before bumping: re-run that split test, and remember `magiskboot sign` was
# renamed to `sign-avb1` in v31.1 -- harmless here (this boot image does not
# verify as AVB-signed, so ak3 never signs it), fatal on a device that does.
AK3_REF="${AK3_REF:-c072981836cd3ee46ad52a5f2cba76ecb927cb1b}"

die() { echo "build-zip: $*" >&2; exit 1; }

# zip runs from the staging directory, so every path must be absolute.
for v in OUT DIST AK3; do
  eval "p=\$$v"
  case "$p" in /*) ;; *) eval "$v=\"\$PWD/\$p\"" ;; esac
done

# ------------------------------- checks -------------------------------------
IMG="$OUT/arch/arm64/boot/Image"
KREL="$OUT/include/config/kernel.release"
[ -f "$IMG" ]  || die "no image at $IMG -- build first (see README.md)"
[ -f "$KREL" ] || die "no $KREL -- build first (see README.md)"
if [ ! -f "$AK3/tools/ak3-core.sh" ] ||
   [ "$(cat "$AK3/.ak3-ref" 2>/dev/null)" != "$AK3_REF" ]; then
  command -v git >/dev/null 2>&1 ||
    die "no AnyKernel3 at $AK3, and no git to fetch it"
  echo "build-zip: fetching AnyKernel3 $AK3_REF into $AK3" >&2
  mkdir -p "$AK3"
  ( cd "$AK3"
    [ -d .git ] || git init -q .
    git remote add origin "$AK3_REPO" 2>/dev/null ||
      git remote set-url origin "$AK3_REPO"
    git fetch -q --depth 1 origin "$AK3_REF" &&
      git checkout -q -f --detach FETCH_HEAD &&
      printf '%s\n' "$AK3_REF" > .ak3-ref
  ) 2>/dev/null ||
    die "could not fetch $AK3_REPO at $AK3_REF -- pass AK3=<checkout> for a local one"
fi
# The installer travels with the release, so its version belongs in the log
# next to the kernel's: when a flash fails, that is the first thing to compare.
AK3_VER=$(cd "$AK3" && git log -1 --format='%h %s' 2>/dev/null | cut -c1-40 || echo unknown)

REL=$(cat "$KREL")
case "$REL" in
  *-g*) V1="${REL%%-g*}"; V2="-g${REL#*-g}" ;;
  *)    V1="$REL";        V2="" ;;
esac
HASH=$(printf '%s\n' "$V2" | sed -n 's/^-g\([0-9a-f]\{12\}\).*/\1/p')
KO=$(find "$OUT" -name '*.ko' | wc -l)

# ------------------------------- details ------------------------------------
# Printed by the recovery banner (packaging/anykernel.sh) and by the Magisk
# notice (packaging/customize.sh). Lines stay under ~40 columns: the crDroid
# recovery console is narrow and wraps anything longer.
mkdir -p "$DIST"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

{
  echo "NetHunter kernel - OnePlus 8T (kebab)"
  echo "release  $V1"
  [ -n "$V2" ] && echo "         $V2"
  echo "base     crDroid 13.x / Android 17"
  [ -n "$HASH" ] && echo "         upstream $HASH"
  echo "drivers  88XXau rtl8822bu p54usb r8188eu, all =y"
  if [ "$KO" -eq 0 ]; then
    echo "modules  0 - nothing to insmod"
  else
    echo "modules  $KO .ko -- zero-module check FAILED"
  fi
  echo "installer AnyKernel3 ${AK3_REF%????????????????????????}"
  echo "built    $(date -u '+%Y-%m-%d %H:%M UTC')"
} > "$WORK/nh-details.txt"

# ------------------------------- assemble -----------------------------------
# Copy, never zip in place: zipping a directory that already holds an archive
# merges with it and silently ships the previous Image.
cp -a "$AK3"/. "$WORK"/
rm -f "$WORK/.ak3-ref"   # our own marker in the cache checkout, not part of the release
cp "$IMG" "$WORK/Image"
cp "$HERE/anykernel.sh" "$WORK/anykernel.sh"
cp "$HERE/customize.sh" "$WORK/customize.sh"
chmod 755 "$WORK/customize.sh"

# Magisk reads module.prop before anything else. Without it the answer is a
# bare "This is not a Magisk module" and the user learns nothing; with it,
# customize.sh runs and explains. A recovery flash never looks at either file.
cat > "$WORK/module.prop" <<EOF
id=nethunter-kernel-notice
name=NetHunter Kernel (recovery only)
version=$REL
versionCode=1
author=Mist3r_N0b0dy
description=AnyKernel3 kernel image, not a Magisk module. Flash it in the recovery over adb (adb sideload); this install only tells you that.
EOF

ZIP="$DIST/NetHunter-Kernel-$REL-kebab-AnyKernel3.zip"
rm -f "$ZIP"
( cd "$WORK" && zip -q -r9 "$ZIP" . -x '*.git*' -x 'README.md' -x 'patch/*' )

# ------------------------------- verify -------------------------------------
unzip -l "$ZIP" | grep -q ' Image$'     || die "no Image in the zip"
unzip -l "$ZIP" | grep -q ' anykernel.sh$' || die "no anykernel.sh in the zip"
unzip -l "$ZIP" | grep -q ' nh-details.txt$' || die "no nh-details.txt in the zip"
if [ "$(unzip -l "$ZIP" | grep -c '\.ko$')" -ne 0 ]; then
  die "the zip carries .ko files -- zero-module policy broken"
fi

echo "$ZIP"
ls -l "$ZIP" | awk '{print "  size   " $5 " bytes"}'
echo "  sha256 $(sha256sum "$ZIP" | cut -d" " -f1)"
echo "  installer  AnyKernel3 ${AK3_REF}"
echo "             $AK3_VER"
echo "  --- what the log will say ---"
sed 's/^/  /' "$WORK/nh-details.txt"

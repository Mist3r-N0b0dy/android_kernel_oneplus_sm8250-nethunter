#!/usr/bin/env bash
# =============================================================================
#  build.sh — NetHunter kernel for OnePlus 8T (kebab), crDroid 13.x / Android 17
#
#  One command, from a plain clone to the flashable zip:
#
#      ./build.sh
#
#  Everything it needs is either in this tree (vendor/kona-perf_defconfig,
#  vendor/oplus.config, arch/arm64/configs/nethunter.fragment, packaging/) or
#  is a tool it names explicitly when it is missing. The AnyKernel3 installer
#  is fetched once into a cache OUTSIDE the tree, so a build never leaves
#  untracked files behind.
#
#      ./build.sh --no-zip     # stop after out/arch/arm64/boot/Image
#      ./build.sh -j 4         # override the job count
#      CLANG_DIR=/opt/clang/bin ./build.sh
#
#  Requires: x86_64 Linux host, an arm64 LLVM toolchain (Android clang
#  r416183b1 / 12.0.7 or newer), bison, flex, bc, rsync, python3, zip, unzip,
#  and the openssl + libelf development headers. ~16 GB of disk.
#
#  NOT built on the device: this tree needs a real host.
# =============================================================================
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"

JOBS=${JOBS:-$(nproc)}
OUT=${OUT:-out}
DIST=${DIST:-dist}
CLANG_DIR=${CLANG_DIR:-}
AK3=${AK3:-}
DO_ZIP=1
TARGETS=(Image)

# ------------------------------- arguments -----------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --no-zip)   DO_ZIP=0 ;;
    -j|--jobs)  JOBS="$2"; shift ;;
    -h|--help)  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "build.sh: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# The builder stamp in /proc/version: "Linux version ... (user@host) #1 SMP
# PREEMPT <date>". NOT part of the vermagic (unlike CONFIG_LOCALVERSION), so it
# never invalidates a module -- but it is the line a user sees in `uname -a`,
# and "agent@<container>" says nothing about what they just flashed.
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-Mist3r_N0b0dy}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-nethunter-op8t}"

# ...and the release string must not depend on HOW the tree was obtained.
# scripts/setlocalversion appends "+" whenever HEAD is not an exact tag match,
# which is always true here: we carry commits on top of a crDroid merge and we
# do not tag the tree before building. Building the same tree from a tarball
# (not a git repo) or from a clone would then produce two different releases,
# "-Mist3r_N0b0dy" and "-Mist3r_N0b0dy+", with two different vermagics. Setting
# LOCALVERSION -- even to an empty string -- is the switch the script honours to
# skip the scm suffix entirely, so the release is a property of the fragment
# alone. Reproduced on the build host: a plain `make kernelrelease` in a clone
# gives "...-Mist3r_N0b0dy+", this build gives "...-Mist3r_N0b0dy".
export LOCALVERSION=

say()  { printf '\n=== %s\n' "$*"; }
warn() { printf '  !! %s\n' "$*" >&2; }
die()  { printf '\nbuild.sh: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------- 0. the tree ---------------------------------
[ -f Makefile ] || die "run this from the kernel tree (no Makefile here)"
[ -f arch/arm64/configs/nethunter.fragment ] ||
  die "arch/arm64/configs/nethunter.fragment is missing -- wrong tree?"
[ -f packaging/build-zip.sh ] ||
  die "packaging/build-zip.sh is missing -- wrong tree?"

# ------------------------------- 1. toolchain --------------------------------
say "1/6 toolchain"

if [ -n "$CLANG_DIR" ]; then
  export PATH="$CLANG_DIR:$PATH"
elif ! have clang && [ -d "$HOME/clang/bin" ]; then
  export PATH="$HOME/clang/bin:$PATH"
fi

missing=()
have clang     || missing+=("clang (Android prebuilt r416183b1 or newer)")
have ld.lld    || missing+=("ld.lld (ships with the clang prebuilt)")
have bison     || missing+=("bison")
have flex      || missing+=("flex")
have bc        || missing+=("bc")
have rsync     || missing+=("rsync")
have python3   || missing+=("python3")
[ -f /usr/include/openssl/bio.h ] || missing+=("libssl-dev")
[ -f /usr/include/libelf.h ]      || missing+=("libelf-dev")
if [ "$DO_ZIP" -eq 1 ]; then
  have zip   || missing+=("zip")
  have unzip || missing+=("unzip")
fi
if [ ${#missing[@]} -gt 0 ]; then
  warn "missing: ${missing[*]}"
  cat >&2 <<'EOF'
  Debian/Ubuntu:  sudo apt-get install -y build-essential bc bison flex \
                    libssl-dev libelf-dev rsync python3 zip unzip
  clang prebuilt: curl -L -o clang.tar.gz \
                    https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-release/clang-r416183b1.tar.gz \
                  && mkdir -p ~/clang && tar xzf clang.tar.gz -C ~/clang \
                  && export PATH=$HOME/clang/bin:$PATH
EOF
  die "install the missing pieces and run again"
fi

clang_v=$(clang --version | head -1)
clang_major=$(clang --version | sed -n 's/.*clang version \([0-9]\+\).*/\1/p' | head -1)
echo "  clang      $clang_v"
echo "  ld.lld     $(ld.lld --version | head -1)"
echo "  builder    $KBUILD_BUILD_USER@$KBUILD_BUILD_HOST (/proc/version)"
# CFI_CLANG/LTO_CLANG/THINLTO are decided by this compiler and nothing else --
# a savedefconfig generated with gcc silently loses them, which is why the
# fragment is the source of truth and why the version is printed here.
[ -n "$clang_major" ] && [ "$clang_major" -ge 12 ] 2>/dev/null ||
  die "clang $clang_major is too old: this tree needs 12 or newer for CFI + LTO"
echo "  jobs       $JOBS"

# ------------------------------- 2. config -----------------------------------
say "2/6 configuration ($OUT/.config)"
export ARCH=arm64 SUBARCH=arm64
mkdir -p "$OUT"

# Three files, always together and always in this order. kona-perf_defconfig
# alone yields 1901 options instead of 1951 and the build then fails in
# schgm-flash.c on an incomplete struct smb_charger, because
# -DOPLUS_FEATURE_CHG_BASIC is injected for that file. The fragment carries
# what the defconfig cannot: CFI/LTO knobs that depend on the host compiler,
# the release string, and '# CONFIG_LOCALVERSION_AUTO is not set'.
# EXTRA_CONFIG is for debugging builds only: an extra kconfig fragment merged
# LAST, so it wins over the fragment. Used to build a CFI-permissive kernel --
# with CONFIG_CFI_PERMISSIVE=y a CFI violation is logged and the kernel keeps
# running, which is the only way to learn which function trap when the strict
# kernel freezes before it can write anything down.
configs=(arch/arm64/configs/vendor/kona-perf_defconfig
         arch/arm64/configs/vendor/oplus.config
         arch/arm64/configs/nethunter.fragment)
if [ -n "${EXTRA_CONFIG:-}" ]; then
  [ -f "$EXTRA_CONFIG" ] || die "EXTRA_CONFIG=$EXTRA_CONFIG: no such file"
  configs+=("$EXTRA_CONFIG")
  echo "  extra      $EXTRA_CONFIG"
fi
scripts/kconfig/merge_config.sh -m -O "$OUT" "${configs[@]}" > "$OUT/merge_config.log" 2>&1 ||
  { tail -20 "$OUT/merge_config.log" >&2; die "merge_config failed"; }
make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig > "$OUT/olddefconfig.log" 2>&1 ||
  { tail -20 "$OUT/olddefconfig.log" >&2; die "olddefconfig failed"; }

# ------------------------------- 3. checks -----------------------------------
# Before the 8-minute build, not after: every one of these has already cost a
# full rebuild once.
say "3/6 configuration checks"
cfg="$OUT/.config"
for opt in CONFIG_CFI_CLANG CONFIG_CFI_CLANG_SHADOW CONFIG_LTO_CLANG CONFIG_THINLTO \
           CONFIG_88XXAU CONFIG_RTL8822BU CONFIG_P54_USB CONFIG_NFC_NCI \
           CONFIG_ATH6KL_USB CONFIG_MWIFIEX_USB; do
  grep -qE "^$opt=y" "$cfg" && echo "  $opt=y" ||
    die "$opt is not =y in $cfg -- wrong compiler? see the fragment's comment"
done
grep -q '^# CONFIG_CFI_PERMISSIVE is not set' "$cfg" &&
  echo "  CFI_PERMISSIVE off (enforcing)" || warn "CONFIG_CFI_PERMISSIVE not explicitly off"
# -Werror is on for the whole tree; only four named diagnostic classes in the
# two vendored driver trees are downgraded, in their own Makefiles. If this
# ever reads 'not set', a fragment/vendor merge went wrong and warnings are
# being ignored without anyone noticing -- which is the point of the check.
grep -q '^CONFIG_CC_WERROR=y' "$cfg" &&
  echo "  CC_WERROR on (warnings are errors, except in the vendored drivers)" ||
  die "CONFIG_CC_WERROR is off in $cfg -- warnings would pass silently"

mods=$(grep -c '=m$' "$cfg" || true)
[ "$mods" -eq 0 ] && echo "  modules   0 (zero-module policy held)" ||
  die "$mods option(s) =m in $cfg -- the release must be module-free:
  $(grep '=m$' "$cfg" | head -5)"

rel=$(make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 -s kernelrelease)
echo "  release   $rel"
case "$rel" in
  *-Mist3r_N0b0dy) echo "  pseudo    in the release string and in the vermagic" ;;
  *) die "unexpected release '$rel' -- CONFIG_LOCALVERSION in the fragment?" ;;
esac

# ------------------------------- 4. build ------------------------------------
say "4/6 build (-j$JOBS)"
time make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$JOBS" "${TARGETS[@]}"
# 'find: arch/arm64/boot/dts/: No such file or directory' is expected and
# harmless: this vendor tree ships no device trees.

# ------------------------------- 5. verify -----------------------------------
say "5/6 image"
img="$OUT/arch/arm64/boot/Image"
[ -f "$img" ] || die "no image at $img"
rel_after=$(cat "$OUT/include/config/kernel.release")
[ "$rel_after" = "$rel" ] || die "kernel.release moved during the build ($rel -> $rel_after)"
echo "  $img"
echo "  size      $(stat -c %s "$img") bytes"
echo "  sha256    $(sha256sum "$img" | cut -d' ' -f1)"
echo "  release   $rel_after"
echo "  modules   $(find "$OUT" -name '*.ko' | wc -l) .ko in the tree"

# ------------------------------- 6. zip --------------------------------------
if [ "$DO_ZIP" -eq 0 ]; then
  say "6/6 zip skipped (--no-zip)"
  exit 0
fi
say "6/6 flashable zip"
# "bash", not "./": the scripts are committed 0644 so that a clone can be
# built anywhere, /sdcard included (mounted noexec on this device). Calling
# them with ./ would fail with EACCES on the very first run.
OUT="$OUT" DIST="$DIST" AK3="$AK3" bash "$HERE/packaging/build-zip.sh"

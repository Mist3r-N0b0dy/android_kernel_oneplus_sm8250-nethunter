### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers - configured for OnePlus 8T (kebab)
## NetHunter fork: the banner and the details block at the end are ours; the
## patching logic is upstream AnyKernel3 and is not modified.

### AnyKernel setup
properties() { '
kernel.string=NetHunter 4.19.325 (kebab / OnePlus 8T) - crDroid 13.x
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=kebab
device.name2=OnePlus8T
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
} # end attributes

# boot shell variables
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot;
write_boot;

# Signature. Printed last on purpose: update-binary prints "Done!" as soon as
# this script returns, so the art lands immediately above the success line and
# stays visible in `adb sideload` output and in the recovery log.
# This is the compact face: 41 columns, which fits the crDroid recovery
# console. The wide 67-column face needs more room than that console has and
# wraps there; it lives in the README instead.
# 7-bit ASCII only, no backslash and no quote, so ui_print "..." needs nothing
# escaped and every leading space survives.
ui_print "#    #  ###    ####  ######  ####  #####"
ui_print "##  ##   #    #    #   ##   #    # #    #"
ui_print "# ## #   #    #        ##        # #    #"
ui_print "#    #   #     ####    ##     ###  #####"
ui_print "#    #   #         #   ##        # #  #"
ui_print "#    #   #    #    #   ##        # #   #"
ui_print "#    #  ###    ####    ##    ####  #    #"
ui_print " "
ui_print "#    #  ####  #####   ####  #####  #    #"
ui_print "##   # #    # #    # #    # #    # #    #"
ui_print "# #  # #   ## #    # #   ## #    # #    #"
ui_print "#  # # #  # # #####  #  # # #    #  #  #"
ui_print "#   ## # #  # #    # # #  # #    #   ##"
ui_print "#    # ##   # #    # ##   # #    #   ##"
ui_print "#    #  ####  #####   ####  #####    ##"
ui_print " "

# What is being flashed, in the log, at the moment it is flashed.
# nh-details.txt is written at packaging time by packaging/build-zip.sh, from
# out/include/config/kernel.release: the release string in the log is the one
# the kernel will report in `uname -r`, not a copy typed by hand somewhere.
# Each line is kept under ~40 columns because the recovery console is narrow.
if [ -f nh-details.txt ]; then
  while IFS= read -r nh_line; do
    ui_print "  $nh_line"
  done < nh-details.txt
else
  ui_print "  NetHunter kernel - OnePlus 8T (kebab)"
fi
ui_print "  Reboot to apply."
## end boot install

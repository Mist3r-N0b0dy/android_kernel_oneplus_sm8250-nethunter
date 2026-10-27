#!/sbin/sh
# ONLY Magisk runs this file. A recovery flash goes through
# META-INF/com/google/android/update-binary -> anykernel.sh and never looks
# here. module.prop exists for one reason: without it Magisk answers
# "This is not a Magisk module" and stops, leaving the user with no
# explanation at all. This script explains, then aborts: nothing is installed.

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

# Same details block as the recovery banner: one file, written at packaging
# time, so Magisk and the recovery never say different things.
if [ -f nh-details.txt ]; then
  while IFS= read -r nh_line; do
    ui_print "  $nh_line"
  done < nh-details.txt
  ui_print " "
fi

ui_print "- This zip is an AnyKernel3 kernel,"
ui_print "- NOT a Magisk module: Magisk cannot"
ui_print "- write a boot image (all-or-nothing)."
ui_print "- Flash it in recovery, over adb:"
ui_print "    adb reboot recovery"
ui_print "    Apply update > Apply from ADB"
ui_print "    adb sideload NetHunter-Kernel-*.zip"
ui_print " "
# customize.sh is sourced by the Magisk installer, so abort() normally
# exists. If it ever does not, a non-zero exit still fails the install.
if command -v abort >/dev/null 2>&1; then
  abort "- Nothing was installed."
fi
ui_print "- Nothing was installed."
exit 1

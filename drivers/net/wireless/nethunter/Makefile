# v1.6 -- see Kconfig. CONFIG_88XXAU and CONFIG_RTL8822BU are declared there
# with the exact names the two vendor Makefiles expect, so each subdirectory
# keeps its own Makefile untouched and simply resolves to obj-y.
obj-$(CONFIG_88XXAU)   += rtl8812au/
obj-$(CONFIG_RTL8822BU) += rtl8822bu/

# -Werror is ON for the whole tree (CONFIG_CC_WERROR=y). These two directories
# are third-party code we do not maintain, and they cannot be made warning-free:
# 490 unused-variable and 2 parentheses-equality warnings, all of the form the
# vendor shipped them in. Only those two classes are downgraded, and only here;
# anything else -- a new warning on a line we patched included -- still fails
# the build.
subdir-ccflags-y += -Wno-error=unused-variable
subdir-ccflags-y += -Wno-error=parentheses-equality

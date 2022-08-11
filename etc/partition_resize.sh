#!/bin/ash

echo "trying to expand rootfs partition"
/bin/parted -s -a optimal /dev/mmcblk1 -- rm 3                                  # remove swap partition once
/bin/parted -s -a optimal /dev/mmcblk1 -- mkpart Linux_Swap linux-swap -1080 -1 # make 1GB swap partition at end of SD
/bin/parted -s -a optimal /dev/mmcblk1 -- resizepart 2 -1081                    # expand rootfs to before swap partition

echo "make swap on /dev/mmcblk1p3"
/sbin/mkswap /dev/mmcblk1p3
sync

echo "wait 5sec"
sleep 5

reboot &
exec /sbin/orig/init

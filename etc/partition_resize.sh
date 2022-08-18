#!/bin/ash

echo "trying to expand rootfs partition"
/bin/parted -s -a optimal /dev/mmcblk1 -- rm 3                               # remove swap partition once
/bin/parted -s -a optimal /dev/mmcblk1 -- mkpart primary linux-swap -1080 -1 # make 1GB swap partition at end of SD
/bin/parted -s -a optimal /dev/mmcblk1 -- resizepart 2 -1081                 # expand rootfs to before swap partition
/bin/e2fsck -f /dev/mmcblk1p2
/bin/resize2fs /dev/mmcblk1p2

echo "make swap on /dev/mmcblk1p3"
/sbin/mkswap /dev/mmcblk1p3
sync

echo "wait 3sec"
sleep 3

echo "reboot"
reboot &

exec /sbin/orig/init

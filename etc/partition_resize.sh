#!/bin/sh

if [ ! "${USER}" = "root" ]; then
    echo "This script need to do with sudo or root account."
    exit 1
fi

swapoff /dev/mmcblk1p3

parted -s -a optimal /dev/mmcblk1 -- rm 3                                  # remove swap partition once
parted -s -a optimal /dev/mmcblk1 -- mkpart Linux_Swap linux-swap -1000 -1 # make 1GB swap partition at end of SD
parted -s -a optimal /dev/mmcblk1 -- resizepart 2 -1001                    # expand rootfs to before swap partition

mkswap /dev/mmcblk1p3
swapon /dev/mmcblk1p3

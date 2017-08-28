#!/bin/sh

if [ ! "${USER}" = "root" ]; then
    echo "This script need to do with sudo or root account."
    exit 1
fi

mkdir /tmp/initramfs
cd /tmp/initramfs

dd if=/dev/mmcblk0p4 of=initramfs.img bs=1 skip=8

zcat initramfs.img | cpio -id

cp -r etc/firmware/* /opt/etc/firmware/
cd /tmp

rm -fr /tmp/initramfs


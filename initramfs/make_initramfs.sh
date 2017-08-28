#!/bin/sh

####################################
#
# initramfs create script for DM200
# v0.2 @ichinomoto
#
####################################

BUSYBOX_SRC_VERSION=busybox-1.27.1

if [ ! "${USER}" = "root" ]; then
    echo "This script need to do with sudo or root account."
    exit 1
fi

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

#wget http://busybox.net/downloads/$BUSYBOX_SRC_VERSION.tar.bz2
tar jxvf $BUSYBOX_SRC_VERSION.tar.bz2
cd $BUSYBOX_SRC_VERSION
make defconfig
sed -i -e "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/" .config
make install -j4

cd _install
mkdir -p dev/pts
mkdir -p dev/shm
mkdir -p dev/snd
mkdir -p dev/sound
mkdir proc
mkdir root
mkdir sys
mkdir -p tmp/sd

mknod dev/mmcblk0 b 179 0
mknod dev/mmcblk0p14 b 179 14
mknod dev/mmcblk0p15 b 179 15
mknod dev/mmcblk1 b 179 32
mknod dev/mmcblk1p1 b 179 33
mknod dev/mmcblk1p2 b 179 34
mknod -m 666 dev/fb0 u 29 0

mkdir sbin/orig
ln -s ../../bin/busybox sbin/orig/init
rm sbin/init
cp ../../init sbin/init

find . | cpio -R 0:0 -o -H newc | gzip > ../../initramfs.img

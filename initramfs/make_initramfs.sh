#!/bin/sh

####################################
#
# initramfs create script for DM200
# v0.21 @ichinomoto
# ####################################
BUSYBOX_SRC_VERSION=busybox-1.35.0

if [ ! "${USER}" = "root" ]; then
    echo "This script need to do with sudo or root account."
    exit 1
fi

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
export CONFIG_EXTRA_LDLIBS="pthread dl tirpc audit pam"

wget http://busybox.net/downloads/$BUSYBOX_SRC_VERSION.tar.bz2
tar jxvf $BUSYBOX_SRC_VERSION.tar.bz2
cd $BUSYBOX_SRC_VERSION
make defconfig
sed -i -e "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/" .config
make -j4
make install

cd _install
mkdir -p dev/pts
mkdir -p dev/shm
mkdir -p dev/snd
mkdir -p dev/sound
mkdir proc
mkdir root
mkdir sys
mkdir -p mnt/sd
mkdir sbin/orig
ln -s ../../bin/busybox sbin/orig/init
rm sbin/init
cp ../../files/init sbin/init
cp ../../files/init init
cp -r ../../files/bin/* bin/
cp -r ../../files/lib .
cp -r ../../files/etc .

find . | cpio -R 0:0 -o -H newc | gzip > ../../initramfs.img

cd ../..
./rkcrc -k initramfs.img initramfs.crc
mv initramfs.crc initramfs.img

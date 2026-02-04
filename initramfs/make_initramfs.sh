#!/bin/sh

#######################################
#
# initramfs create script for DM200/250
# v0.3.1 @ichinomoto
#
#######################################
BUSYBOX_SRC_VERSION=busybox-1.37.0

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
# busybox 1.37ではこれをnoにしないと動かない。
# https://forum.beagleboard.org/t/errors-during-busybox-compilation/38969/5
sed -i -e "s/CONFIG_TC=y/CONFIG_TC=n/" .config
# busybox 1.37でx86_64以外は修正が必要
# https://lists.uclibc.org/pipermail/busybox/2024-September/090899.html
patch -u --ignore-whitespace libbb/hash_md5_sha.c ../for1.37_MissingShaNIguard.patch
make -j$(proc)
make install

cd _install
mkdir -p dev/pts
mkdir -p dev/shm
mkdir -p dev/snd
mkdir -p dev/sound
mkdir -p tmp
mkdir proc
mkdir root
mkdir sys
mkdir -p mnt/sd
mkdir sbin/orig
ln -s /bin/busybox sbin/orig/init
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

#!/bin/sh

##############################
# DM200 debian install sctipt
# ver. 0.11
# @ichinomoto
#


#########################
# settings
#

##
# device
#
KERNEL_TARGET=/dev/mmcblk0p14      # recovery_kernel
INITRAMFS_TARGET=/dev/mmcblk0p15   # recovery_initramfs
MMCBLK_SD_VFAT=/dev/mmcblk1p1      # vfat
MMCBLK_SD_ROOTFS=/dev/mmcblk1p2    # rootfs
MMCBLK_SD_SWAP=/dev/mmcblk1p3      # swap

##
# mount point
MOUNT_SD=/tmp/sd
MOUNT_ROOTFS=/tmp/rootfs

##
# file
#
RESOURCE_IMG_DIR=$MOUNT_SD/res/imgs
KERNEL_IMG=$MOUNT_SD/res/kernel.img
INITRAMFS_IMG=$MOUNT_SD/res/initramfs.img
LOGFILE=$MOUNT_SD/install.log

RET=0


#########################
# functions
#

##
# mount sd card
#
mount_sd () {
    if [ ! -d $MOUNT_SD ]; then
        mkdir $MOUNT_SD
    fi
    mount -t vfat $MMCBLK_SD_VFAT $MOUNT_SD
}

##
# show error image
#
show_error_img () {
    dd if=$RESOURCE_IMG_DIR/install_error.bin of=/dev/fb0 bs=2K seek=410 count=190 > /dev/null 2>&1
}

##
# mount target rootfs
#
mount_target_rootfs () {
   mkdir -p $MOUNT_ROOTFS
   mount -t ext4 $MMCBLK_SD_ROOTFS $MOUNT_ROOTFS

   if [ $? -ne 0 ];then
       echo "target mount error!" >> $LOGFILE
       echo "error in mount_target_root $?" > $MOUNT_SD/INSTALL_ERROR
       RET=1
   fi
}

##
# copy bluetooth firmware and settings
#
copy_files () {
    mkdir /tmp/sys_info
    mount -t ext4 -o ro /dev/mmcblk0p11 /tmp/sys_info
    mkdir -p $MOUNT_ROOTFS/opt/sys_info
    cp /tmp/sys_info/bcm20710a1.hcd $MOUNT_ROOTFS/opt/sys_info/bcm20710a1.hcd
    cp /tmp/sys_info/brightlevel.dat $MOUNT_ROOTFS/opt/sys_info/brightlevel.dat
    cp /tmp/sys_info/bt_mac.dat $MOUNT_ROOTFS/opt/sys_info/bt_mac.dat
    cp /tmp/sys_info/wifi_mac.dat $MOUNT_ROOTFS/opt/sys_info/wifi_mac.dat
    umount /tmp/sys_info

    mkdir -p $MOUNT_ROOTFS/opt/etc
    cp -r /system/etc/firmware $MOUNT_ROOTFS/opt/etc/

    echo "get resource files end" >> $LOGFILE
}

##
# install kernel
#
install_kernel () {
    dd if=$KERNEL_IMG of=$KERNEL_TARGET bs=4M

    if [ $? = 0 ]; then
        echo "install kernel success" >> $LOGFILE
    else
        echo "install kernel error!" >> $LOGFILE
        echo "error in install_kernel $?" >$MOUNT_SD/INSTALL_ERROR
	RET=2
    fi
}

##
# install initramfs
#
install_initramfs () {
    dd if=$INITRAMFS_IMG of=$INITRAMFS_TARGET bs=4M

    if [ $? = 0 ]; then
        echo "install initramfs success" >> $LOGFILE
    else
        echo "install initramfs error!" >> $LOGFILE
        echo "error in install_initramfs $?" >$MOUNT_SD/INSTALL_ERROR
	RET=3
    fi
}

##
# format swap partition
#
make_swap() {
    mkswap $MMCBLK_SD_SWAP
}

##
# remove install files
#
remove_install_files() {
    rm $MOUNT_SD/_sdboot.sh
    rm $MOUNT_SD/install.sh
    rm -fr $MOUNT_SD/res
}

#########################
# main
#

# mount sd
#mount_sd

date > $LOGFILE
echo "start debian installer" >> $LOGFILE

#show img
echo 0 > /sys/class/graphics/fb0/rotate
dd if=/dev/zero of=/dev/fb0 > /dev/null 2>&1
dd if=$RESOURCE_IMG_DIR/install_top.bin of=/dev/fb0 bs=2K count=170 > /dev/null 2>&1

# mount rootfs
#mount_target_rootfs
#if [ $RET -ne 0 ]; then
#    show_error_img
#    sleep 3
#    exit 1
#fi

# get resource files from dm200 original partition
#dd if=$RESOURCE_IMG_DIR/install_file.bin of=/dev/fb0 bs=2K seek=170 count=60 > /dev/null 2>&1
#copy_files

# install kernel/initramfs
dd if=$RESOURCE_IMG_DIR/install_kernel.bin of=/dev/fb0 bs=2K seek=230 count=60 > /dev/null 2>&1
install_kernel
if [ $RET -ne 0 ]; then
    show_error_img
    sleep 3
    exit 1
fi

dd if=$RESOURCE_IMG_DIR/install_initramfs.bin of=/dev/fb0 bs=2K seek=290 count=60 > /dev/null 2>&1
install_initramfs
if [ $RET -ne 0 ]; then
    show_error_img
    sleep 3
    exit 1
fi

# format swap partition
#dd if=$RESOURCE_IMG_DIR/install_swap.bin of=/dev/fb0 bs=2K seek=350 count=60 > /dev/null 2>&1
#make_swap

# install end
dd if=$RESOURCE_IMG_DIR/install_bottom.bin of=/dev/fb0 bs=2K seek=410 count=190 > /dev/null 2>&1
touch $MOUNT_SD/INSTALL_COMPLETED
echo "install finished" >> $LOGFILE
date >> $LOGFILE

# remove install file
remove_install_files
echo "remove install files finished" >> $LOGFILE
date >> $LOGFILE

sleep 3

exit 0

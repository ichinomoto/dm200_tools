#!/bin/sh

#########################
# settings
#
MMCBLK_SD=/dev/mmcblk1p1
MOUNT_SD=/tmp/sd
RESOURCE_IMG_DIR=$MOUNT_SD/res/imgs
LOGFILE=$MOUNT_SD/install.log

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
    mount -t vfat $MMCBLK_SD $MOUNT_SD
}

##
# init_screen
#
init_screen () {
    echo 0 > /sys/class/graphics/fb0/rotate
    dd if=/dev/zero of=/dev/fb0 > /dev/null 2>&1
}

##
# show image
#
show_img () {
    dd if=$RESOURCE_IMG_DIR/$1 of=/dev/fb0 bs=2K > /dev/null 2>&1
}

#########################
# main
#

export LANG=C

mount_sd
init_screen

# Check ERROR file
if [ -f $MOUNT_SD/INSTALL_ERROR ]; then
    echo "INSTALL_ERROR file exists" > $LOGFILE
    reboot
fi

# if install is completed or not
if [ ! -f $MOUNT_SD/INSTALL_COMPLETED ]; then
    $MOUNT_SD/install.sh
else
    echo "INSTALL_COMPLETE file exists" > $LOGFILE
fi

reboot

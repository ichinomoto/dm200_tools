#!/bin/sh

############################
#
# DM200 rootfs make script
# v0.4.1 @ichinomoto
#
############################

###########
# settings
#

VERSION=bullseye
ENABLE_X=1

#VARIANT=buildd
VARIANT=minbase
#SERVER=http://ftp.debian.org/debian/
SERVER=http://ftp.jp.debian.org/debian/

ROOTFS=rootfs
CACHE_DIR=`pwd`/cache/$VERSION
COMPONENTS=main,contrib,non-free

# base
PACKAGE=apt-transport-https,apt-utils,ca-certificates,debian-archive-keyring,systemd,dbus,systemd-sysv,vim-tiny,unzip,bzip2,libcap2-bin
# network
PACKAGE=${PACKAGE},netbase,ifupdown,dnsutils,net-tools,isc-dhcp-client,openssh-server,iputils-ping,wget
# wireless
PACKAGE=${PACKAGE},bluetooth,wireless-tools,wpasupplicant
# console
PACKAGE=${PACKAGE},console-setup,sudo,psmisc,locales,keyboard-configuration,dialog,parted,less,lv,unar
# console tools extra
#PACKAGE=${PACKAGE},mc,gpm
# japanese console
PACKAGE=${PACKAGE},fbterm,fbi,screen,tmux,fonts-ricty-diminished,fonts-noto-cjk-extra
# FEP
PACKAGE=${PACKAGE},uim-mozc,uim-fep
# etc
PACKAGE=${PACKAGE},alsa-utils,man-db
# develop
PACKAGE=${PACKAGE},python3
# editor
PACKAGE=${PACKAGE},vim-tiny,emacs-nox

# X version option
if [ ${ENABLE_X} -eq 1 ]; then
    PACKAGE=${PACKAGE},xorg
    PACKAGE=${PACKAGE},vim-gtk,emacs,midori
    # XFCE4
    PACKAGE=${PACKAGE},xfce4,dbus-user-session,dbus-x11,gvfs,xfce4-power-manager,xfce4-terminal
    # BT audio
    #PACKAGE=${PACKAGE},pulseaudio-module-bluetooth
    # FEP X
    PACKAGE=${PACKAGE},ibus-mozc
    #PACKAGE=${PACKAGE},fcitx-mozc,fcitx-config-gtk,mozc-utils-gui
fi


##########################
# ubuntu 16.04
#VERSION=xenial
#COMPONENTS=main,restricted,universe,multiverse
#PACKAGE=vim,bluez,net-tools,wireless-tools,console-setup,sudo,isc-dhcp-client,wpasupplicant,psmisc,locales,fbterm,uim-fep,tmux,emacs,fonts-ricty-diminished,fonts-migmix,uim-anthy,fbterm,fluxbox,xorg,xfce4,libcap2-bin
#SERVER=http://jp.archive.ubuntu.com/ubuntu-ports/


###########
# main
#

if [ ! "${USER}" = "root" ]; then
    echo "This script need to do with sudo or root account."
    exit 1
fi

if [ -n "$1" ]; then
    ROOTFS=$1
fi

# make rootfs dir
mkdir -p $ROOTFS

# make debootstrap cache dir
mkdir -p $CACHE_DIR

# debootstrap
qemu-debootstrap --arch=armhf --variant=$VARIANT --components=$COMPONENTS --include=$PACKAGE --cache-dir=$CACHE_DIR $VERSION $ROOTFS $SERVER

# copy additional scripts
COPY_FILES=files

if [ -e $COPY_FILES ]; then
    cp -r $COPY_FILES/etc $ROOTFS/
    cp -r $COPY_FILES/lib $ROOTFS/
    cp -r $COPY_FILES/lib/modules $ROOTFS/lib/
    cp -r $COPY_FILES/opt $ROOTFS/

    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc3.d/S10dm200_wireless
    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc4.d/S10dm200_wireless
    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc5.d/S10dm200_wireless
    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc6.d/K10dm200_wireless

    ln -s ../init.d/usb_host $ROOTFS/etc/rc3.d/S10usb_host
    ln -s ../init.d/usb_host $ROOTFS/etc/rc4.d/S10usb_host
    ln -s ../init.d/usb_host $ROOTFS/etc/rc5.d/S10usb_host
    ln -s ../init.d/usb_host $ROOTFS/etc/rc6.d/K10usb_host

    ln -s ../init.d/backlight $ROOTFS/etc/rc3.d/S10backlight
    ln -s ../init.d/backlight $ROOTFS/etc/rc4.d/S10backlight
    ln -s ../init.d/backlight $ROOTFS/etc/rc5.d/S10backlight
    ln -s ../init.d/backlight $ROOTFS/etc/rc6.d/K10backlight

    ln -s ../init.d/firstboot $ROOTFS/etc/rc3.d/S10firstboot
fi

#get firmware from armbian github repository
mkdir -p $ROOTFS/opt/etc/firmware

# for DM200
wget https://github.com/armbian/firmware/raw/master/ap6210/bcm20710a1.hcd -O $ROOTFS/opt/etc/firmware/bcm20710a1.hcd
wget https://raw.githubusercontent.com/armbian/firmware/master/ap6210/nvram.txt -O $ROOTFS/opt/etc/firmware/nvram_AP6210.txt
wget https://github.com/armbian/firmware/raw/master/rkwifi/fw_RK901a2.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2.bin
wget https://github.com/armbian/firmware/raw/master/rkwifi/fw_RK901a2_apsta.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2_apsta.bin
wget https://github.com/armbian/firmware/raw/master/rkwifi/fw_RK901a2_p2p.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2_p2p.bin

# for DM250
wget https://github.com/armbian/firmware/raw/master/ap6212/bcm43438a1.hcd -O $ROOTFS/opt/etc/firmware/BCM43438A1.hcd
wget https://github.com/armbian/firmware/raw/master/ap6212/fw_bcm43438a1.bin -O $ROOTFS/opt/etc/firmware/fw_bcm43438a1.bin
wget https://github.com/armbian/firmware/raw/master/ap6212/fw_bcm43438a1_mfg.bin -O $ROOTFS/opt/etc/firmware/fw_bcm43438a1_mfg.bin
wget https://github.com/armbian/firmware/raw/master/ap6212/nvram.txt -O $ROOTFS/opt/etc/firmware/nvram_AP6212.txt


if [ -e ./initial_settings.sh ]; then
    cp initial_settings.sh $ROOTFS/tmp/
    export HOME=/root
    chroot $ROOTFS /tmp/initial_settings.sh
fi

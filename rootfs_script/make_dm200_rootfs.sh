#!/bin/sh

############################
#
# DM200 rootfs make script
# v0.31 @ichinomoto
#
############################

COPY_FILES=files

###########
# settings
#

#VARIANT=buildd
VARIANT=minbase
ROOTFS=rootfs
#SERVER=http://ftp.jp.debian.org/debian/
SERVER=http://ftp.debian.org/debian/

# jessie Debian8
#VERSION=jessie
#PACKAGE=apt-transport-https,apt-utils,ca-certificates,debian-archive-keyring,vim-tiny,bluetooth,netbase,net-tools,wireless-tools,console-setup,sudo,isc-dhcp-client,wpasupplicant,openssh-server,iputils-ping,dnsutils,psmisc,locales,fbterm,uim-fep,uim-anthy,fonts-migmix,tmux

# stretch Debian9
VERSION=stretch
COMPONENTS=main,contrib,non-free
# base
PACKAGE=apt-transport-https,apt-utils,ca-certificates,debian-archive-keyring,systemd,dbus,systemd-sysv,vim-tiny,unzip,bzip2,libcap2-bin
# network
PACKAGE=${PACKAGE},netbase,ifupdown,dnsutils,net-tools,isc-dhcp-client,openssh-server,iputils-ping,wget
# wireless
PACKAGE=${PACKAGE},bluetooth,wireless-tools,wpasupplicant
# console
PACKAGE=${PACKAGE},console-setup,sudo,psmisc,locales,keyboard-configuration,dialog,parted,less,lv
# console tools extra
#PACKAGE=${PACKAGE},mc,gpm
# japanese console
PACKAGE=${PACKAGE},fbterm,fbi,screen,tmux,fonts-ricty-diminished
# FEP
PACKAGE=${PACKAGE},uim-mozc,uim-fep
# FEP X
PACKAGE=${PACKAGE},ibus-mozc
#PACKAGE=${PACKAGE},fcitx-mozc,fcitx-config-gtk,mozc-utils-gui
# etc
PACKAGE=${PACKAGE},alsa-utils,man-db
# develop
#PACKAGE=${PACKAGE},python3,ruby
# editor
PACKAGE=${PACKAGE},vim-tiny,emacs-nox
# X version option
#PACKAGE=${PACKAGE},vim-gtk,emacs,midori,fonts-takao-mincho,fonts-takao-gothic
PACKAGE=${PACKAGE},vim-gtk,emacs,midori,fonts-noto
# XFCE4
PACKAGE=${PACKAGE},xfce4,dbus-user-session,dbus-x11,gvfs,xorg,xfce4-power-manager
# BT audio
#PACKAGE=${PACKAGE},pulseaudio-module-bluetooth


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
mkdir $ROOTFS

# debootstrap
qemu-debootstrap --arch=armhf --variant=$VARIANT --components=$COMPONENTS --include=$PACKAGE $VERSION $ROOTFS $SERVER

# copy additional scripts
if [ -e $COPY_FILES ]; then
    cp -r $COPY_FILES/etc $ROOTFS/
    cp -r $COPY_FILES/lib $ROOTFS/
    cp -r $COPY_FILES/opt $ROOTFS/
    cp -r $COPY_FILES/usr $ROOTFS/
#    cp $COPY_FILES/etc/skel/.uim $ROOTFS/etc/skel/
#    cp $COPY_FILES/etc/skel/.fbtermrc $ROOTFS/etc/skel/
#    cp $COPY_FILES/etc/adjtime $ROOTFS/etc/

#    cp $COPY_FILES/etc/init.d/dm200_wireless $ROOTFS/etc/init.d/
    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc3.d/S10dm200_wireless
    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc4.d/S10dm200_wireless
    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc5.d/S10dm200_wireless
    ln -s ../init.d/dm200_wireless $ROOTFS/etc/rc6.d/K10dm200_wireless

#    cp $COPY_FILES/etc/init.d/usb_host $ROOTFS/etc/init.d/
    ln -s ../init.d/usb_host $ROOTFS/etc/rc3.d/S10usb_host
    ln -s ../init.d/usb_host $ROOTFS/etc/rc4.d/S10usb_host
    ln -s ../init.d/usb_host $ROOTFS/etc/rc5.d/S10usb_host
    ln -s ../init.d/usb_host $ROOTFS/etc/rc6.d/K10usb_host

    ln -s ../init.d/keychecker $ROOTFS/etc/rc3.d/S10keychecker
    ln -s ../init.d/keychecker $ROOTFS/etc/rc4.d/S10keychecker
    ln -s ../init.d/keychecker $ROOTFS/etc/rc5.d/S10keychecker
    ln -s ../init.d/keychecker $ROOTFS/etc/rc6.d/K10keychecker

    ln -s ../init.d/firstboot $ROOTFS/etc/rc3.d/S10firstboot
fi

#get firmware from armbian and rockchip github repository
    mkdir -p $ROOTFS/opt/etc/firmware
    wget https://github.com/armbian/firmware/raw/master/ap6210/bcm20710a1.hcd -O $ROOTFS/opt/etc/firmware/bcm20710a1.hcd
    wget https://raw.githubusercontent.com/armbian/firmware/master/ap6210/nvram_ap6210.txt -O $ROOTFS/opt/etc/firmware/nvram_AP6210.txt
    wget https://github.com/rockchip-linux/rk-rootfs-build/raw/master/overlay-firmware/system/etc/firmware/nvram_AP6210.txt -O $ROOTFS/opt/etc/firmware/nvram_AP6210.txt
    wget https://github.com/rockchip-linux/rk-rootfs-build/raw/master/overlay-firmware/system/etc/firmware/fw_RK901a2.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2.bin
    wget https://github.com/rockchip-linux/rk-rootfs-build/raw/master/overlay-firmware/system/etc/firmware/fw_RK901a2_apsta.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2_apsta.bin
    wget https://github.com/rockchip-linux/rk-rootfs-build/raw/master/overlay-firmware/system/etc/firmware/fw_RK901a2_p2p.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2_p2p.bin

if [ -e ./initial_settings.sh ]; then
    cp initial_settings.sh $ROOTFS/tmp/
    export HOME=/root
    chroot $ROOTFS /tmp/initial_settings.sh
fi

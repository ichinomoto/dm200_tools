#!/bin/sh

############################
#
# DM200 rootfs make script
# v0.4.2 @ichinomoto,@letwir
#
############################

###########
# settings
#

# distri VERSION
VERSION=trixie

## GUI option
ENABLE_X=1

# distri SIZE
#VARIANT=buildd
VARIANT=minbase

# distri SERVERURL
#SERVER=http://ports.ubuntu.com/ubuntu-ports
SERVER=http://ftp.jp.debian.org/debian/

# rootfs FILEFORMAT
FORMAT=directory

ROOTFS=rootfs
TMPDIR=tmp/$VERSION
COMPONENTS=main,contrib,non-free,non-free-firmware

# base
PACKAGE=apt-transport-https,apt-utils,ca-certificates,dbus,vim-tiny,unzip,bzip2,libcap2-bin
# base-keyring
PACKAGE=${PACKAGE},debian-archive-keyring,debian-ports-archive-keyring,ubuntu-keyring,ubuntu-archive-keyring
# systemd
PACKAGE=${PACKAGE},systemd,systemd-resolved
# network
PACKAGE=${PACKAGE},netbase,ifupdown,dnsutils,net-tools,isc-dhcp-client,openssl,openssh-server,iputils-ping,wget,curl,git
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
PACKAGE=${PACKAGE},python3,python3-pip
# editor
PACKAGE=${PACKAGE},nano,vim,emacs-nox

# X version option
if [ ${ENABLE_X} -eq 1 ]; then
    PACKAGE=${PACKAGE},xorg,tightvncserver
#    PACKAGE=${PACKAGE},vim-gtk,emacs,midori
    PACKAGE=${PACKAGE},emacs
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

mkdir -p $TMPDIR

# debootstrap
mmdebstrap \
--variant=$VARIANT \
--format=$FORMAT \
--arch=armhf \
--comp=$COMPONENTS \
--include=$PACKAGE \
--logfile=./rootfs.log \
$VERSION $ROOTFS $SERVER

if [ `grep "success" rootfs.log` eq 0 ]; then
    echo "rootfs make successed !"
else
    cat rootfs.log
    exit 1
fi
# copy additional scripts
COPY_FILES=files

if [ -e $COPY_FILES ]; then
    cp -Rdp $COPY_FILES/etc $ROOTFS/ && echo "etc copied !"
    cp -Rdp $COPY_FILES/lib $ROOTFS/usr && echo "lib copied !"
    #cp -R $COPY_FILES/lib/modules $ROOTFS/lib/ && echo "lib/modules copied !"
    cp -Rdp $COPY_FILES/opt $ROOTFS/ && echo "opt copied !"

    ln -s $ROOTFS/etc/init.d/dm200_wireless $ROOTFS/etc/rc3.d/S10dm200_wireless
    ln -s $ROOTFS/etc/init.d/dm200_wireless $ROOTFS/etc/rc4.d/S10dm200_wireless
    ln -s $ROOTFS/etc/init.d/dm200_wireless $ROOTFS/etc/rc5.d/S10dm200_wireless
    ln -s $ROOTFS/etc/init.d/dm200_wireless $ROOTFS/etc/rc6.d/K10dm200_wireless

    ln -s $ROOTFS/etc/init.d/usb_host $ROOTFS/etc/rc3.d/S10usb_host
    ln -s $ROOTFS/etc/init.d/usb_host $ROOTFS/etc/rc4.d/S10usb_host
    ln -s $ROOTFS/etc/init.d/usb_host $ROOTFS/etc/rc5.d/S10usb_host
    ln -s $ROOTFS/etc/init.d/usb_host $ROOTFS/etc/rc6.d/K10usb_host

    ln -s $ROOTFS/etc/init.d/backlight $ROOTFS/etc/rc3.d/S10backlight
    ln -s $ROOTFS/etc/init.d/backlight $ROOTFS/etc/rc4.d/S10backlight
    ln -s $ROOTFS/etc/init.d/backlight $ROOTFS/etc/rc5.d/S10backlight
    ln -s $ROOTFS/etc/init.d/backlight $ROOTFS/etc/rc6.d/K10backlight

    ln -s $ROOTFS/etc/init.d/firstboot $ROOTFS/etc/rc3.d/S10firstboot
fi

#get firmware from armbian github repository
mkdir -p $ROOTFS/opt/etc/firmware

# for DM200
wget https://github.com/armbian/firmware/raw/master/ap6210/bcm20710a1.hcd -O $ROOTFS/opt/etc/firmware/bcm20710a1.hcd
wget https://github.com/armbian/firmware/raw/master/ap6210/nvram.txt -O $ROOTFS/opt/etc/firmware/nvram_AP6210.txt
wget https://github.com/armbian/firmware/raw/master/rkwifi/fw_RK901a2.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2.bin
wget https://github.com/armbian/firmware/raw/master/rkwifi/fw_RK901a2_apsta.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2_apsta.bin
wget https://github.com/armbian/firmware/raw/master/rkwifi/fw_RK901a2_p2p.bin -O $ROOTFS/opt/etc/firmware/fw_RK901a2_p2p.bin

# for DM250
wget https://github.com/armbian/firmware/raw/master/ap6212/bcm43438a1.hcd -O $ROOTFS/opt/etc/firmware/BCM43438A1.hcd
wget https://github.com/armbian/firmware/raw/master/ap6212/fw_bcm43438a1.bin -O $ROOTFS/opt/etc/firmware/fw_bcm43438a1.bin
wget https://github.com/armbian/firmware/raw/master/ap6212/fw_bcm43438a1_mfg.bin -O $ROOTFS/opt/etc/firmware/fw_bcm43438a1_mfg.bin
wget https://github.com/armbian/firmware/raw/master/ap6212/nvram.txt -O $ROOTFS/opt/etc/firmware/nvram_AP6212.txt

mkdir -p $ROOTFS/lib/firmware
ln -s $ROOTFS/opt/etc/firmware/ $ROOTFS/lib/firmware/pomera

if [ -e ./initial_settings.sh ]; then
    cp initial_settings.sh $ROOTFS/tmp/
    export HOME=/root
    cp myinstall.sh $ROOTFS/tmp/
    # chroot settings
    mount -t proc proc /proc
    bind
    echo "chroot $ROOTFS /tmp/myinstall.sh"

    chroot $ROOTFS /tmp/initial_settings.sh
    chroot $ROOTFS /tmp/myinstall.sh
    umount $ROOTFS/proc
fi

#!/bin/sh

# global settings
HOSTNAME=pomera
USERNAME=pomera
# ---------------

# chroot settings
mount -t proc proc /proc
bind

# user interface
## japanese settings
chmod u+s /usr/bin/fbterm
sed -i -e "s/# ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/" /etc/locale.gen
LANG="ja_JP.UTF-8"
locale-gen
update-locale
rm /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

## no sudo
chmod u+s /sbin/halt
chmod u+s /sbin/reboot
chmod u+s /usr/bin/ping
chmod u+s /usr/bin/ping4
chmod u+s /usr/bin/ping6

## keyboard layout
echo 'XKBMODEL="jp106"' > /etc/default/keyboard
echo 'XKBLAYOUT="jp"' >> /etc/default/keyboard
echo '#XKBOPTIONS="ctrl:nocaps"' >> /etc/default/keyboard
#echo 'XKBMODEL="pc105"' > /etc/default/keyboard
#echo 'XKBLAYOUT="us"' >> /etc/default/keyboard
#echo 'XKBOPTIONS="ctrl:nocaps"' >> /etc/default/keyboard

## pomera fix
cat > /etc/adjtime << EOT
0.0 0 0
0
LOCAL
EOT


# kernel modules
## mali module
echo drm >> /etc/modules
echo mali_drm >> /etc/modules
echo ump >> /etc/modules
echo mali >> /etc/modules


# os settings
## stop auto X startup
#systemctl disable lightdm

## stop e2scrub_reap
systemctl stop e2scrub_reap.service
systemctl disable e2scrub_reap.service

## write source.list
DISTRIBUTION=`cat /etc/issue | awk '{print $1}'`
if [ ${DISTRIBUTION} = "Debian" ]; then
    CODE_NAME=`cat /etc/os-release | grep VERSION_CODENAME= | sed "s/.*=//g"`
    mkdir -p /etc/apt/sources.list.d
    touch /etc/apt/sources.list.d/debian.sources
    cat > /etc/apt/sources.list.d/debian.sources << EOF
Types: deb deb-src
URIs: https://ftp.riken.jp/Linux/debian/debian/
Suites: $CODE_NAME $CODE_NAME-updates $CODE_NAME-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: https://security.debian.org/debian-security
Suites: $CODE_NAME-security
Components: main contrib non-free non-free-firmware
Enabled: yes
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

EOF
elif [ ${DISTRIBUTION} = "Ubuntu" ]; then
    CODE_NAME=`cat /etc/os-release | grep VERSION_CODENAME= | sed "s/.*=//g"`
    mkdir -p /etc/apt/sources.list.d
    touch /etc/apt/sources.list.d/ubuntu.sources
    cat > /etc/apt/sources.list.d/ubuntu.sources << EOF
Types: deb deb-src
URIs: http://archive.ubuntu.com/ubuntu/
Suites: $CODE_NAME $CODE_NAME-updates $CODE_NAME-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb deb-src
URIs: http://security.ubuntu.com/ubuntu/
Suites: $CODE_NAME-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

EOF
fi

## make mount point
install -g 1000 -o 1000 -m 771 -d /mnt/sd
install -g 1000 -o 1000 -m 660 -d /mnt/internal

## write fstab
cat > /etc/fstab << EOT
proc                /proc           proc    nodev,nosuid,noexec                         0   0 
sysfs               /sys            sysfs   defaults                                    0   0 
devpts              /dev/pts        devpts  defaults                                    0   0 
/dev/mmcblk0p11 /opt/sys_info   ext4    ro                                          0   0 
/dev/mmcblk1p2  /                 ext4    errors=remount-ro                           0   1 
/dev/mmcblk1p3  none             swap    sw                                          0   0 
/dev/mmcblk1p1  /mnt/sd       vfat    rw,sync,dirsync,noatime,umask=0000,utf8,uid=1000,gid=1000     0   0 
/dev/mmcblk1p7  /mnt/internal vfat    rw,sync,dirsync,noatime,umask=0000,utf8,uid=1000,gid=1000     0   0 

# for not show in desktop 
/dev/mmcblk0p1  none            none    none                                        0   0 
/dev/mmcblk0p2  none            none    none                                        0   0 
/dev/mmcblk0p3  none            none    none                                        0   0 
/dev/mmcblk0p4  none            none    none                                        0   0 
/dev/mmcblk0p5  none            none    none                                        0   0 
/dev/mmcblk0p6  none            none    none                                        0   0 
/dev/mmcblk0p7  none            none    none                                        0   0 
/dev/mmcblk0p8  none            none    none                                        0   0 
/dev/mmcblk0p9  none            none    none                                        0   0 
/dev/mmcblk0p10 none            none    none                                        0   0 
/dev/mmcblk0p12 none            none    none                                        0   0 
/dev/mmcblk0p13 none            none    none                                        0   0 
/dev/mmcblk0p14 none            none    none                                        0   0 
/dev/mmcblk0p15 none            none    none                                        0   0 
/dev/mmcblk0p16 none            none    none                                        0   0 
/dev/mmcblk0p17 none            none    none                                        0   0 
/dev/mmcblk0p18 none            none    none                                        0   0 
/dev/mmcblk0p19 none            none    none                                        0   0 
/dev/mmcblk0p20 none            none    none                                        0   0 
/dev/mmcblk0p21 none            none    none                                        0   0 
/dev/mmcblk0p22 none            none    none                                        0   0 
/dev/mmcblk0p23 none            none    none                                        0   0 
/dev/mmcblk0p24 none            none    none                                        0   0 
/dev/mmcblk0p25 none            none    none                                        0   0 
/dev/mmcblk0p26 none            none    none                                        0   0 
/dev/mmcblk0p27 none            none    none                                        0   0 

# ----- user settings -----

EOT

## hostname
echo $HOSTNAME > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

## stop bluetoothd auto start
#chmod -x /etc/init.d/bluetooth


# user configures
## add auto fbterm setting for skel
cat >> /etc/skel/.bashrc << EOT
# ----- fbterm -----
alias fbterm="LANG=ja_JP.UTF-8 fbterm -- uim-fep"

# If you want to auto launch fbterm at login time, uncomment here.
#case "$TERM" in
#  linux*)
#    LANG=ja_JP.UTF-8 fbterm -- uim-fep
#	;;
#esac

# ...And If you want to auto launch tmux at login time, uncomment here.
#if [ $SHLVL = 2 ]; then
#    tmux
#fi

EOT

## add /opt/bin to PATH to skel
cat >>/etc/skel/.bashrc<<EOT
# ----- PATH -----

PATH=/usr/sbin:/sbin:/opt/bin:\$PATH

EOT

## add auto tmux setting for skel
cat >> /etc/skel/.tmux.conf << EOT
set-option -g status-interval 60
set-option -g status-right "#(date '+%m月%d日 %A %H:%M') #(/opt/bin/battery)%#(/opt/bin/battery_ischarging)"
EOT

## lock root account
passwd -l root

## add user
useradd $USERNAME -d /home/$USERNAME -m -k /etc/skel -s /bin/bash -G video,sudo,lp
echo "set $USERNAME passwd"
passwd $USERNAME

## .xinitrc
#cat << \EOT >> /home/$USERNAME/.xinitrc
#export LANG=ja_JP.UTF-8
#export GTK_IM_MODULE=ibus
#export XMODIFIERS=@im=ibus
#export QT_IM_MODULE=ibus
#
#EOT
##cat << \EOT >> /home/$USERNAME/.xinitrc
##export LANG=ja_JP.UTF-8
##export GTK_IM_MODULE=fcitx
##export XMODIFIERS=@im=fcitx
##export QT_IM_MODULE=fcitx
##
##EOT
#
##echo "ibus-daemon -drx&" >> /home/$USERNAME/.xinitrc
#echo "exec startxfce4" >> /home/$USERNAME/.xinitrc
#chown $USERNAME:$USERNAME /home/$USERNAME/.xinitrc

## add PATH to root
cat >>/root/.bashrc<<EOT
# ----- PATH -----

PATH=/usr/sbin:/sbin:/opt/bin:\$PATH

EOT


# network config
#systemctl disable NetworkManager
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl start systemd-resolved

## pomera fix - boot wait disable
systemctl disable systemd-networkd-wait-online.service

## resolv.conf
rm /etc/resolv.conf
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

## interface
cat << EOT > /etc/systemd/network/20-dhcp.network
[Match]
Name=wlan0

[Network]
DHCP=yes
EOT

# bluetooth config
#systemctl start bluetooth.service
#systemctl enable bluetooth.service


# remove myself
rm /tmp/initial_settings.sh

# start customize
/tmp/myinstall.sh
exit 0

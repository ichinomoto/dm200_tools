#!/bin/sh

set -eu
umask 022

ROOTFS_HOSTNAME=${POMERA_HOSTNAME:-pomera}
case "$ROOTFS_HOSTNAME" in
    ''|*[!A-Za-z0-9._-]*)
        echo "Invalid POMERA_HOSTNAME: $ROOTFS_HOSTNAME" >&2
        exit 1
        ;;
esac

# make_rootfs.sh configures the selected distribution's APT sources before
# installing packages. Do not replace them with Debian sources here.
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi

# Japanese locale and timezone.
if ! grep -q '^ja_JP.UTF-8 UTF-8$' /etc/locale.gen 2>/dev/null; then
    printf '%s\n' 'ja_JP.UTF-8 UTF-8' >> /etc/locale.gen
fi
locale-gen ja_JP.UTF-8
update-locale LANG=ja_JP.UTF-8
ln -sfn /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
printf '%s\n' Asia/Tokyo > /etc/timezone

# FbTerm needs the setuid bit to access the framebuffer console.
if [ -e /usr/bin/fbterm ]; then
    chmod u+s /usr/bin/fbterm
fi

# Populate the target architecture's font cache before the first console login.
# Font packages are all installed by this point, including the CJK fallbacks.
fc-cache -f

# Keyboard layout used by X and console-setup.
cat > /etc/default/keyboard <<'EOF'
XKBMODEL="jp106"
XKBLAYOUT="jp"
#XKBOPTIONS="ctrl:nocaps"
EOF

# Keep the fixed Pomera partition layout.  The root filesystem is mounted by
# the kernel command line as /dev/mmcblk1p2; these entries are for userspace
# mounts after the root filesystem is available. The FAT partition is mounted
# manually when needed, so it cannot introduce a device wait during boot.
mkdir -p /mnt/sd
cat > /etc/fstab <<'EOF'
/dev/mmcblk1p2  /               ext4    errors=remount-ro                           0   1
/dev/mmcblk1p1  /mnt/sd         vfat    rw,sync,dirsync,noatime,umask=0000,utf8,noauto,nofail 0 0
EOF
# Remove the old overlay if a rootfs directory is rebuilt without --clean.
rm -f /etc/systemd/system/dev-mmcblk1p3.swap.d/firstboot.conf
rmdir /etc/systemd/system/dev-mmcblk1p3.swap.d 2>/dev/null || true

# Hostname and local name resolution.
printf '%s\n' "$ROOTFS_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 $ROOTFS_HOSTNAME
EOF

# Remove our old helper copies when rebuilding an existing rootfs.
# /usr/local/bin is already in Debian/Ubuntu's standard PATH.
rm -f /opt/bin/battery /opt/bin/backlight /opt/bin/usb_host /opt/bin/sus2ram
for shell_rc in /root/.bashrc /etc/skel/.bashrc; do
    if [ -f "$shell_rc" ]; then
        sed -i '/^PATH=\/usr\/local\/bin:\$PATH$/d' "$shell_rc"
    fi
done

# FbTerm/uim defaults are inherited by the user created on first boot.
if ! grep -q '^alias fbterm=' /etc/skel/.bashrc 2>/dev/null; then
    cat >> /etc/skel/.bashrc <<'EOF'

alias fbterm="LANG=ja_JP.UTF-8 fbterm -- uim-fep"

# To launch FbTerm automatically on a virtual console, uncomment this block.
#case "$TERM" in
#  linux*)
#    LANG=ja_JP.UTF-8 fbterm -- uim-fep
#    ;;
#esac
EOF
fi

# Use NetworkManager for all network interfaces.  Enabling services in a
# chroot is safe; starting them here would fail because the target systemd
# instance is not running yet. NetworkManager uses the wpa_supplicant
# service through D-Bus for Wi-Fi authentication.
enable_service()
{
    service=$1
    service_target=${2:-multi-user.target}
    systemctl enable "$service" >/dev/null 2>&1 || true
    # systemctl enable is normally safe in a chroot, but some systemd
    # versions refuse it when /run is not mounted.  Keep the configuration
    # deterministic with the equivalent wants/ symlink as a fallback.
    mkdir -p "/etc/systemd/system/$service_target.wants"
    if [ -e "/etc/systemd/system/$service" ]; then
        unit_path=/etc/systemd/system/$service
    elif [ -e "/lib/systemd/system/$service" ]; then
        unit_path=/lib/systemd/system/$service
    else
        unit_path=
    fi
    if [ -n "$unit_path" ]; then
        ln -sfn "$unit_path" \
            "/etc/systemd/system/$service_target.wants/$service"
    else
        echo "warning: service unit not found: $service" >&2
    fi
}

disable_service()
{
    service=$1
    systemctl disable "$service" >/dev/null 2>&1 || true
    rm -f \
        "/etc/systemd/system/multi-user.target.wants/$service" \
        "/etc/systemd/system/network-online.target.wants/$service"
}

disable_service systemd-networkd.service
disable_service networking.service
enable_service NetworkManager.service
enable_service systemd-resolved.service

rm -f /etc/systemd/network/20-dhcp.network

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/NetworkManager.conf <<'EOF'
[main]
plugins=keyfile
dns=systemd-resolved
EOF

rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# e2scrub_reap is not useful on the small removable rootfs and can create
# unnecessary background work.  It is optional across Debian releases.
if [ -e /lib/systemd/system/e2scrub_reap.service ]; then
    systemctl disable e2scrub_reap.service >/dev/null 2>&1 || true
fi

# The current DM200 kernel uses the in-kernel DRM driver.  Its modules are
# installed explicitly with --kernel-modules when needed; no module entries
# are required in /etc/modules.

rm -f /tmp/initial_settings.sh

#!/bin/sh

set -eu

ROOTFS_USER=${DM200_USER_NAME:-pomera}
ROOTFS_HOSTNAME=${DM200_HOSTNAME:-pomera}
USER_PASSWORD=${DM200_USER_PASSWORD:-}
USER_PASSWORD_HASH=${DM200_USER_PASSWORD_HASH:-}
DEBIAN_MIRROR=${DM200_DEBIAN_MIRROR:-https://deb.debian.org/debian}
DEBIAN_SECURITY_MIRROR=${DM200_DEBIAN_SECURITY_MIRROR:-https://security.debian.org/debian-security}

case "$ROOTFS_USER" in
    ''|*[!A-Za-z0-9_-]*)
        echo "Invalid DM200_USER_NAME: $ROOTFS_USER" >&2
        exit 1
        ;;
esac
case "$ROOTFS_HOSTNAME" in
    ''|*[!A-Za-z0-9._-]*)
        echo "Invalid DM200_HOSTNAME: $ROOTFS_HOSTNAME" >&2
        exit 1
        ;;
esac

# Configure APT using the suite selected by debootstrap.  Debian 13 adds the
# non-free-firmware component and normally uses a deb822 source file; keeping a
# plain sources.list here also works with the older tools in the installer.
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi

if [ "${ID:-}" = debian ]; then
    CODE_NAME=${VERSION_CODENAME:-}
    if [ -z "$CODE_NAME" ]; then
        case "${VERSION_ID:-}" in
            13) CODE_NAME=trixie ;;
            12) CODE_NAME=bookworm ;;
            11) CODE_NAME=bullseye ;;
            10) CODE_NAME=buster ;;
        esac
    fi

    if [ -n "$CODE_NAME" ]; then
        case "$CODE_NAME" in
            trixie|forky|sid|experimental)
                COMPONENTS="main contrib non-free non-free-firmware"
                ;;
            *)
                COMPONENTS="main contrib non-free"
                ;;
        esac
        mkdir -p /etc/apt/sources.list.d
        rm -f /etc/apt/sources.list.d/debian.sources
        cat > /etc/apt/sources.list <<EOF
deb $DEBIAN_MIRROR $CODE_NAME $COMPONENTS
deb $DEBIAN_MIRROR ${CODE_NAME}-updates $COMPONENTS
deb $DEBIAN_SECURITY_MIRROR ${CODE_NAME}-security $COMPONENTS
EOF
    fi
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

# Keyboard layout used by X and console-setup.
cat > /etc/default/keyboard <<'EOF'
XKBMODEL="jp106"
XKBLAYOUT="jp"
#XKBOPTIONS="ctrl:nocaps"
EOF

# Keep the fixed DM200 partition layout.  The root filesystem is mounted by
# the kernel command line as /dev/mmcblk1p2; these entries are for userspace
# mounts after the root filesystem is available.
mkdir -p /mnt/sd /opt/sys_info
cat > /etc/fstab <<'EOF'
proc            /proc           proc    nodev,nosuid,noexec                         0   0
sysfs           /sys            sysfs   defaults                                    0   0
devpts          /dev/pts        devpts  defaults                                    0   0
/dev/mmcblk0p11 /opt/sys_info   ext4    ro,nofail,x-systemd.device-timeout=1s      0   0
/dev/mmcblk1p2  /               ext4    errors=remount-ro                           0   1
/dev/mmcblk1p3  none            swap    sw,nofail                                  0   0
/dev/mmcblk1p1  /mnt/sd         vfat    rw,sync,dirsync,noatime,umask=0000,utf8,nofail,x-systemd.device-timeout=1s 0 0
EOF

partition=1
while [ "$partition" -le 27 ]; do
    if [ "$partition" -ne 11 ]; then
        printf '/dev/mmcblk0p%-2s none            none    noauto                                      0   0\n' "$partition" >> /etc/fstab
    fi
    partition=$((partition + 1))
done

# Hostname and local name resolution.
printf '%s\n' "$ROOTFS_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 $ROOTFS_HOSTNAME
EOF

# Add /opt/bin to interactive shells.
for shell_rc in /root/.bashrc /etc/skel/.bashrc; do
    if [ ! -f "$shell_rc" ]; then
        : > "$shell_rc"
    fi
    if ! grep -q '^PATH=/opt/bin:' "$shell_rc"; then
        printf '\nPATH=/opt/bin:$PATH\n' >> "$shell_rc"
    fi
done

# Create the normal user.  No password is stored in the script: callers can
# provide a password or a crypt(3) hash through the environment, otherwise an
# interactive build prompts for it.
USER_GROUPS=sudo,video,lp
for group in audio input netdev; do
    if grep -q "^${group}:" /etc/group; then
        USER_GROUPS="$USER_GROUPS,$group"
    fi
done
if ! id "$ROOTFS_USER" >/dev/null 2>&1; then
    useradd -d "/home/$ROOTFS_USER" -m -k /etc/skel -s /bin/bash -G "$USER_GROUPS" "$ROOTFS_USER"
fi

if [ -n "$USER_PASSWORD_HASH" ]; then
    usermod -p "$USER_PASSWORD_HASH" "$ROOTFS_USER"
elif [ -n "$USER_PASSWORD" ]; then
    printf '%s:%s\n' "$ROOTFS_USER" "$USER_PASSWORD" | chpasswd
elif [ -t 0 ]; then
    printf 'Set password for %s:\n' "$ROOTFS_USER"
    passwd "$ROOTFS_USER"
else
    echo "Error: set DM200_USER_PASSWORD or DM200_USER_PASSWORD_HASH for a non-interactive build." >&2
    exit 1
fi
passwd -l root

# FbTerm/uim defaults for the DM200 console user.
if ! grep -q '^alias fbterm=' "/home/$ROOTFS_USER/.bashrc" 2>/dev/null; then
    cat >> "/home/$ROOTFS_USER/.bashrc" <<'EOF'

alias fbterm="LANG=ja_JP.UTF-8 fbterm -- uim-fep"

# To launch FbTerm automatically on a virtual console, uncomment this block.
#case "$TERM" in
#  linux*)
#    LANG=ja_JP.UTF-8 fbterm -- uim-fep
#    ;;
#esac
EOF
fi

# Use systemd-networkd for the DM200 wireless interface.  Enabling services in
# a chroot is safe; starting them here would fail because the target systemd
# instance is not running yet.
enable_service()
{
    service=$1
    systemctl enable "$service" >/dev/null 2>&1 || true
    # systemctl enable is normally safe in a chroot, but some systemd
    # versions refuse it when /run is not mounted.  Keep the configuration
    # deterministic with the equivalent wants/ symlink as a fallback.
    mkdir -p /etc/systemd/system/multi-user.target.wants
    if [ -e "/lib/systemd/system/$service" ]; then
        ln -sfn "/lib/systemd/system/$service" \
            "/etc/systemd/system/multi-user.target.wants/$service"
    else
        echo "warning: service unit not found: $service" >&2
    fi
}

enable_service systemd-networkd.service
enable_service systemd-resolved.service
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-dhcp.network <<'EOF'
[Match]
Name=wlan0

[Network]
DHCP=yes
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

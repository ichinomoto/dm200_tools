#!/bin/sh

############################
#
# DM200 Debian rootfs builder
#
############################

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

SUITE=${DM200_DEBIAN_SUITE:-trixie}
ARCH=${DM200_ROOTFS_ARCH:-armhf}
VARIANT=${DM200_ROOTFS_VARIANT:-minbase}
COMPONENTS=${DM200_DEBIAN_COMPONENTS:-main,contrib,non-free,non-free-firmware}
MIRROR=${DM200_DEBIAN_MIRROR:-https://deb.debian.org/debian}
SECURITY_MIRROR=${DM200_DEBIAN_SECURITY_MIRROR:-https://security.debian.org/debian-security}
ROOTFS=${DM200_ROOTFS_DIR:-$SCRIPT_DIR/rootfs}
CACHE_DIR=${DM200_ROOTFS_CACHE_DIR:-$SCRIPT_DIR/cache/$SUITE-$ARCH}
ENABLE_X=${DM200_ENABLE_X:-1}
INSTALL_FIRMWARE=${DM200_INSTALL_FIRMWARE:-1}
FIRMWARE_DIR=${DM200_FIRMWARE_DIR:-}
FIRMWARE_BASE_URL=${DM200_FIRMWARE_BASE_URL:-https://raw.githubusercontent.com/armbian/firmware/master}
KERNEL_MODULES_DIR=${DM200_KERNEL_MODULES_DIR:-}

CLEAN_ROOTFS=0
ROOTFS_ARGUMENT_SET=0

usage()
{
    cat <<EOF
Usage: $0 [OPTIONS] [ROOTFS]

Create a Debian ${SUITE} ${ARCH} rootfs for the Pomera DM200.

Options:
  --clean                 Remove an existing ROOTFS before building it
  --no-x                  Do not install Xorg/Xfce packages
  --no-firmware           Do not download the optional DM200/DM250 firmware
  --firmware-dir DIR      Copy firmware from DIR instead of downloading it
  --kernel-modules DIR    Copy a kernel's lib/modules directory into the rootfs
  --help                  Show this help

The same options can be set with DM200_* environment variables.  The default
output directory is rootfs_script/rootfs.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --clean)
            CLEAN_ROOTFS=1
            shift
            ;;
        --no-x)
            ENABLE_X=0
            shift
            ;;
        --no-firmware)
            INSTALL_FIRMWARE=0
            shift
            ;;
        --firmware-dir)
            if [ "$#" -lt 2 ]; then
                echo "Error: --firmware-dir requires a directory" >&2
                exit 2
            fi
            FIRMWARE_DIR=$2
            shift 2
            ;;
        --kernel-modules)
            if [ "$#" -lt 2 ]; then
                echo "Error: --kernel-modules requires a directory" >&2
                exit 2
            fi
            KERNEL_MODULES_DIR=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            if [ "$#" -gt 1 ]; then
                echo "Error: only one ROOTFS argument is accepted" >&2
                exit 2
            fi
            if [ "$#" -eq 1 ]; then
                ROOTFS=$1
                ROOTFS_ARGUMENT_SET=1
            fi
            shift
            ;;
        -* )
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [ "$ROOTFS_ARGUMENT_SET" -eq 1 ]; then
                echo "Error: only one ROOTFS argument is accepted" >&2
                exit 2
            fi
            ROOTFS=$1
            ROOTFS_ARGUMENT_SET=1
            shift
            ;;
    esac
done

case "$ROOTFS" in
    /*) ;;
    *) ROOTFS=$(pwd)/$ROOTFS ;;
esac
case "$CACHE_DIR" in
    /*) ;;
    *) CACHE_DIR=$(pwd)/$CACHE_DIR ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: run this script as root (for example: sudo $0)." >&2
    exit 1
fi

if [ "$ENABLE_X" != 0 ] && [ "$ENABLE_X" != 1 ]; then
    echo "Error: DM200_ENABLE_X must be 0 or 1" >&2
    exit 2
fi
if [ "$INSTALL_FIRMWARE" != 0 ] && [ "$INSTALL_FIRMWARE" != 1 ]; then
    echo "Error: DM200_INSTALL_FIRMWARE must be 0 or 1" >&2
    exit 2
fi
if [ -z "${DM200_USER_PASSWORD:-}" ] && [ -z "${DM200_USER_PASSWORD_HASH:-}" ] && [ ! -t 0 ]; then
    echo "Error: non-interactive builds require DM200_USER_PASSWORD or DM200_USER_PASSWORD_HASH." >&2
    exit 2
fi

for command in chroot cp find mkdir rm sed; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command not found: $command" >&2
        exit 1
    fi
done

if ! command -v debootstrap >/dev/null 2>&1; then
    echo "Error: debootstrap is required. Install the host package first." >&2
    echo "       Debian example: sudo apt install debootstrap qemu-user-static" >&2
    exit 1
fi

HOST_ARCH=$(dpkg --print-architecture 2>/dev/null || true)
USE_QEMU=1
QEMU_ARM_STATIC=
if [ "$HOST_ARCH" = "$ARCH" ]; then
    USE_QEMU=0
else
    QEMU_ARM_STATIC=$(command -v qemu-arm-static || true)
    if [ -z "$QEMU_ARM_STATIC" ]; then
        echo "Error: qemu-arm-static is required for an ${ARCH} rootfs on ${HOST_ARCH:-this host}." >&2
        echo "       Debian example: sudo apt install qemu-user-static" >&2
        exit 1
    fi
    if command -v update-binfmts >/dev/null 2>&1; then
        update-binfmts --enable qemu-arm >/dev/null 2>&1 || true
    fi
    if [ ! -e /proc/sys/fs/binfmt_misc/qemu-arm ]; then
        echo "Error: qemu-arm binfmt support is not enabled on this host." >&2
        echo "       Debian example: sudo apt install qemu-user-static binfmt-support" >&2
        exit 1
    fi
fi

if [ "$INSTALL_FIRMWARE" -eq 1 ] && [ -z "$FIRMWARE_DIR" ]; then
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        echo "Error: wget or curl is required to download firmware." >&2
        exit 1
    fi
fi
if [ "$INSTALL_FIRMWARE" -eq 1 ] && [ -n "$FIRMWARE_DIR" ] && [ ! -d "$FIRMWARE_DIR" ]; then
    echo "Error: firmware directory not found: $FIRMWARE_DIR" >&2
    exit 1
fi
if [ -n "$KERNEL_MODULES_DIR" ] && [ ! -d "$KERNEL_MODULES_DIR" ]; then
    echo "Error: kernel modules directory not found: $KERNEL_MODULES_DIR" >&2
    exit 1
fi

if [ -e "$ROOTFS" ] && [ ! -d "$ROOTFS" ]; then
    echo "Error: ROOTFS exists but is not a directory: $ROOTFS" >&2
    exit 1
fi
if [ -d "$ROOTFS" ]; then
    if [ "$CLEAN_ROOTFS" -eq 1 ]; then
        # --clean is an explicit request, but reject paths that are obviously
        # too broad to be a rootfs output directory.
        case "$ROOTFS" in
            ''|.|*/..|*/../*|/|/bin|/boot|/dev|/etc|/home|/lib|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
                echo "Error: refusing to clean a system directory: $ROOTFS" >&2
                exit 1
                ;;
        esac
        rm -rf -- "$ROOTFS"
    elif [ -n "$(find "$ROOTFS" -mindepth 1 -print -quit)" ]; then
        echo "Error: ROOTFS is not empty: $ROOTFS" >&2
        echo "       Use --clean only when replacing this exact rootfs." >&2
        exit 1
    fi
fi
mkdir -p "$ROOTFS" "$CACHE_DIR"

BASE_PACKAGES="apt-utils,ca-certificates,debian-archive-keyring,systemd,systemd-resolved,dbus,systemd-sysv,kmod,passwd"
NETWORK_PACKAGES="netbase,ifupdown,iproute2,bind9-dnsutils,net-tools,isc-dhcp-client,openssh-server,iputils-ping,wget"
WIRELESS_PACKAGES="bluetooth,rfkill,wireless-tools,wpasupplicant"
CONSOLE_PACKAGES="console-setup,sudo,psmisc,locales,keyboard-configuration,dialog,parted,e2fsprogs,less,lv,unar,evtest,fbset,i2c-tools"
JAPANESE_PACKAGES="fbterm,fbi,screen,tmux,fonts-ricty-diminished,fonts-noto-cjk-extra"
INPUT_PACKAGES="uim-mozc,uim-fep"
UTILITY_PACKAGES="alsa-utils,man-db,python3,vim-tiny,emacs-nox,unzip,bzip2,libcap2-bin"
PACKAGE="$BASE_PACKAGES,$NETWORK_PACKAGES,$WIRELESS_PACKAGES,$CONSOLE_PACKAGES,$JAPANESE_PACKAGES,$INPUT_PACKAGES,$UTILITY_PACKAGES"

if [ "$ENABLE_X" -eq 1 ]; then
    PACKAGE="$PACKAGE,xorg,vim-gtk3,emacs,netsurf-gtk,gir1.2-freedesktop"
    PACKAGE="$PACKAGE,xfce4,dbus-user-session,dbus-x11,gvfs,xfce4-power-manager,xfce4-terminal"
    PACKAGE="$PACKAGE,ibus-mozc"
fi

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export DM200_DEBIAN_MIRROR="$MIRROR"
export DM200_DEBIAN_SECURITY_MIRROR="$SECURITY_MIRROR"

echo "Creating Debian $SUITE ($ARCH) rootfs in $ROOTFS"
echo "Using debootstrap foreign stage with variant $VARIANT"

debootstrap \
    --arch="$ARCH" \
    --foreign \
    --variant="$VARIANT" \
    --components="$COMPONENTS" \
    --include="$PACKAGE" \
    --cache-dir="$CACHE_DIR" \
    "$SUITE" "$ROOTFS" "$MIRROR"

QEMU_IN_ROOTFS=0
cleanup()
{
    if [ "$QEMU_IN_ROOTFS" -eq 1 ]; then
        rm -f -- "$ROOTFS/usr/bin/qemu-arm-static"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ "$USE_QEMU" -eq 1 ]; then
    cp --dereference "$QEMU_ARM_STATIC" "$ROOTFS/usr/bin/qemu-arm-static"
    chmod 0755 "$ROOTFS/usr/bin/qemu-arm-static"
    QEMU_IN_ROOTFS=1
fi

run_in_rootfs()
{
    if [ "$USE_QEMU" -eq 1 ]; then
        chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh "$@"
    else
        chroot "$ROOTFS" /bin/sh "$@"
    fi
}

run_in_rootfs /debootstrap/debootstrap --second-stage

COPY_FILES="$SCRIPT_DIR/files"
if [ -d "$COPY_FILES/etc" ]; then
    mkdir -p "$ROOTFS/etc"
    cp -a "$COPY_FILES/etc/." "$ROOTFS/etc/"
fi
if [ -d "$COPY_FILES/opt" ]; then
    mkdir -p "$ROOTFS/opt"
    cp -a "$COPY_FILES/opt/." "$ROOTFS/opt/"
fi

if [ -n "$KERNEL_MODULES_DIR" ]; then
    mkdir -p "$ROOTFS/lib/modules"
    cp -a "$KERNEL_MODULES_DIR/." "$ROOTFS/lib/modules/"
fi

mkdir -p "$ROOTFS/etc/rc3.d" "$ROOTFS/etc/rc4.d" "$ROOTFS/etc/rc5.d" "$ROOTFS/etc/rc6.d"
for service in dm200_wireless usb_host backlight; do
    ln -sfn "../init.d/$service" "$ROOTFS/etc/rc3.d/S10$service"
    ln -sfn "../init.d/$service" "$ROOTFS/etc/rc4.d/S10$service"
    ln -sfn "../init.d/$service" "$ROOTFS/etc/rc5.d/S10$service"
    ln -sfn "../init.d/$service" "$ROOTFS/etc/rc6.d/K10$service"
done
ln -sfn ../init.d/firstboot "$ROOTFS/etc/rc3.d/S10firstboot"

download_file()
{
    url=$1
    destination=$2
    if command -v wget >/dev/null 2>&1; then
        wget --https-only --no-verbose --output-document="$destination" "$url"
    else
        curl --fail --location --retry 3 --output "$destination" "$url"
    fi
}

copy_or_download_firmware()
{
    relative_path=$1
    destination=$2
    if [ -n "$FIRMWARE_DIR" ]; then
        source_file="$FIRMWARE_DIR/$relative_path"
        if [ ! -f "$source_file" ]; then
            echo "Error: firmware file not found: $source_file" >&2
            exit 1
        fi
        cp -- "$source_file" "$destination"
    else
        download_file "$FIRMWARE_BASE_URL/$relative_path" "$destination"
    fi
}

if [ "$INSTALL_FIRMWARE" -eq 1 ]; then
    FIRMWARE_DESTINATION="$ROOTFS/opt/etc/firmware"
    mkdir -p "$FIRMWARE_DESTINATION"

    copy_or_download_firmware ap6210/bcm20710a1.hcd "$FIRMWARE_DESTINATION/bcm20710a1.hcd"
    copy_or_download_firmware ap6210/nvram.txt "$FIRMWARE_DESTINATION/nvram_AP6210.txt"
    copy_or_download_firmware rkwifi/fw_RK901a2.bin "$FIRMWARE_DESTINATION/fw_RK901a2.bin"
    copy_or_download_firmware rkwifi/fw_RK901a2_apsta.bin "$FIRMWARE_DESTINATION/fw_RK901a2_apsta.bin"
    copy_or_download_firmware rkwifi/fw_RK901a2_p2p.bin "$FIRMWARE_DESTINATION/fw_RK901a2_p2p.bin"

    copy_or_download_firmware ap6212/bcm43438a1.hcd "$FIRMWARE_DESTINATION/BCM43438A1.hcd"
    copy_or_download_firmware ap6212/fw_bcm43438a1.bin "$FIRMWARE_DESTINATION/fw_bcm43438a1.bin"
    copy_or_download_firmware ap6212/fw_bcm43438a1_mfg.bin "$FIRMWARE_DESTINATION/fw_bcm43438a1_mfg.bin"
    copy_or_download_firmware ap6212/nvram.txt "$FIRMWARE_DESTINATION/nvram_AP6212.txt"
else
    echo "Skipping optional wireless firmware"
fi

if [ -f "$SCRIPT_DIR/initial_settings.sh" ]; then
    cp "$SCRIPT_DIR/initial_settings.sh" "$ROOTFS/tmp/initial_settings.sh"
    export DM200_USER_NAME=${DM200_USER_NAME:-pomera}
    export DM200_HOSTNAME=${DM200_HOSTNAME:-pomera}
    export DM200_USER_PASSWORD=${DM200_USER_PASSWORD:-}
    export DM200_USER_PASSWORD_HASH=${DM200_USER_PASSWORD_HASH:-}
    run_in_rootfs /tmp/initial_settings.sh
fi

echo "Rootfs creation completed: $ROOTFS"
echo "Kernel modules: ${KERNEL_MODULES_DIR:-none}"

#!/bin/sh

############################
#
# Pomera Debian / Ubuntu rootfs builder
# ver.2.0.3 @ichinomoto
#
############################

set -eu
umask 022

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

DISTRO=${POMERA_ROOTFS_DISTRO:-debian}
REQUESTED_SUITE=
ROOTFS=${POMERA_ROOTFS_DIR:-}
PRINT_PACKAGES=0
ENABLE_X=${POMERA_ENABLE_X:-1}
INSTALL_FIRMWARE=${POMERA_INSTALL_FIRMWARE:-1}
FIRMWARE_DIR=${POMERA_FIRMWARE_DIR:-}
# Pin the supplemental NVRAM/Bluetooth source. Wi-Fi binaries come from APT.
# POMERA_FIRMWARE_BASE_URL
# can still point at a local mirror, while POMERA_FIRMWARE_COMMIT can select a
# different immutable Armbian revision.
FIRMWARE_COMMIT=${POMERA_FIRMWARE_COMMIT:-2a9e1c19460401443267926181191d57e3ff175d}
FIRMWARE_BASE_URL=${POMERA_FIRMWARE_BASE_URL:-https://raw.githubusercontent.com/armbian/firmware/$FIRMWARE_COMMIT}
KERNEL_MODULES_DIR=${POMERA_KERNEL_MODULES_DIR:-}
DEFAULT_KERNEL_MODULES_DIR=$SCRIPT_DIR/../docker/kernel-build/build/modules/lib/modules

if [ -z "$KERNEL_MODULES_DIR" ] && [ -d "$DEFAULT_KERNEL_MODULES_DIR" ]; then
    KERNEL_MODULES_DIR=$DEFAULT_KERNEL_MODULES_DIR
fi

CLEAN_ROOTFS=0
ROOTFS_ARGUMENT_SET=0

usage()
{
    cat <<EOF
Usage: $0 [OPTIONS] [ROOTFS]

Create a Debian or Ubuntu armhf rootfs for Pomera devices.

Options:
  --distro NAME           debian (default) or ubuntu
  --suite NAME            Debian suite, or Ubuntu resolute/26.04 (default)
  --print-packages        Print the selected package names and exit without building
  --clean                 Remove an existing ROOTFS before building it
  --no-x                  Do not install Xorg/Xfce or desktop applets
  --no-firmware           Skip Wi-Fi firmware packages and NVRAM/Bluetooth files
  --firmware-dir DIR      Copy NVRAM/Bluetooth files from DIR instead of downloading
  --kernel-modules DIR    Copy a kernel's lib/modules directory into the rootfs
  --help                  Show this help

The same options can be set with POMERA_* environment variables.  The default
NVRAM/Bluetooth revision is $FIRMWARE_COMMIT. Wi-Fi binaries use the distro's
firmware package. The default output directory is
rootfs_script/rootfs for Debian, or rootfs_script/rootfs-ubuntu-SUITE for Ubuntu.
Ubuntu builds need the host's ubuntu-keyring package (signature checks stay enabled).
A legacy module directory at
docker/kernel-build/build/modules/lib/modules is copied automatically when it
exists; the new kernel Docker flow normally installs modules from its archive
while creating make_rootfs_image.sh's model-specific image.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --distro|--suite)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                echo "Error: $1 requires a value" >&2
                exit 2
            fi
            case "$1" in
                --distro) DISTRO=$2 ;;
                --suite) REQUESTED_SUITE=$2 ;;
            esac
            shift 2
            ;;
        --print-packages)
            PRINT_PACKAGES=1
            shift
            ;;
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
            if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$ROOTFS_ARGUMENT_SET" -eq 1 ]; }; then
                echo "Error: only one ROOTFS argument is accepted" >&2
                exit 2
            fi
            if [ "$#" -eq 1 ]; then
                ROOTFS=$1
                ROOTFS_ARGUMENT_SET=1
                shift
            fi
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

if [ "$ENABLE_X" != 0 ] && [ "$ENABLE_X" != 1 ]; then
    echo "Error: POMERA_ENABLE_X must be 0 or 1" >&2
    exit 2
fi
if [ "$INSTALL_FIRMWARE" != 0 ] && [ "$INSTALL_FIRMWARE" != 1 ]; then
    echo "Error: POMERA_INSTALL_FIRMWARE must be 0 or 1" >&2
    exit 2
fi
# shellcheck source=rootfs_config.sh
. "$SCRIPT_DIR/rootfs_config.sh"
configure_rootfs

if [ "$PRINT_PACKAGES" -eq 1 ]; then
    printf '%s\n' "$PACKAGE" | tr ',' '\n'
    exit 0
fi

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

for command in chroot chown chmod cp find mkdir mount mountpoint rm sed tr umount; do
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

if [ ! -r "$KEYRING" ]; then
    echo "Error: archive keyring not found: $KEYRING" >&2
    echo "       Install the host package: sudo apt install $ARCHIVE_KEYRING_PACKAGE" >&2
    exit 1
fi
# Ubuntu releases share debootstrap's Ubuntu implementation. Debian hosts
# may have no suite-named symlink yet for the newest LTS.
BOOTSTRAP_SCRIPT=
if [ "$DISTRO" = ubuntu ]; then
    BOOTSTRAP_SCRIPT=${DEBOOTSTRAP_DIR:-/usr/share/debootstrap}/scripts/gutsy
    if [ ! -r "$BOOTSTRAP_SCRIPT" ]; then
        echo "Error: debootstrap's Ubuntu script is missing: $BOOTSTRAP_SCRIPT" >&2
        echo "       Update the host's debootstrap package." >&2
        exit 1
    fi
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
        # A previous interrupted build may have left virtual filesystems.
        # Never descend into them when replacing a rootfs directory.
        for mount_dir in proc sys dev dev/pts dev/shm run; do
            # rm removes these links themselves, not the external targets.
            [ ! -L "$ROOTFS/${mount_dir%%/*}" ] || continue
            [ ! -L "$ROOTFS/$mount_dir" ] || continue
            if mountpoint -q "$ROOTFS/$mount_dir"; then
                echo "Error: unmount $ROOTFS/$mount_dir before using --clean." >&2
                exit 1
            fi
        done
        rm -rf -- "$ROOTFS"
    elif [ -n "$(find "$ROOTFS" -mindepth 1 -print -quit)" ]; then
        echo "Error: ROOTFS is not empty: $ROOTFS" >&2
        echo "       Use --clean only when replacing this exact rootfs." >&2
        exit 1
    fi
fi
mkdir -p "$ROOTFS" "$CACHE_DIR"
chown -h 0:0 "$ROOTFS"
chmod 0755 "$ROOTFS"

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

echo "Creating $DISTRO $SUITE ($ARCH) rootfs in $ROOTFS"
echo "Using debootstrap foreign stage with variant $VARIANT"
echo "Application packages will be installed with apt after the second stage"

# Keep debootstrap focused on creating the minimal base system.
# The package selection below is intentionally installed later with apt so that
# normal dependency resolution is used for the full package set.
set -- "$SUITE" "$ROOTFS" "$MIRROR"
if [ -n "$BOOTSTRAP_SCRIPT" ]; then
    set -- "$@" "$BOOTSTRAP_SCRIPT"
fi
debootstrap \
    --keyring="$KEYRING" \
    --force-check-gpg \
    --include="$ARCHIVE_KEYRING_PACKAGE,ca-certificates" \
    --arch="$ARCH" \
    --foreign \
    --variant="$VARIANT" \
    --components="$COMPONENTS" \
    --cache-dir="$CACHE_DIR" \
    "$@"

QEMU_IN_ROOTFS=0
POLICY_RC_D_CREATED=0
PROC_MOUNTED=0

unmount_rootfs_proc()
{
    if [ "$PROC_MOUNTED" -eq 1 ]; then
        if [ -L "$ROOTFS/proc" ]; then
            echo "Error: rootfs/proc changed into a symbolic link; refusing to unmount its target." >&2
            return 1
        fi
        if mountpoint -q "$ROOTFS/proc"; then
            if ! umount "$ROOTFS/proc"; then
                echo "Error: could not unmount $ROOTFS/proc; unmount it before reusing this rootfs." >&2
                return 1
            fi
        fi
        PROC_MOUNTED=0
    fi
}

cleanup()
{
    cleanup_status=$?
    trap - EXIT
    trap '' HUP INT TERM
    if ! unmount_rootfs_proc && [ "$cleanup_status" -eq 0 ]; then
        cleanup_status=1
    fi
    if [ "$POLICY_RC_D_CREATED" -eq 1 ]; then
        if ! rm -f -- "$ROOTFS/usr/sbin/policy-rc.d" && [ "$cleanup_status" -eq 0 ]; then
            cleanup_status=1
        fi
    fi
    if [ "$QEMU_IN_ROOTFS" -eq 1 ]; then
        if ! rm -f -- "$ROOTFS/usr/bin/qemu-arm-static" && [ "$cleanup_status" -eq 0 ]; then
            cleanup_status=1
        fi
    fi
    exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$USE_QEMU" -eq 1 ]; then
    cp --dereference "$QEMU_ARM_STATIC" "$ROOTFS/usr/bin/qemu-arm-static"
    chmod 0755 "$ROOTFS/usr/bin/qemu-arm-static"
    QEMU_IN_ROOTFS=1
fi

run_in_rootfs()
{
    # debootstrap can unmount /proc at the end of its second stage, so check
    # before every chroot, including the later package/configuration commands.
    if [ -L "$ROOTFS/proc" ]; then
        echo "Error: rootfs/proc must be a directory, not a symbolic link." >&2
        return 1
    fi
    mkdir -p "$ROOTFS/proc"
    if ! mountpoint -q "$ROOTFS/proc"; then
        PROC_MOUNTED=1
        mount -t proc -o nosuid,nodev,noexec proc "$ROOTFS/proc" || return "$?"
    fi
    if [ "$USE_QEMU" -eq 1 ]; then
        chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh "$@"
    else
        chroot "$ROOTFS" /bin/sh "$@"
    fi
}

run_in_rootfs /debootstrap/debootstrap --second-stage

write_rootfs_sources "$ROOTFS"

# The second stage removes debootstrap's temporary service-start policy.
# Keep package installation from starting daemons inside the unfinished rootfs.
# Preserve any existing policy and remove only the one created here, even if
# apt fails.  Remove it before copying the final rootfs overlay as well.
if [ ! -e "$ROOTFS/usr/sbin/policy-rc.d" ] && [ ! -L "$ROOTFS/usr/sbin/policy-rc.d" ]; then
    POLICY_RC_D_CREATED=1
    printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
    chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"
fi

# debootstrap has now created a usable base system.  Install exactly the same
# package set selected above, but let apt resolve the complete dependency graph.
# --no-install-recommends keeps the result close to the previous debootstrap
# behaviour, which did not install Recommends for --include packages.
echo "Updating apt package indexes"
run_in_rootfs -c "apt-get update"

echo "Installing selected packages"
APT_PACKAGES=$(printf '%s' "$PACKAGE" | sed 's/,/ /g')
run_in_rootfs -c "apt-get install -y --no-install-recommends $APT_PACKAGES"

# Drop package archives after installation; they are not needed in the final
# rootfs and the external debootstrap cache remains available for future builds.
run_in_rootfs -c "apt-get clean"

if [ "$POLICY_RC_D_CREATED" -eq 1 ]; then
    rm -f -- "$ROOTFS/usr/sbin/policy-rc.d"
    POLICY_RC_D_CREATED=0
fi

COPY_FILES="$SCRIPT_DIR/files"
if [ -d "$COPY_FILES/etc" ]; then
    mkdir -p "$ROOTFS/etc"
    cp -a --no-preserve=ownership "$COPY_FILES/etc/." "$ROOTFS/etc/"
fi
if [ -d "$COPY_FILES/opt" ]; then
    mkdir -p "$ROOTFS/opt"
    cp -a --no-preserve=ownership "$COPY_FILES/opt/." "$ROOTFS/opt/"
fi
if [ -d "$COPY_FILES/usr" ]; then
    mkdir -p "$ROOTFS/usr"
    cp -a --no-preserve=ownership "$COPY_FILES/usr/." "$ROOTFS/usr/"
fi
normalize_rootfs_permissions "$ROOTFS" "$COPY_FILES"

# Desktop-only defaults follow the same switch as the Xfce packages.
X_COPY_FILES="$SCRIPT_DIR/files-x"
if [ "$ENABLE_X" -eq 1 ] && [ -d "$X_COPY_FILES" ]; then
    cp -a --no-preserve=ownership "$X_COPY_FILES/." "$ROOTFS/"
    normalize_rootfs_permissions "$ROOTFS" "$X_COPY_FILES"
fi

if [ -n "$KERNEL_MODULES_DIR" ]; then
    mkdir -p "$ROOTFS/lib/modules"
    cp -a --no-preserve=ownership "$KERNEL_MODULES_DIR/." "$ROOTFS/lib/modules/"
    chown -hR 0:0 "$ROOTFS/lib/modules"
    find "$ROOTFS/lib/modules" ! -type l -exec chmod go-w {} +
fi

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
    BRCM_FIRMWARE_DESTINATION="$ROOTFS/lib/firmware/brcm"
    mkdir -p "$FIRMWARE_DESTINATION"
    mkdir -p "$BRCM_FIRMWARE_DESTINATION"

    # APT owns all Wi-Fi binaries and the A1 CLM blob. Never overwrite them
    # with legacy vendor copies. Ubuntu ships compressed .zst firmware;
    # the Pomera kernel must support compressed firmware loading.
    for firmware_name in brcmfmac43362-sdio.bin brcmfmac4329-sdio.bin \
                         brcmfmac43430a0-sdio.bin brcmfmac43430-sdio.bin \
                         brcmfmac43430-sdio.clm_blob; do
        if [ ! -s "$BRCM_FIRMWARE_DESTINATION/$firmware_name" ] &&
           [ ! -s "$BRCM_FIRMWARE_DESTINATION/$firmware_name.zst" ] &&
           [ ! -s "$BRCM_FIRMWARE_DESTINATION/$firmware_name.xz" ]; then
            echo "Error: $WIFI_FIRMWARE_PACKAGE did not provide $firmware_name" >&2
            exit 1
        fi
    done

    # The common rootfs contains NVRAM and Bluetooth firmware for all models:
    # DM200 AP6210/BCM43362 and DM250/US AP6212/BCM43438.
    copy_or_download_firmware ap6210/bcm20710a1.hcd "$FIRMWARE_DESTINATION/bcm20710a1.hcd"
    copy_or_download_firmware ap6210/nvram.txt "$FIRMWARE_DESTINATION/nvram_AP6210.txt"

    copy_or_download_firmware ap6212/bcm43438a0.hcd "$FIRMWARE_DESTINATION/BCM43438A0.hcd"
    copy_or_download_firmware ap6212/bcm43438a1.hcd "$FIRMWARE_DESTINATION/BCM43438A1.hcd"
    copy_or_download_firmware ap6212/nvram.txt "$FIRMWARE_DESTINATION/nvram_AP6212.txt"

    # Board NVRAM is not supplied under the generic names by the packages.
    copy_or_download_firmware brcm/brcmfmac4329-sdio.txt \
        "$BRCM_FIRMWARE_DESTINATION/brcmfmac4329-sdio.txt"
    copy_or_download_firmware brcm/brcmfmac43430a0-sdio.txt \
        "$BRCM_FIRMWARE_DESTINATION/brcmfmac43430a0-sdio.txt"
    copy_or_download_firmware brcm/brcmfmac43430-sdio.txt \
        "$BRCM_FIRMWARE_DESTINATION/brcmfmac43430-sdio.txt"
    # hci_bcm identifies the BCM43438 Bluetooth controller as BCM4343A0
    # after reading its UART version.  Keep the vendor spelling below too.
    copy_or_download_firmware brcm/BCM4343A0.hcd \
        "$BRCM_FIRMWARE_DESTINATION/BCM4343A0.hcd"
    cp -- "$FIRMWARE_DESTINATION/BCM43438A1.hcd" \
        "$FIRMWARE_DESTINATION/BCM4343A1.hcd"
    cp -- "$FIRMWARE_DESTINATION/BCM43438A1.hcd" \
        "$BRCM_FIRMWARE_DESTINATION/BCM43430A1.hcd"
    cp -- "$FIRMWARE_DESTINATION/BCM43438A1.hcd" \
        "$BRCM_FIRMWARE_DESTINATION/BCM4343A1.hcd"

    # The mainline brcmfmac driver looks in /lib/firmware/brcm and identifies
    # the DM200 module as Broadcom BCM43362. Install its AP6210 NVRAM under
    # the requested name while leaving the package's binary untouched.
    cp -- "$FIRMWARE_DESTINATION/nvram_AP6210.txt" \
        "$BRCM_FIRMWARE_DESTINATION/brcmfmac43362-sdio.txt"
    # The Bluetooth controller is the UART-attached BCM20702A1 on the same
    # AP6210 module.  hci_bcm requests this standard firmware name.
    cp -- "$FIRMWARE_DESTINATION/bcm20710a1.hcd" \
        "$BRCM_FIRMWARE_DESTINATION/BCM20702A1.hcd"
else
    echo "Skipping optional wireless firmware"
fi

if [ -f "$SCRIPT_DIR/initial_settings.sh" ]; then
    cp "$SCRIPT_DIR/initial_settings.sh" "$ROOTFS/tmp/initial_settings.sh"
    export POMERA_HOSTNAME=${POMERA_HOSTNAME:-pomera}
    run_in_rootfs /tmp/initial_settings.sh
fi

unmount_rootfs_proc
echo "Rootfs creation completed: $ROOTFS"
echo "Kernel modules: ${KERNEL_MODULES_DIR:-none}"

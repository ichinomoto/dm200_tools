#!/bin/sh

set -eu
umask 022

export LC_ALL=C

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/rootfs_config.sh"
ROOTFS=${POMERA_ROOTFS_DIR:-$SCRIPT_DIR/rootfs}
OUTPUT=${POMERA_ROOTFS_IMAGE:-}
IMAGE_SIZE=${POMERA_ROOTFS_IMAGE_SIZE:-}
LABEL=${POMERA_ROOTFS_IMAGE_LABEL:-POMERAROOT}
FORCE=0
MODEL=
MODULE_ARCHIVE=

# Keep the image compact because the SD partition is expanded after writing.
# The source usage below is measured in allocated filesystem blocks, so the
# per-file block rounding is included without requiring a percentage margin.
# The fixed space covers filesystem metadata and a small amount of initial use.
MIN_FREE_BYTES=$((128 * 1024 * 1024))
ROUND_BYTES=$((64 * 1024 * 1024))
GROW_BYTES=$((256 * 1024 * 1024))
MAX_COPY_ATTEMPTS=4

WORK_IMAGE=
MOUNT_DIR=
MOUNTED=0
MODULE_STAGE=

usage()
{
    cat <<EOF
Usage: $0 MODEL [OPTIONS]

Create an ext4 image from a populated Pomera rootfs directory and install the
kernel modules for MODEL.

MODEL:
  dm200, dm250, dm250us

Options:
  --rootfs DIR       Source rootfs directory (default: $SCRIPT_DIR/rootfs)
  --output FILE      Output image (default: $SCRIPT_DIR/rootfs_MODEL.img)
  --size SIZE        Image size understood by truncate, for example 4G
  --label LABEL      ext4 volume label (default: $LABEL)
  --modules-archive FILE
                     Kernel module archive (default: kernel/linux/modules_MODEL.tar.gz)
  --force            Replace an existing output image
  --help             Show this help

Without --size, the image is sized to the rootfs usage plus 128 MiB, rounded
up to a 64 MiB boundary.  If the staged files still do not fit, the script
automatically retries with 256 MiB more space, up to four attempts.  An
explicit --size is treated as a fixed size.
EOF
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 2
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
esac

MODEL=$1
shift

case "$MODEL" in
    dm200|dm250|dm250us)
        ;;
    *)
        echo "Error: unsupported model: $MODEL" >&2
        echo "Supported models: dm200, dm250, dm250us" >&2
        exit 2
        ;;
esac

if [ -z "$OUTPUT" ]; then
    OUTPUT=$SCRIPT_DIR/rootfs_${MODEL}.img
fi

MODULE_ARCHIVE=${POMERA_MODULE_ARCHIVE:-$SCRIPT_DIR/../kernel/linux/modules_${MODEL}.tar.gz}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --rootfs)
            if [ "$#" -lt 2 ]; then
                echo "Error: --rootfs requires a directory" >&2
                exit 2
            fi
            ROOTFS=$2
            shift 2
            ;;
        --output)
            if [ "$#" -lt 2 ]; then
                echo "Error: --output requires a file" >&2
                exit 2
            fi
            OUTPUT=$2
            shift 2
            ;;
        --size)
            if [ "$#" -lt 2 ]; then
                echo "Error: --size requires a value" >&2
                exit 2
            fi
            IMAGE_SIZE=$2
            shift 2
            ;;
        --label)
            if [ "$#" -lt 2 ]; then
                echo "Error: --label requires a value" >&2
                exit 2
            fi
            LABEL=$2
            shift 2
            ;;
        --modules-archive)
            if [ "$#" -lt 2 ]; then
                echo "Error: --modules-archive requires a file" >&2
                exit 2
            fi
            MODULE_ARCHIVE=$2
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$ROOTFS" in
    /*) ;;
    *) ROOTFS=$(pwd)/$ROOTFS ;;
esac
case "$OUTPUT" in
    /*) ;;
    *) OUTPUT=$(pwd)/$OUTPUT ;;
esac
case "$MODULE_ARCHIVE" in
    /*) ;;
    *) MODULE_ARCHIVE=$(pwd)/$MODULE_ARCHIVE ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: run this script as root (for example: sudo $0)." >&2
    exit 1
fi

for command in awk cat chown chmod dirname du e2fsck find install ln mkfs.ext4 mount mkdir mktemp mv rm rsync rmdir sha256sum stat sync tar truncate umount; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command not found: $command" >&2
        exit 1
    fi
done

if [ ! -d "$ROOTFS" ]; then
    echo "Error: rootfs directory not found: $ROOTFS" >&2
    echo "       Run make_rootfs.sh first." >&2
    exit 1
fi
if [ -z "$(find "$ROOTFS" -mindepth 1 -print -quit)" ]; then
    echo "Error: rootfs directory is empty: $ROOTFS" >&2
    exit 1
fi
if [ ! -f "$MODULE_ARCHIVE" ]; then
    echo "Error: module archive not found for $MODEL: $MODULE_ARCHIVE" >&2
    echo "       Build it first with: (cd $SCRIPT_DIR/../kernel && ./docker_builder.sh)" >&2
    echo "       Then run ./make_kernel.sh $MODEL inside the container." >&2
    exit 1
fi

case "$OUTPUT" in
    "$ROOTFS"|"$ROOTFS"/*)
        echo "Error: output image must not be inside the source rootfs" >&2
        exit 2
        ;;
esac

if [ -e "$OUTPUT" ] && [ "$FORCE" -ne 1 ]; then
    echo "Error: output image already exists: $OUTPUT" >&2
    echo "       Use --force to replace this exact file." >&2
    exit 1
fi

# Stage the module tree selected for this model.  The archive produced by
# linux/make_kernel.sh contains ./lib/modules/....  Keep the source rootfs
# generic and install this tree only into the generated image below.
MODULE_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/pomera-modules.XXXXXX")
cleanup_module_stage()
{
    if [ -n "$MODULE_STAGE" ] && [ -d "$MODULE_STAGE" ]; then
        rm -rf -- "$MODULE_STAGE"
    fi
}
trap cleanup_module_stage EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

tar -xzf "$MODULE_ARCHIVE" -C "$MODULE_STAGE" --no-same-owner
if [ ! -d "$MODULE_STAGE/lib/modules" ]; then
    echo "Error: module archive has no lib/modules directory: $MODULE_ARCHIVE" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
used_bytes=$(du -sx -B1 -- "$ROOTFS" | awk 'NR == 1 { print $1 }')
module_bytes=$(du -sx -B1 -- "$MODULE_STAGE/lib/modules" | awk 'NR == 1 { print $1 }')
existing_module_bytes=0
if [ -d "$ROOTFS/lib/modules" ]; then
    existing_module_bytes=$(du -sx -B1 -- "$ROOTFS/lib/modules" | awk 'NR == 1 { print $1 }')
fi
case "$used_bytes" in
    ''|*[!0-9]*)
        echo "Error: could not determine rootfs size" >&2
        exit 1
        ;;
esac
case "$module_bytes" in
    ''|*[!0-9]*)
        echo "Error: could not determine module archive size" >&2
        exit 1
        ;;
esac
case "$existing_module_bytes" in
    ''|*[!0-9]*)
        echo "Error: could not determine existing module size" >&2
        exit 1
        ;;
esac
used_bytes=$((used_bytes - existing_module_bytes + module_bytes))

AUTO_SIZE=0
if [ -z "$IMAGE_SIZE" ]; then
    AUTO_SIZE=1
    image_size_bytes=$((used_bytes + MIN_FREE_BYTES))
    image_size_bytes=$(((image_size_bytes + ROUND_BYTES - 1) / ROUND_BYTES * ROUND_BYTES))
    IMAGE_SIZE=$image_size_bytes
fi

WORK_IMAGE="$OUTPUT.tmp.$$"
if [ -e "$WORK_IMAGE" ]; then
    echo "Error: temporary image already exists: $WORK_IMAGE" >&2
    exit 1
fi

cleanup()
{
    cleanup_status=$?
    if [ "$MOUNTED" -eq 1 ]; then
        sync || cleanup_status=1
        umount "$MOUNT_DIR" || cleanup_status=1
        MOUNTED=0
    fi
    if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
        rmdir "$MOUNT_DIR" 2>/dev/null || cleanup_status=1
    fi
    if [ -n "$WORK_IMAGE" ] && [ -e "$WORK_IMAGE" ]; then
        rm -f -- "$WORK_IMAGE" || cleanup_status=1
    fi
    if [ -n "$MODULE_STAGE" ] && [ -d "$MODULE_STAGE" ]; then
        rm -rf -- "$MODULE_STAGE" || cleanup_status=1
    fi
    if [ "$cleanup_status" -ne 0 ]; then
        exit "$cleanup_status"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

copy_attempt=1
while :; do
    truncate -s "$IMAGE_SIZE" "$WORK_IMAGE"
    actual_size=$(stat -c %s "$WORK_IMAGE")
    if [ "$actual_size" -lt "$used_bytes" ]; then
        echo "Error: image size ($actual_size bytes) is smaller than rootfs usage ($used_bytes bytes)" >&2
        exit 1
    fi

    mkfs.ext4 -F -m 0 -L "$LABEL" "$WORK_IMAGE"

    MOUNT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pomera-rootfs-image.XXXXXX")
    mount -o loop "$WORK_IMAGE" "$MOUNT_DIR"
    MOUNTED=1

    copy_status=0
    # Exclude identities before copying: copying private keys and unlinking
    # them afterwards would still leave their bytes in the raw ext4 image.
    rsync -aHAX --numeric-ids \
        '--exclude=/etc/ssh/ssh_host_*' --exclude=/etc/machine-id \
        --exclude=/var/lib/dbus/machine-id \
        --exclude=/var/lib/systemd/random-seed \
        "$ROOTFS/" "$MOUNT_DIR/" || copy_status=$?
    if [ "$copy_status" -eq 0 ]; then
        mkdir -p "$MOUNT_DIR/lib/modules" || copy_status=$?
    fi
    if [ "$copy_status" -eq 0 ] && [ -L "$MOUNT_DIR/lib/modules" ]; then
        echo "Error: rootfs image has an unexpected lib/modules symlink" >&2
        copy_status=1
    fi
    if [ "$copy_status" -eq 0 ]; then
        rsync -aHAX --delete --chown=0:0 --chmod=go-w "$MODULE_STAGE/lib/modules/" \
            "$MOUNT_DIR/lib/modules/" || copy_status=$?
    fi
    if [ "$copy_status" -eq 0 ]; then
        normalize_rootfs_permissions "$MOUNT_DIR" \
            "$SCRIPT_DIR/files" "$SCRIPT_DIR/files-x" || copy_status=$?
    fi

    # Also sanitize an older or previously booted source rootfs. Do this only
    # in the image: the source directory's keys and identity stay untouched.
    # Install the dependencies too, so old rootfs trees can generate new keys
    # with either SSH service or socket activation on their first boot.
    if [ "$copy_status" -eq 0 ]; then
        (
            # Retire the SD brightness override in older source rootfs trees.
            rm -f "$MOUNT_DIR/etc/systemd/system/pomera-backlight.service" \
                "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/pomera-backlight.service" || exit "$?"
            # Keep old rootfs inputs usable without boot-time FAT mount waits.
            # Preserve other fstab entries and mount options, including swap.
            if [ -f "$MOUNT_DIR/etc/fstab" ]; then
                awk '
                    $1 == "/dev/mmcblk1p1" && $2 == "/mnt/sd" && $3 == "vfat" {
                        n = split($4, opts, ",")
                        options = ""
                        for (i = 1; i <= n; i++) {
                            if (opts[i] == "noauto" || opts[i] == "x-systemd.device-timeout=1s") continue
                            options = options (options == "" ? "" : ",") opts[i]
                        }
                        $4 = options (options == "" ? "" : ",") "noauto"
                    }
                    { print }
                ' "$MOUNT_DIR/etc/fstab" > "$MOUNT_DIR/etc/fstab.pomera-tmp" || exit "$?"
                cat "$MOUNT_DIR/etc/fstab.pomera-tmp" > "$MOUNT_DIR/etc/fstab" || exit "$?"
                rm -f "$MOUNT_DIR/etc/fstab.pomera-tmp" || exit "$?"
            fi
            rm -f "$MOUNT_DIR"/etc/ssh/ssh_host_* \
                "$MOUNT_DIR/var/lib/dbus/machine-id" \
                "$MOUNT_DIR/var/lib/systemd/random-seed" \
                "$MOUNT_DIR/etc/machine-id" || exit "$?"
            printf '%s\n' uninitialized > "$MOUNT_DIR/etc/machine-id" || exit "$?"
            mkdir -p "$MOUNT_DIR/var/lib/dbus" || exit "$?"
            ln -s /etc/machine-id "$MOUNT_DIR/var/lib/dbus/machine-id" || exit "$?"
            for unit_file in sshd-keygen.service ssh.service.d/10-hostkeys.conf \
                ssh.socket.d/10-hostkeys.conf sshd@.service.d/10-hostkeys.conf; do
                install -D -m 0644 \
                    "$SCRIPT_DIR/files/etc/systemd/system/$unit_file" \
                    "$MOUNT_DIR/etc/systemd/system/$unit_file" || exit "$?"
            done
        ) || copy_status=$?
    fi

    if [ "$copy_status" -eq 0 ]; then
        sync
        umount "$MOUNT_DIR"
        MOUNTED=0
        rmdir "$MOUNT_DIR"
        MOUNT_DIR=
        rm -rf -- "$MODULE_STAGE"
        MODULE_STAGE=
        break
    fi

    if [ "$MOUNTED" -eq 1 ]; then
        sync || true
        if ! umount "$MOUNT_DIR"; then
            echo "Error: could not unmount temporary image after copy failure: $MOUNT_DIR" >&2
            exit 1
        fi
        MOUNTED=0
    fi
    if ! rmdir "$MOUNT_DIR"; then
        echo "Error: could not remove temporary mount directory: $MOUNT_DIR" >&2
        exit 1
    fi
    MOUNT_DIR=

    if [ "$AUTO_SIZE" -ne 1 ] || [ "$copy_attempt" -ge "$MAX_COPY_ATTEMPTS" ]; then
        echo "Error: could not fit rootfs and modules in image (rsync status $copy_status)" >&2
        echo "       Increase --size or omit it to enable automatic growth." >&2
        exit "$copy_status"
    fi

    IMAGE_SIZE=$((IMAGE_SIZE + GROW_BYTES))
    copy_attempt=$((copy_attempt + 1))
    echo "Image was too small; retrying with $IMAGE_SIZE bytes (attempt $copy_attempt/$MAX_COPY_ATTEMPTS)." >&2
done

e2fsck_status=0
e2fsck -fy "$WORK_IMAGE" || e2fsck_status=$?
if [ "$e2fsck_status" -gt 1 ]; then
    echo "Error: e2fsck failed with status $e2fsck_status" >&2
    exit "$e2fsck_status"
fi

mv -f -- "$WORK_IMAGE" "$OUTPUT"
WORK_IMAGE=
sha256sum "$OUTPUT" > "$OUTPUT.sha256"

echo "Rootfs image created: $OUTPUT"
echo "Model: $MODEL"
echo "Modules: $MODULE_ARCHIVE"
echo "Filesystem: ext4"
echo "Image size: $(stat -c %s "$OUTPUT") bytes"
echo "Checksum:   $OUTPUT.sha256"

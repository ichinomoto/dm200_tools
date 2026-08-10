#!/bin/sh

set -eu

export LC_ALL=C

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOTFS=${DM200_ROOTFS_DIR:-$SCRIPT_DIR/rootfs}
OUTPUT=${DM200_ROOTFS_IMAGE:-$SCRIPT_DIR/rootfs.img}
IMAGE_SIZE=${DM200_ROOTFS_IMAGE_SIZE:-}
LABEL=${DM200_ROOTFS_IMAGE_LABEL:-DM200ROOT}
FORCE=0

# Keep the image compact because the SD partition is expanded after writing.
# The fixed space covers filesystem metadata and a small amount of initial use.
MIN_FREE_BYTES=$((128 * 1024 * 1024))
ROUND_BYTES=$((64 * 1024 * 1024))

WORK_IMAGE=
MOUNT_DIR=
MOUNTED=0

usage()
{
    cat <<EOF
Usage: $0 [OPTIONS]

Create an ext4 image from a populated DM200 rootfs directory.

Options:
  --rootfs DIR       Source rootfs directory (default: $SCRIPT_DIR/rootfs)
  --output FILE      Output image (default: $SCRIPT_DIR/rootfs.img)
  --size SIZE        Image size understood by truncate, for example 4G
  --label LABEL      ext4 volume label (default: $LABEL)
  --force            Replace an existing output image
  --help             Show this help

Without --size, the image is sized to the rootfs usage plus 128 MiB, rounded
up to a 64 MiB boundary.  The filesystem can be expanded after writing.
EOF
}

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

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: run this script as root (for example: sudo $0)." >&2
    exit 1
fi

for command in awk dirname du e2fsck find mkfs.ext4 mount mkdir mktemp mv rm rsync rmdir sha256sum stat sync truncate umount; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command not found: $command" >&2
        exit 1
    fi
done

if [ ! -d "$ROOTFS" ]; then
    echo "Error: rootfs directory not found: $ROOTFS" >&2
    echo "       Run make_dm200_rootfs.sh first." >&2
    exit 1
fi
if [ -z "$(find "$ROOTFS" -mindepth 1 -print -quit)" ]; then
    echo "Error: rootfs directory is empty: $ROOTFS" >&2
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

mkdir -p "$(dirname "$OUTPUT")"
used_bytes=$(du -sx --apparent-size -B1 -- "$ROOTFS" | awk 'NR == 1 { print $1 }')
case "$used_bytes" in
    ''|*[!0-9]*)
        echo "Error: could not determine rootfs size" >&2
        exit 1
        ;;
esac

if [ -z "$IMAGE_SIZE" ]; then
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
    if [ "$cleanup_status" -ne 0 ]; then
        exit "$cleanup_status"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

truncate -s "$IMAGE_SIZE" "$WORK_IMAGE"
actual_size=$(stat -c %s "$WORK_IMAGE")
if [ "$actual_size" -lt "$used_bytes" ]; then
    echo "Error: image size ($actual_size bytes) is smaller than rootfs usage ($used_bytes bytes)" >&2
    exit 1
fi

mkfs.ext4 -F -m 0 -L "$LABEL" "$WORK_IMAGE"

MOUNT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dm200-rootfs-image.XXXXXX")
mount -o loop "$WORK_IMAGE" "$MOUNT_DIR"
MOUNTED=1

rsync -aHAX --numeric-ids "$ROOTFS/" "$MOUNT_DIR/"
sync
umount "$MOUNT_DIR"
MOUNTED=0
rmdir "$MOUNT_DIR"
MOUNT_DIR=

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
echo "Filesystem: ext4"
echo "Image size: $(stat -c %s "$OUTPUT") bytes"
echo "Checksum:   $OUTPUT.sha256"

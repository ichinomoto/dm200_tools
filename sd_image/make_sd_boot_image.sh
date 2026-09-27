#!/bin/sh
# Collect separately built Pomera artifacts and assemble a bootable SD image.
set -eu
export LC_ALL=C
PATH=$PATH:/usr/sbin:/sbin
export PATH

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stage_dir=
source_idb=$script_dir/../idb/idb.img
source_uboot=
source_kernel=
source_resource=
source_rootfs=
output=
force=0

usage()
{
    cat <<EOF_USAGE
Usage: sh $0 MODEL [OPTIONS]
MODEL: dm200, dm250, dm250us

The default inputs are collected from the separate build directories:
  ../idb/idb.img
  ../kernel/u-boot/uboot_MODEL.img
  ../kernel/linux/kernel_MODEL.img
  ../kernel/linux/resource_MODEL.img
  ../rootfs_script/rootfs_MODEL.img

All five inputs are copied into sd_image/MODEL (or --stage-dir) before they
are validated and written into the final image.

Options:
  --stage-dir DIR      Staging directory (default: $script_dir/MODEL)
  --idb FILE           IDB input override
  --uboot FILE         U-Boot input override
  --kernel FILE        kernel input override
  --resource FILE      resource input override
  --rootfs-image FILE  ext4 rootfs input override
  --boot-files DIR     Alias for --stage-dir
  --output FILE        Output (default: sd_MODEL.img next to this script)
  --force              Replace an existing output
  --help               Show this help

The image contains a 128 MiB raw boot area, an empty 1 GiB FAT32 p1, and the
ext4 rootfs as p2.  The target SD card needs at least 1 GiB beyond the image for
first-boot swap expansion.
EOF_USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 2
fi
case "$1" in
    -h|--help) usage; exit 0 ;;
esac
model=$1
shift
case "$model" in
    dm200|dm250|dm250us) ;;
    *) die "unsupported model: $model" ;;
esac

stage_dir=$script_dir/$model
source_uboot=$script_dir/../kernel/u-boot/uboot_${model}.img
source_kernel=$script_dir/../kernel/linux/kernel_${model}.img
source_resource=$script_dir/../kernel/linux/resource_${model}.img
source_rootfs=$script_dir/../rootfs_script/rootfs_${model}.img

while [ "$#" -gt 0 ]; do
    case "$1" in
        --stage-dir|--boot-files)
            [ "$#" -ge 2 ] || die "$1 requires a value"
            stage_dir=$2
            shift 2
            ;;
        --idb|--uboot|--kernel|--resource|--rootfs-image)
            [ "$#" -ge 2 ] || die "$1 requires a value"
            case "$1" in
                --idb) source_idb=$2 ;;
                --uboot) source_uboot=$2 ;;
                --kernel) source_kernel=$2 ;;
                --resource) source_resource=$2 ;;
                --rootfs-image) source_rootfs=$2 ;;
            esac
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] || die "--output requires a value"
            output=$2
            shift 2
            ;;
        --force)
            force=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

for tool in realpath stat od tr blkid mktemp truncate sfdisk mkfs.vfat dd cp mv rm rmdir dirname mkdir sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || die "required command not found: $tool"
done

stage_dir=$(realpath -m -- "$stage_dir")
output=$(realpath -m -- "${output:-$script_dir/sd_$model.img}")
mkdir -p "$stage_dir"

resolve_input()
{
    [ -f "$1" ] || die "required input does not exist: $1"
    realpath -e -- "$1"
}

source_idb=$(resolve_input "$source_idb")
source_uboot=$(resolve_input "$source_uboot")
source_kernel=$(resolve_input "$source_kernel")
source_resource=$(resolve_input "$source_resource")
source_rootfs=$(resolve_input "$source_rootfs")

copy_to_stage()
{
    source=$1
    destination=$2
    destination=$(realpath -m -- "$destination")
    if [ "$source" != "$destination" ]; then
        cp -f -- "$source" "$destination"
    fi
}

for input in "$source_idb" "$source_uboot" "$source_kernel" "$source_resource" "$source_rootfs"; do
    [ -f "$input" ] || die "required input does not exist: $input"
    [ "$(stat -Lc %s "$input")" -gt 0 ] || die "input is empty: $input"
    [ "$output" != "$input" ] || die "output must not overwrite an input: $input"
done

stage_idb=$stage_dir/idb.img
stage_uboot=$stage_dir/uboot_${model}.img
stage_kernel=$stage_dir/kernel_${model}.img
stage_resource=$stage_dir/resource_${model}.img
stage_rootfs=$stage_dir/rootfs_${model}.img

for destination in "$stage_idb" "$stage_uboot" "$stage_kernel" "$stage_resource" "$stage_rootfs"; do
    [ "$output" != "$(realpath -m -- "$destination")" ] ||
        die "output must not overwrite a staged input: $destination"
done

copy_to_stage "$source_idb" "$stage_idb"
copy_to_stage "$source_uboot" "$stage_uboot"
copy_to_stage "$source_kernel" "$stage_kernel"
copy_to_stage "$source_resource" "$stage_resource"
copy_to_stage "$source_rootfs" "$stage_rootfs"

idb=$stage_idb
uboot=$stage_uboot
kernel=$stage_kernel
resource=$stage_resource
rootfs=$stage_rootfs
for input in "$idb" "$uboot" "$kernel" "$resource" "$rootfs"; do
    [ -f "$input" ] || die "staged input does not exist: $input"
    [ "$(stat -Lc %s "$input")" -gt 0 ] || die "staged input is empty: $input"
    [ "$output" != "$(realpath -m -- "$input")" ] || die "output must not overwrite a staged input"
done

if [ -e "$output" ]; then
    [ -f "$output" ] || die "output is not a regular file: $output"
    [ "$force" -eq 1 ] || die "output exists; use --force to replace it: $output"
fi

mib=$((1024 * 1024))
idb_size=$(stat -Lc %s "$idb")
[ "$idb_size" -ge 620 ] && [ "$idb_size" -le $((4 * mib - 64 * 512)) ] ||
    die "IDB must fit between sector 64 and 4 MiB"
[ "$(stat -Lc %s "$uboot")" -le $((4 * mib)) ] || die "U-Boot exceeds its 8-12 MiB slot"
[ "$(stat -Lc %s "$kernel")" -le $((12 * mib)) ] || die "kernel exceeds its 12-24 MiB slot"
[ "$(stat -Lc %s "$resource")" -le $((6 * mib)) ] || die "resource exceeds its 24-30 MiB slot"
magic() { od -An -tx1 -N "$2" "$1" | tr -d ' \n'; }
[ "$(magic "$uboot" 8)" = 4c4f414445522020 ] || die "U-Boot is not a LOADER image"
[ "$(magic "$kernel" 4)" = 4b524e4c ] || die "kernel is not a KRNL image"
[ "$(magic "$resource" 4)" = 52534345 ] || die "resource is not an RSCE image"
[ "$(blkid -p -s TYPE -o value "$rootfs")" = ext4 ] || die "rootfs must be ext4"
rootfs_bytes=$(stat -Lc %s "$rootfs")
[ $((rootfs_bytes % 512)) -eq 0 ] || die "rootfs size must be sector aligned"

p1_start=262144
p1_sectors=2097152
p2_start=$((p1_start + p1_sectors))
rootfs_sectors=$((rootfs_bytes / 512))
work=$(mktemp -d "$(dirname -- "$output")/.pomera-sd.XXXXXX")
cleanup() { rm -f -- "$work/idb.img" "$work/p1.img" "$work/sd.img"; rmdir "$work"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
cp -- "$idb" "$work/idb.img"
# Set the legacy SD boot flag only in the staged copy.
printf '\001\000\000\000' | dd of="$work/idb.img" bs=1 seek=616 conv=notrunc status=none
truncate -s $(((p2_start + rootfs_sectors) * 512)) "$work/sd.img"
sfdisk "$work/sd.img" <<EOF_SFDISK
label: dos
unit: sectors

start=$p1_start,size=$p1_sectors,type=c
start=$p2_start,size=$rootfs_sectors,type=83
EOF_SFDISK
truncate -s $((p1_sectors * 512)) "$work/p1.img"
volume_label=$(printf '%sSD' "$model" | tr '[:lower:]' '[:upper:]')
mkfs.vfat -F 32 -n "$volume_label" "$work/p1.img"
# Current Pomera U-Boot uses absolute locations and does not read PARM.
dd if="$work/idb.img" of="$work/sd.img" bs=512 seek=64 conv=notrunc status=none
dd if="$uboot" of="$work/sd.img" bs=1M seek=8 conv=notrunc,sparse status=none
dd if="$kernel" of="$work/sd.img" bs=1M seek=12 conv=notrunc,sparse status=none
dd if="$resource" of="$work/sd.img" bs=1M seek=24 conv=notrunc,sparse status=none
dd if="$work/p1.img" of="$work/sd.img" bs=1M seek=$((p1_start / 2048)) conv=notrunc,sparse status=none
dd if="$rootfs" of="$work/sd.img" bs=1M seek=$((p2_start / 2048)) conv=notrunc,sparse status=none
mv -f -- "$work/sd.img" "$output"
sha256sum "$output" > "$output.sha256"
echo "Staged artifacts: $stage_dir"
echo "Created: $output"
echo "Model: $model; rootfs: $rootfs"
echo "Use an SD card with at least 1 GiB beyond this image for firstboot swap."

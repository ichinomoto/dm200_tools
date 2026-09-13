#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dm200_uboot_dir=$script_dir/dm200_uboot
rkbin_dir=$script_dir/rkbin
output=$script_dir/idb.img

clone_if_missing()
{
    name=$1
    repository=$2
    directory=$3

    if [ -e "$directory" ]; then
        if [ ! -d "$directory/.git" ]; then
            echo "Error: $name directory exists but is not a Git checkout: $directory" >&2
            exit 1
        fi
        echo "Skipping clone; $name checkout already exists: $directory"
    else
        echo "Cloning $name: $repository"
        git clone --depth 1 "$repository" "$directory"
    fi
}

for command in git dd; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command not found: $command" >&2
        exit 1
    fi
done

cd "$script_dir"
clone_if_missing dm200_uboot https://github.com/ichinomoto/dm200_uboot "$dm200_uboot_dir"
clone_if_missing rkbin https://github.com/rockchip-linux/rkbin "$rkbin_dir"

flash_data=$dm200_uboot_dir/u-boot-2014.10/tools/rk_tools/RK3128_DDR_300M_V2.04.bin
flash_boot=$dm200_uboot_dir/u-boot-2014.10/tools/rk_tools/rk312xminiloaderall.bin
mkimage=$rkbin_dir/tools/mkimage

for input in "$flash_data" "$flash_boot"; do
    if [ ! -f "$input" ]; then
        echo "Error: required input not found: $input" >&2
        exit 1
    fi
done
if [ ! -x "$mkimage" ]; then
    echo "Error: mkimage executable not found: $mkimage" >&2
    exit 1
fi

rm -f "$output"
"$mkimage" -n rk3128 -T rksd -d "$flash_data:$flash_boot" "$output"

# SD-boot flag at offset 616.
printf '\001\000\000\000' |
    dd of="$output" bs=1 seek=616 conv=notrunc status=none

echo "Created: $output"

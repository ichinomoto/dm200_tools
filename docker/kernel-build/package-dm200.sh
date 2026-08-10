#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: package-dm200 ZIMAGE DTB OUTPUT_DIR" >&2
    exit 2
fi

zimage=$1
dtb=$2
output_dir=$3
kernel_partition_size=12582912

for input_file in "$zimage" "$dtb"; do
    if [ ! -f "$input_file" ]; then
        echo "ERROR: required input does not exist: $input_file" >&2
        exit 1
    fi
done

mkdir -p "$output_dir"
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM
staging_dir=$work_dir/images
appended_zimage=$work_dir/zImage-dtb
mkdir -p "$staging_dir"

cat "$zimage" "$dtb" > "$appended_zimage"
mkkrnlimg "$appended_zimage" "$staging_dir/kernel.img"
mkkrnlimg --verify "$staging_dir/kernel.img" "$appended_zimage"

kernel_image_size=$(stat -c %s "$staging_dir/kernel.img")
if [ "$kernel_image_size" -gt "$kernel_partition_size" ]; then
    echo "ERROR: kernel.img exceeds the DM200 kernel partition" >&2
    exit 1
fi

cp "$dtb" "$staging_dir/rk3128-pomera-dm200.dtb"
(
    cd "$staging_dir"
    sha256sum kernel.img rk3128-pomera-dm200.dtb > SHA256SUMS
)

rm -f "$output_dir/resource.img"
for output_file in kernel.img rk3128-pomera-dm200.dtb SHA256SUMS; do
    mv "$staging_dir/$output_file" "$output_dir/$output_file"
done

echo "PASS: kernel.img payload contains zImage followed by the DM200 DTB"
echo "DM200 kernel image is ready in $output_dir"
echo "kernel.img: $kernel_image_size / $kernel_partition_size bytes"

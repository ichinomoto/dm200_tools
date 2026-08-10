#!/bin/sh

set -eu

usage()
{
    echo "Usage: $0 [--defconfig DEFCONFIG]"
    echo
    echo "DEFCONFIG may be a make target such as multi_v7_defconfig or"
    echo "a config file path relative to the DM200 project directory."
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/../../../.." && pwd)
host_build_dir=$script_dir/build
image_name=${DM200_KERNEL_BUILD_IMAGE:-dm200-kernel-build:trixie}
build_dir=/build/linux-6.18-dm200
image_dir=/build/dm200-images
defconfig=${DM200_KERNEL_DEFCONFIG:-multi_v7_defconfig}

while [ "$#" -gt 0 ]; do
    case $1 in
        --defconfig)
            if [ "$#" -lt 2 ]; then
                echo "Error: --defconfig requires an argument" >&2
                usage >&2
                exit 2
            fi
            defconfig=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case $defconfig in
    /*|../*|*/../*|*/..)
        echo "Error: config file paths must be relative to $project_dir" >&2
        exit 2
        ;;
    */*)
        if [ ! -f "$project_dir/$defconfig" ]; then
            echo "Error: config file not found: $project_dir/$defconfig" >&2
            exit 2
        fi
        container_defconfig=/workspace/$defconfig
        ;;
    *)
        container_defconfig=$defconfig
        ;;
esac

docker build \
    --tag "$image_name" \
    "$script_dir"

mkdir -p "$host_build_dir/linux-6.18-dm200"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    --env KBUILD_BUILD_USER=builder \
    --env KBUILD_BUILD_HOST=dm200-container \
    --env DM200_KERNEL_DEFCONFIG="$container_defconfig" \
    --volume "$project_dir:/workspace" \
    --volume "$host_build_dir:/build" \
    --workdir /workspace/git/linux \
    "$image_name" \
    sh -ec "
        case \"\$DM200_KERNEL_DEFCONFIG\" in
            /*)
                cp \"\$DM200_KERNEL_DEFCONFIG\" $build_dir/.config
                make O=$build_dir olddefconfig
                ;;
            *)
                make O=$build_dir \"\$DM200_KERNEL_DEFCONFIG\"
                ;;
        esac
        grep -qx 'CONFIG_ARM_APPENDED_DTB=y' $build_dir/.config
        make O=$build_dir -j\"\$(nproc)\" \\
            zImage rockchip/rk3128-pomera-dm200.dtb
        package-dm200 \\
            $build_dir/arch/arm/boot/zImage \\
            $build_dir/arch/arm/boot/dts/rockchip/rk3128-pomera-dm200.dtb \\
            $image_dir
    "

echo "Kernel: $host_build_dir/linux-6.18-dm200/arch/arm/boot/zImage"
echo "DTB:    $host_build_dir/linux-6.18-dm200/arch/arm/boot/dts/rockchip/rk3128-pomera-dm200.dtb"
echo "Images: $host_build_dir/dm200-images"

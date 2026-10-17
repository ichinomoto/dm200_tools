# Pomera DM200 / DM250 / DM250US tools

[日本語](readme.md) | English

Build and image-creation tools for booting Linux from an SD card on Pomera devices.
Linux and U-Boot are obtained from separate repositories; this repository builds the rootfs and SD images.

Supported model names are `dm200`, `dm250` and `dm250us`. The examples below use `dm250`.

## Directories

| Location | Purpose |
| --- | --- |
| [kernel/](kernel/) | Linux / U-Boot checkout and updates, shared Docker build environment |
| [rootfs_script/](rootfs_script/) | Debian / Ubuntu armhf rootfs, model-specific ext4 images and target overlays |
| [idb/](idb/) | RK3128 SD boot IDB generation |
| [sd_image/](sd_image/) | Artifact collection, SD images, distribution ZIP archives and checksums |
| [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) | Third-party licenses, including firmware |
| [initramfs/](initramfs/), [installer/](installer/) | Legacy installation tools; not used by the current workflow |

## Host environment

A Linux host, Git, a working Docker Engine (or an equivalent build environment),
and network access for APT, Git and firmware downloads are required.
Rootfs creation and ext4 image creation run on the host with root privileges.

## 1. Build Linux / U-Boot

```sh
cd kernel
./docker_builder.sh
```

On the first run, the script clones Linux and U-Boot. Existing clones are updated
to their remote branches with a fast-forward merge. Local changes are preserved,
but conflicts, diverged history, or a branch or origin mismatch stop the update.
The script then builds the shared toolchain Docker image and opens an interactive shell.

Default sources:

- Linux: `https://github.com/ichinomoto/linux`, branch `pomera/linux-6.18.y`
- U-Boot: `https://github.com/ichinomoto/u-boot`, branch `pomera/v2026.07`
- Host checkout directories: `kernel/linux`, `kernel/u-boot`

Run inside the container:

```sh
cd /workspace/u-boot
./make_uboot_image.sh dm250

cd /workspace/linux
./make_kernel.sh dm250
```

`kernel_<model>.img` contains only the zImage wrapped in Rockchip KRNL format.
`resource_<model>.img` contains the separate DTB in RSCE format.

The following files are generated:

- `u-boot/uboot_dm250.img`
- `linux/kernel_dm250.img`
- `linux/resource_dm250.img`
- `linux/modules_dm250.tar.gz`

## 2. Create the rootfs

The default is Debian 13 (trixie), including Xorg / Xfce.

```sh
cd rootfs_script
sudo ./make_rootfs.sh
```

The output directory is `rootfs`. Add `--no-x` if X is not needed.

To use Ubuntu 26.04:

```sh
sudo ./make_rootfs.sh --distro ubuntu --suite 26.04
```

This creates `rootfs-ubuntu-resolute`.
Shared configuration is in [rootfs_script/rootfs_config.sh](rootfs_script/rootfs_config.sh),
and files added to the target are in [rootfs_script/files/](rootfs_script/files/).

## 3. Create a model-specific rootfs image

```sh
sudo ./make_rootfs_image.sh dm250
```

Using the `rootfs` created in step 2, this installs the modules from
`kernel/linux/modules_dm250.tar.gz` and generates `rootfs_dm250.img` and `.sha256`.
The source rootfs remains common to all models; model-specific modules are installed
into the generated image. Build the matching kernel module archive first.

For Ubuntu, specify its source directory:

```sh
sudo ./make_rootfs_image.sh dm250 --rootfs rootfs-ubuntu-resolute
```

The image size is calculated from disk usage by default.
Use an option such as `--size 4G` when a fixed size is required.

## 4. Create the IDB

```sh
cd idb
./make_idb.sh
```

The script clones `dm200_uboot` and `rkbin` only if they are missing, then generates
`idb.img`. Existing checkouts are not updated automatically. It uses the legacy
U-Boot DDR/miniloader binaries and `rkbin/tools/mkimage`.

## 5. Create the SD image and distribution ZIP

```sh
cd sd_image
sh ./make_sd_boot_image.sh dm250
```

The script collects the IDB, model-specific U-Boot, kernel, resource and rootfs
created through step 4, copies them into `sd_image/dm250/`, and combines them into
an SD image named `sd_dm250.img`.

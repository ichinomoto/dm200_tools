# Debian 13 rootfs for DM200

make_dm200_rootfs.sh creates an armhf Debian 13 (trixie) root filesystem
for the DM200.  The script uses the official debootstrap --foreign flow and
qemu-arm-static; the old qemu-debootstrap wrapper is no longer required.

## Host packages

On a Debian build host, install the bootstrap tools first:

    sudo apt install debootstrap qemu-user-static binfmt-support ca-certificates wget

The script must be run as root because debootstrap and the target chroot
create device-independent root-owned files.

## Build

From this directory:

    sudo ./make_dm200_rootfs.sh

The default output is rootfs_script/rootfs.  An existing non-empty output
directory is rejected.  To intentionally replace it:

    sudo ./make_dm200_rootfs.sh --clean

The default image includes the console tools, Japanese locale/input method,
networking, Bluetooth utilities, Xorg and Xfce.  midori was removed before
trixie, so netsurf-gtk is used as the lightweight browser instead.  Use
--no-x for a console-only image.

The normal user is pomera, and the build prompts for its password.  For an
unattended build, pass either a clear-text password or a crypt(3) hash:

    sudo DM200_USER_PASSWORD='change-me' ./make_dm200_rootfs.sh
    sudo DM200_USER_PASSWORD_HASH='$6$...' ./make_dm200_rootfs.sh

The password is supplied to the temporary chroot and is not stored in this
repository.

## Kernel modules

Kernel modules are not copied unless `--kernel-modules` is specified.  Install
modules from the current Linux 6.18 kernel build first, then pass the directory
containing the release subdirectory:

    make -C git/linux O=/path/to/kernel-build \
      modules_install INSTALL_MOD_PATH=/tmp/dm200-modules
    sudo ./make_dm200_rootfs.sh \
      --kernel-modules /tmp/dm200-modules/lib/modules

## Optional inputs

- --no-firmware skips the Armbian firmware downloads.
- --firmware-dir DIR copies the same firmware files from a local directory.
- DM200_ROOTFS_DIR, DM200_ROOTFS_CACHE_DIR, DM200_DEBIAN_MIRROR,
  DM200_DEBIAN_SECURITY_MIRROR, and DM200_DEBIAN_SUITE override the output,
  cache, mirrors, and suite.
- DM200_USER_NAME and DM200_HOSTNAME override the default account and
  hostname (pomera).

The root filesystem keeps the DM200 partition layout used by the current
kernel command line: /dev/mmcblk1p2 is /, /dev/mmcblk1p1 is /mnt/sd, and
/dev/mmcblk1p3 is swap.

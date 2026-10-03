# DM200 third-party notices

The Debian/Ubuntu root filesystem includes third-party wireless firmware and
regulatory data. These files are not part of the Linux kernel source and remain
subject to their own terms when they are included in `sd.img`.

## Broadcom/Armbian wireless firmware

Wi-Fi binaries and CLM data are installed through Debian's `firmware-brcm80211`
or Ubuntu 26.04's `linux-firmware-broadcom-wireless`. Their installed copyright
files are retained under `/usr/share/doc/PACKAGE/copyright`.

Board NVRAM and Bluetooth firmware are copied from the pinned Armbian
repository without modifying their contents, for example:

- `ap6210/nvram.txt` -> `brcm/brcmfmac43362-sdio.txt`
- `ap6210/bcm20710a1.hcd` -> `brcm/BCM20702A1.hcd`

The legacy RK901a2 Wi-Fi binary is no longer renamed over the packaged
BCM43362 binary. This lets package updates replace the running firmware.

Armbian does not provide one blanket license for every file in its firmware
repository; the license and redistribution conditions of each file apply.
The repository also notes that some files are proprietary. See the [Armbian
firmware README](https://github.com/armbian/firmware/blob/2a9e1c19460401443267926181191d57e3ff175d/README.md) and
the source/sha256 record for all downloaded files in
[`rootfs_script/files/usr/share/doc/dm200-firmware/SOURCES.md`](../rootfs_script/files/usr/share/doc/dm200-firmware/SOURCES.md).

The Broadcom license text used for the Broadcom firmware is included at
[`LICENCE.broadcom_bcm43xx`](../rootfs_script/files/usr/share/doc/dm200-firmware/LICENCE.broadcom_bcm43xx).
It permits redistribution of complete, unmodified software only for use with
the corresponding Broadcom integrated-circuit product and requires a copy of
the agreement to accompany the software. The DM200 files are used only with
the DM200's Broadcom wireless hardware and are copied without modification.

## wireless-regdb

`regulatory.db` is the wireless-regdb regulatory database. Its source and
copyright notice are documented by the Debian package at
`/usr/share/doc/wireless-regdb/copyright`; the database is distributed under
the ISC license. The matching `regulatory.db.p7s` is a signature file and
must remain paired with the database. Do not modify either file. See the
[wireless-regdb documentation](https://wireless.docs.kernel.org/en/latest/en/developers/regulatory/wireless-regdb.html).

## Distribution note

This notice applies to the firmware included in `sd.img`. The firmware files
are kept out of the tracked Linux source tree and are installed by the rootfs
build script. If the firmware source or version changes, update the source and
sha256 records and review the applicable license terms again.

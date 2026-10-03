# Pomera wireless firmware sources

The common rootfs supplies wireless firmware for DM200, DM250 and DM250US.
Wi-Fi binaries and the BCM43430 A1 CLM blob are installed by APT; they are
not overwritten by the builder. Board NVRAM and Bluetooth HCD files use the
pinned Armbian revision `2a9e1c19460401443267926181191d57e3ff175d`.

## Distribution Wi-Fi packages

- Debian: `firmware-brcm80211` from `non-free-firmware`.
  <https://packages.debian.org/trixie/firmware-brcm80211>
- Ubuntu 26.04: `linux-firmware-broadcom-wireless`.
  <https://packages.ubuntu.com/resolute/linux-firmware-broadcom-wireless>

The package supplies `brcmfmac43362-sdio.bin`, `brcmfmac4329-sdio.bin`,
`brcmfmac43430a0-sdio.bin`, `brcmfmac43430-sdio.bin`, and
`brcmfmac43430-sdio.clm_blob` under `/lib/firmware/brcm` (or the merged
`/usr/lib/firmware` path). Package symlinks to Cypress firmware are preserved.
Ubuntu supplies compressed `.zst` files; the Pomera kernel needs
`CONFIG_FW_LOADER_COMPRESS=y` and `CONFIG_FW_LOADER_COMPRESS_ZSTD=y`.
These files are loaded at runtime, not embedded in the kernel image.
APT updates remain effective because no older raw copies shadow them.

The version used by an image follows the selected distribution repository.
Record it with `dpkg-query -W firmware-brcm80211` on Debian or
`dpkg-query -W linux-firmware-broadcom-wireless` on Ubuntu. The installed
package copyright under `/usr/share/doc/PACKAGE/copyright` documents its
firmware licenses. `--no-firmware` skips the package and supplemental files.

## Armbian NVRAM and Bluetooth firmware

Source: <https://github.com/armbian/firmware/tree/2a9e1c19460401443267926181191d57e3ff175d>

| Image path under `/lib/firmware/brcm` | Source path | SHA256 or pinned revision |
| --- | --- | --- |
| `brcmfmac43362-sdio.txt` | `ap6210/nvram.txt` | `d42dc00586a2948373a06fbf285e5e607b528de42a663c9d96d9434def154cb9` |
| `brcmfmac4329-sdio.txt` | `brcm/brcmfmac4329-sdio.txt` | `2a9e1c19460401443267926181191d57e3ff175d` |
| `brcmfmac43430a0-sdio.txt` | `brcm/brcmfmac43430a0-sdio.txt` | `2a9e1c19460401443267926181191d57e3ff175d` |
| `brcmfmac43430-sdio.txt` | `brcm/brcmfmac43430-sdio.txt` | `2a9e1c19460401443267926181191d57e3ff175d` |
| `BCM20702A1.hcd` | `ap6210/bcm20710a1.hcd` (renamed copy) | `d08f7a30b9412e2336d3de4be2bf73b680c561f095632eef897c04626e1d35c1` |
| `BCM4343A0.hcd` | `brcm/BCM4343A0.hcd` | `2a9e1c19460401443267926181191d57e3ff175d` |
| `BCM43430A1.hcd`, `BCM4343A1.hcd` | `ap6212/bcm43438a1.hcd` (renamed copies) | `d396912aa4efa7e0ea93dc6b63b1088619b59676ab53404d14fe79f5c71a5da0` |

The builder also retains the original Bluetooth/NVRAM names under
`/opt/etc/firmware`: `bcm20710a1.hcd`, `BCM43438A0.hcd`,
`BCM43438A1.hcd`, `BCM4343A1.hcd`, `nvram_AP6210.txt`, and `nvram_AP6212.txt`.
The AP6212 A0 HCD and AP6212 NVRAM are from `ap6212/bcm43438a0.hcd` and
`ap6212/nvram.txt` at the same pinned revision. Legacy `fw_RK901a2*` and
`fw_bcm43438a1*` Wi-Fi binaries are no longer downloaded or copied.
`--firmware-dir` overrides only these supplemental inputs; Wi-Fi binaries
still come from APT.

Armbian files have individual copyright and redistribution terms. See its
[README](https://github.com/armbian/firmware/blob/2a9e1c19460401443267926181191d57e3ff175d/README.md)
and the included `LICENCE.broadcom_bcm43xx`. Preserve the applicable notices
when distributing an image.

## wireless-regdb

The rootfs is built with Debian's `wireless-regdb` package. `initial_settings.sh`
explicitly selects the upstream database/signature pair (`regulatory.db-upstream`
and `regulatory.db.p7s-upstream`) using `update-alternatives --set regulatory.db`.
The signature is updated through the same alternatives group. This is required
because our mainline kernel trusts the upstream signing keys, not Debian's key.
Earlier builds did not select this alternative despite this document claiming
they did, and could therefore reject country changes.

The kernel's runtime regulatory database inputs are:

| Image path | Package/source file | SHA256 |
| --- | --- | --- |
| `regulatory.db` | `regulatory.db-upstream` | `2fb33ca0074db573e05ef7dd50bb45b63c0ff98b7e852e1105ebad536fae8e6b` |
| `regulatory.db.p7s` | `regulatory.db.p7s-upstream` | `c941c08f51c93e46722293b85631604c3740d86c3de0c75f79aef50d2e919179` |

The package copyright and ISC license are installed at
`/usr/share/doc/wireless-regdb/copyright`. The signature file must stay
paired with the database and neither file should be modified.

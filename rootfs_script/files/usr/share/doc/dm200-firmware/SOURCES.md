# DM200 firmware sources

The files below are the inputs used for the current DM200 Wi-Fi/kernel build.
The SHA256 values must be updated if the firmware source or package version is
changed.

## Armbian firmware

Source repository: <https://github.com/armbian/firmware>

| Image path | Source path | SHA256 |
| --- | --- | --- |
| `/lib/firmware/brcm/brcmfmac43362-sdio.bin` | `rkwifi/fw_RK901a2.bin` | `1ef6b0a75d894721c12456e79af2700e939691183aad4de8aed4f77245fa2eb3` |
| `/lib/firmware/brcm/brcmfmac43362-sdio.txt` | `ap6210/nvram.txt` | `d42dc00586a2948373a06fbf285e5e607b528de42a663c9d96d9434def154cb9` |

The same two files are also staged into `kernel.img` through
`CONFIG_EXTRA_FIRMWARE`; only the destination path/name changes.

The Armbian repository contains files with different licensing conditions.
The exact terms for each downloaded file must be respected when redistributing
an image. The Armbian README is at
<https://github.com/armbian/firmware/blob/master/README.md>.

The rootfs also keeps the following Armbian files under `/opt/etc/firmware`:

| Image path | Source path | SHA256 |
| --- | --- | --- |
| `BCM43438A1.hcd` | `ap6212/bcm43438a1.hcd` | `d396912aa4efa7e0ea93dc6b63b1088619b59676ab53404d14fe79f5c71a5da0` |
| `bcm20710a1.hcd` | `ap6210/bcm20710a1.hcd` | `d08f7a30b9412e2336d3de4be2bf73b680c561f095632eef897c04626e1d35c1` |
| `fw_RK901a2_apsta.bin` | `rkwifi/fw_RK901a2_apsta.bin` | `38bb15aca036009d5d98930d617bd81142a157d2f516003e332d6396f223f982` |
| `fw_RK901a2_p2p.bin` | `rkwifi/fw_RK901a2_p2p.bin` | `4c5e9acc45ed1a9cfc980647e3e13001378d16598b077fe243e8aa98160cd905` |
| `fw_bcm43438a1.bin` | `ap6212/fw_bcm43438a1.bin` | `10be231737a7e2f6badd3bc0034f8ec91dc9d8c747276db059747a2f52b25468` |
| `fw_bcm43438a1_mfg.bin` | `ap6212/fw_bcm43438a1_mfg.bin` | `b1b60f741a19fef73a1845d071d32b6b192c94a2b3eca64406c815e0145500ce` |
| `nvram_AP6210.txt` | `ap6210/nvram.txt` | `d42dc00586a2948373a06fbf285e5e607b528de42a663c9d96d9434def154cb9` |
| `nvram_AP6212.txt` | `ap6212/nvram.txt` | `f7ab3c146da63cd41ab3bc3b07b748704b606372b36930652eef3a1507ae8d99` |

## wireless-regdb

The rootfs is built with Debian's `wireless-regdb` package. The current build
uses the upstream database/signature pair (`regulatory.db-upstream` and
`regulatory.db.p7s-upstream`) for the kernel's compiled-in firmware:

| Image path | Package/source file | SHA256 |
| --- | --- | --- |
| `regulatory.db` | `regulatory.db-upstream` | `2fb33ca0074db573e05ef7dd50bb45b63c0ff98b7e852e1105ebad536fae8e6b` |
| `regulatory.db.p7s` | `regulatory.db.p7s-upstream` | `c941c08f51c93e46722293b85631604c3740d86c3de0c75f79aef50d2e919179` |

The package copyright and ISC license are installed at
`/usr/share/doc/wireless-regdb/copyright`. The signature file must stay
paired with the database and neither file should be modified.

#!/bin/sh

#update file header 4096B
#0x00000000 - 0x00000FFF
dd if=$1 of=0_header.bin bs=1k count=4

#initramfs boot p4
#0x00001000 - 0x02000FFF 32MB(33554432)
dd if=$1 of=1_boot.bin bs=1k skip=4 count=32768

#WARP warp p5
#0x02001000 - 0x22000FFF 512MB(536870912)
dd if=$1 of=2_warp.bin bs=1k skip=32772 count=524288

#ext4 ro_data p6
#0x22001000 - 0x32000FFF 256MB(268435456)
dd if=$1 of=3_ro_data.bin bs=1k skip=557060 count=262144

#ext4 user_lib p12
#0x32001000 - 0x34000FFF 32MB(268435456)
dd if=$1 of=4_user_lib.bin bs=1k skip=819204 count=32768

#kernel kernel p2
#0x34001000 - 0x34C00FFF 12MB(12582912)
dd if=$1 of=5_kernel.bin bs=1k skip=851972 count=12288

#dtb resource p3
#0x34C01000 - 0x34C00FFF 6MB(6291456)
dd if=$1 of=6_resource.bin bs=1k skip=864260

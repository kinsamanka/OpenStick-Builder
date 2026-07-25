#!/bin/sh -e

# package rootfs (512MB ext4, label=rootfs)
rm -f rootfs.raw
mkdir -p files mnt

# create root img
truncate -s 536870912 rootfs.raw
mkfs.ext4 -L rootfs rootfs.raw
mount rootfs.raw mnt
tar xpf alpine_rootfs.tgz -C mnt --exclude='./root/*' --exclude='./dev/*'

umount mnt

# create sparse android image
img2simg rootfs.raw files/rootfs.bin

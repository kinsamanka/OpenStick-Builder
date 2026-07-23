#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}

# ============================================================
# Only create rootfs image (boot.img comes from flashing package)
# ============================================================
rm -f rootfs.raw
mkdir -p files mnt

# create root img (512MB ext4, partition label rootfs)
truncate -s 536870912 rootfs.raw
mkfs.ext4 -L rootfs rootfs.raw
mount rootfs.raw mnt
tar xpf alpine_rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*'
umount mnt

# create sparse android image
img2simg rootfs.raw files/alpine_rootfs.bin

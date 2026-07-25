#!/bin/sh -e

echo "Install dependencies\n"
scripts/install_deps.sh

echo "\nCopy prebuilt firmware\n"
scripts/extract_fw.sh

echo "\nCreate rootfs\n"
scripts/alpine_rootfs.sh

echo "\nCreate rootfs image\n"
scripts/build_images.sh

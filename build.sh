#!/bin/sh -e

echo "Install dependencies"
scripts/install_deps.sh

echo "Copy prebuilt firmware"
scripts/extract_fw.sh

echo "Create rootfs"
scripts/alpine_rootfs.sh

echo "Create images"
scripts/build_images.sh

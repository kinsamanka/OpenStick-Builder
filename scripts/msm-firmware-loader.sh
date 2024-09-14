#!/bin/sh
# SPDX-License-Identifier: MIT

#
# This script is responsible for loading firmware blobs from firmware
# partitions on qcom devices. It will make a dir in tmp, mount all of the
# interesting partitions there and then symlink blobs to a single dir that can
# be then provided to the kernel. (At this time only single additional
# directory can be provided)
#
# This script attempts to load everything at runtime and be as generic
# as possible between the target devices: It should allow a single rootfs
# to be used on multiple different devices as long as all the blobs
# are present on dedicated partitions.
# (Usually the case, Samsung devices ship all blobs, other devices may miss
# venus but that still allows for WiFi and modem to work)
#

# Get the slot suffix for A/B devices.
# If qbootctl is available query the active slot using that, otherwise rely on
# the kernel cmdline to contain the slot suffix.
# On non-A/B devices the return value will be empty.
# https://source.android.com/docs/core/architecture/bootloader/updating#slots
ab_get_slot() {
	if command -v qbootctl > /dev/null; then
		ab_slot_suffix=$(qbootctl -a | grep -o 'Active slot: ..' | cut -d ":" -f2 | xargs) || :
	else
		ab_slot_suffix=$(grep -o 'androidboot\.slot_suffix=..' /proc/cmdline |  cut -d "=" -f2) || :
	fi
	echo "$ab_slot_suffix"
}

# Configurations:

# List of partitions to be mounted and inspected for blobs.
FW_PARTITIONS="
	apnhlos
	bluetooth
	modem$(ab_get_slot)
	persist
"

# Base directory to be used to unfold the partitions into.
BASEDIR="/lib/firmware/msm-firmware-loader"

# Preparations:

# This script is intended to run before udev. This means that writeable fs
# may not be available yet. Since this script only creates symlinks, it
# uses tmpfs to work around the early-run limitations as well as to reduce
# disk wear slightly.
mount -o mode=755,nodev,noexec,nosuid -t tmpfs none "$BASEDIR"

mkdir "$BASEDIR/mnt"
mkdir "$BASEDIR/target"

# Scanning and mounting partitions we're interested in:

# /dev/disk/by-partlabel symlinks don't exist yet, scan sysfs for names instead
for part in /sys/block/mmcblk*/mmcblk*p*
do
	DEVNAME="$(grep DEVNAME "$part"/uevent | sed 's/DEVNAME=//g')"
	PARTNAME="$(grep PARTNAME "$part"/uevent | sed 's/PARTNAME=//g')"

	if [ -z "${FW_PARTITIONS##*"$PARTNAME"*}" ] && [ -n "$PARTNAME" ]
	then
		mkdir "$BASEDIR/mnt/$PARTNAME"
		mount -o ro,nodev,noexec,nosuid \
			"/dev/$DEVNAME" "$BASEDIR/mnt/$PARTNAME"
	fi
done

# Linking blobs from all partitions:

# Backup the preselected path, link all of the installed blobs.
# This is needed for devices that require blobs either not present
# on the partitions (e.g. venus on many msm8916 devices) or if
# the device has secure-boot disabled and can run newer blobs.
EXTRA_PATH="$(cat /sys/module/firmware_class/parameters/path)"

if [ -d "$EXTRA_PATH" ]
then
	for blob in "$EXTRA_PATH"/*
	do
		if ! [ -e "$blob" ]; then break; fi
		ln -s "$blob" "$BASEDIR/target/$(basename "$blob")"
	done
fi

# Scan through mounted partitions and symlink all of the blobs.
# This loop ignores blobs with names already present in the
# target to allow preinstalled blobs to override ones in the partitions.
for blob in "$BASEDIR"/mnt/*/image/*
do
	BLOBBASE="${blob##*/}"
	BLOBBASE="${BLOBBASE%.*}"

	# Skip blob prefix if it's already present.
	for prefix in "$BASEDIR/target/$BLOBBASE."*
	do
		if [ -e "$prefix" ]; then continue 2; fi
	done

	for part in "$BASEDIR"/mnt/*/image/"$BLOBBASE"*
	do
		ln -s "$part" "$BASEDIR/target/$(basename "$part")"
	done
done

# Check WCNSS_qcom_wlan_nv.bin in persist partition
if [ -f "$BASEDIR"/mnt/persist/WCNSS_qcom_wlan_nv.bin ]
then
	ln -s "$BASEDIR"/mnt/persist/WCNSS_qcom_wlan_nv.bin "$BASEDIR"/target/WCNSS_qcom_wlan_nv.bin
fi

# Fixup the directory structure:

# venus (video encoder/decoder) blobs are expected to be in a subdir.
# Re-link the blobs if the venus firmware wasn't already preinstalled.
# Different platforms expect firmware in different subdirs
# (as in linux-firmware-qcom) so the venus dir is duplicated multiple times
# under possible names for the script to be generic without complex detection.

if [ -f "$BASEDIR/target/venus.mdt" ] && ! [ -d "$BASEDIR/target/qcom" ]
then
	mkdir -p "$BASEDIR/target/qcom/venus-x"
	for part in "$BASEDIR"/target/venus.*
	do
		ln -s "$part" "$BASEDIR/target/qcom/venus-x/$(basename "$part")"
	done
fi

VENUS_DIRS="
	venus-1.8
	venus-3.0
	venus-4.2
	venus-4.4
	venus-5.2
	venus-5.4
	vpu-1.0
	vpu-2.0
"

for vdir in $VENUS_DIRS
do
	if ! [ -d "$BASEDIR/target/qcom/$vdir" ] && [ -f "$BASEDIR/target/venus.mdt" ]
	then
		ln -s "$BASEDIR/target/qcom/venus-x" \
			"$BASEDIR/target/qcom/$vdir"
	fi
done

# WCNSS_qcom_wlan_nv.bin needs to be relocated too
if [ -h "$BASEDIR"/target/WCNSS_qcom_wlan_nv.bin ]
then
	if ! [ -f "$BASEDIR"/target/wlan/prima/WCNSS_qcom_wlan_nv.bin ]
	then
		mkdir -p "$BASEDIR"/target/wlan/prima
		ln -s "$BASEDIR"/target/WCNSS_qcom_wlan_nv.bin "$BASEDIR"/target/wlan/prima/
	fi
fi

# Devices with ath10k wcn3990 wifi/bt have bluetooth firmware on a separate
# "bluetooth" partition. Files from it need to be placed into qca/ subdir.
# Check if bluetooth partition was mounted, and if so, link files into qca/
if [ -d "$BASEDIR"/mnt/bluetooth ]
then
	mkdir -p "$BASEDIR"/target/qca
	for btblob in "$BASEDIR"/mnt/bluetooth/image/*
	do
		ln -s "$btblob" "$BASEDIR"/target/qca/
	done
fi

# Some kernel versions expect .mbn instead of legacy .mdt
# Symlink these files together, the kernel can autodetect the type.
find "$BASEDIR"/target/ \
	-name '*.mdt' \
	-exec sh -c 'ln -s $0 ${0%.mdt}.mbn' {} \;

# Set the new custom firmware path:
printf "%s" "$BASEDIR/target" > /sys/module/firmware_class/parameters/path


#!/bin/sh -e

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Please provide an argument: thwc, yiming, or zhihe"
    exit 1
fi

# Determine the value of LK2ND_COMPATIBLE based on the argument
case $1 in
    thwc)
        LK2ND_COMPATIBLE="thwc,ufi001c"
        ;;
    yiming)
        LK2ND_COMPATIBLE="yiming,uz801-v3"
        ;;
    zhihe)
        LK2ND_COMPATIBLE="zhihe,various"
        ;;
    *)
        echo "Invalid argument. Valid options are: thwc, yiming, zhihe"
        exit 1
        ;;
esac

# Continue with the make command
make -C src/qhypstub CROSS_COMPILE=aarch64-linux-gnu-

# patch to reduce mmc speed as some boards have intermittent failures when
# inititalizing the mmc (maybe due to using old/recycled flash chips)
echo 'DEFINES += USE_TARGET_HS200_CAPS=1' >> src/lk2nd/project/lk1st-msm8916.mk

# Generate the make command with the appropriate LK2ND_COMPATIBLE
make -C src/lk2nd LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" LK2ND_COMPATIBLE="$LK2ND_COMPATIBLE" \
    TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916

# test sign
mkdir -p files
src/qtestsign/qtestsign.py hyp src/qhypstub/qhypstub.elf \
    -o files/hyp.mbn
src/qtestsign/qtestsign.py aboot src/lk2nd/build-lk1st-msm8916/emmc_appsboot.mbn \
    -o files/aboot.mbn

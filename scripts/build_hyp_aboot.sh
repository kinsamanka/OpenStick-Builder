#!/bin/sh -e

git apply --directory=src/lk2nd/ src/patch/*patch || true

make -C src/qhypstub CROSS_COMPILE=aarch64-linux-gnu-

make -C src/lk2nd LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" LK2ND_COMPATIBLE="yiming,uz801-v3" \
    TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916

# test sign
mkdir -p files
src/qtestsign/qtestsign.py hyp src/qhypstub/qhypstub.elf \
    -o files/hyp.mbn
src/qtestsign/qtestsign.py aboot src/lk2nd/build-lk1st-msm8916/emmc_appsboot.mbn \
    -o files/aboot.mbn

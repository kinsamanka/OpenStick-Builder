#!/bin/sh -e

PREBUILT=${PREBUILT=$(pwd)/prebuilt/uz801}

mkdir -p files

# Copy low-level firmware from prebuilt
cp ${PREBUILT}/gpt_both0.bin files/
cp ${PREBUILT}/aboot.bin files/
cp ${PREBUILT}/hyp.mbn files/
cp ${PREBUILT}/rpm.mbn files/
cp ${PREBUILT}/sbl1.mbn files/
cp ${PREBUILT}/tz.mbn files/

# Copy boot.img as-is (DO NOT MODIFY)
cp ${PREBUILT}/boot.img files/

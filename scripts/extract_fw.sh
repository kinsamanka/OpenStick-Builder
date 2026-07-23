#!/bin/sh -e

export DEVICE=device
export PREBUILT=$(pwd)/prebuilt/${DEVICE}

mkdir -p files

# ============================================================
# Copy prebuilt low-level firmware
# ============================================================
echo "Copying prebuilt firmware..."

cp ${PREBUILT}/firmware/gpt_both0.bin  files/
cp ${PREBUILT}/firmware/aboot.bin      files/
cp ${PREBUILT}/firmware/hyp.mbn        files/
cp ${PREBUILT}/firmware/rpm.mbn        files/
cp ${PREBUILT}/firmware/sbl1.mbn       files/
cp ${PREBUILT}/firmware/tz.mbn         files/

echo "Done copying firmware to files/"
ls -la files/

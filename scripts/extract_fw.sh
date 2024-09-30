#!/bin/sh -e

TMPDIR=$(mktemp -d)

mkdir -p files

# create GPT
truncate -s 179323904 ${TMPDIR}/gpt.img

cat << EOF | sfdisk ${TMPDIR}/gpt.img
label: gpt
label-id: DB708ACF-2E04-8DE2-BAFE-30C9B26444C5
unit: sectors
first-lba: 34
last-lba: 350208
sector-size: 512

gpt.img1 : start=        4096, size=           2, type=57B90A16-22C9-E33B-8F5D-0E81686A68CB, uuid=89BEF928-6B3F-432E-970E-46926F6BD579, name="fsc"
gpt.img2 : start=        4098, size=        3072, type=638FF8E2-22C9-E33B-8F5D-0E81686A68CB, uuid=2B772340-E0F0-4A95-B652-27ADE619EF14, name="fsg"
gpt.img3 : start=        7170, size=      131072, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=709AEC75-FFB4-4218-9A2E-A38C9D689D6D, name="modem"
gpt.img4 : start=      138242, size=        3072, type=EBBEADAF-22C9-E33B-8F5D-0E81686A68CB, uuid=D747B414-92EA-4098-AA56-0ED0AAB1F6DC, name="modemst1"
gpt.img5 : start=      141314, size=        3072, type=0A288B1F-22C9-E33B-8F5D-0E81686A68CB, uuid=057F46B4-9F89-4AA4-9A60-1735B4E2DB4B, name="modemst2"
gpt.img6 : start=      144386, size=       65536, type=6C95E238-E343-4BA8-B489-8681ED22AD0B, uuid=ACD4F30F-6A99-42B2-9262-A3FECEB2B46B, name="persist"
gpt.img7 : start=      209922, size=          32, type=303E6AC3-AF15-4C54-9E9B-D9A8FBECF401, uuid=DD07C606-826C-4B5E-BE75-F5FCAA91E623, name="sec"
gpt.img8 : start=      209954, size=        1024, type=E1A6A689-0C8D-4CC6-B4E8-55A4320FBD8A, uuid=CB49D0D3-C49B-4586-986C-BDADBF545FEF, name="hyp"
gpt.img9 : start=      210978, size=        1024, type=098DF793-D712-413D-9D4E-89D711772228, uuid=B5154BA2-C18D-4A17-A8CD-97EEDC0BEF31, name="rpm"
gpt.img10 : start=      212002, size=        1024, type=DEA0BA2C-CBDD-4805-B4F9-F428251C3E98, uuid=B166535F-4B99-48F6-AA77-16F27669FD2F, name="sbl1"
gpt.img11 : start=      213026, size=        2048, type=A053AA7F-40B8-4B1C-BA08-2F68AC71A4F4, uuid=A983B7C4-FC3A-4F88-823E-91D5DB06337F, name="tz"
gpt.img12 : start=      215074, size=        2048, type=400FFDCD-22E0-47E7-9A23-F16ED9382388, uuid=22675009-60A3-401F-8D3F-44CD32ED394C, name="aboot"
gpt.img13 : start=      217122, size=      131072, type=20117F86-E985-4357-B9EE-374BC1D8487D, uuid=80780B1D-0FE1-27D3-23E4-9244E62F8C46, name="boot"
gpt.img14 : start=      348194, size=        2015, type=1B81E7E6-F50D-419B-A739-2AEEF8DA3335, uuid=A7AB80E8-E9D1-E8CD-F157-93F69B1D141E, name="rootfs"
EOF

# create fastboot compatible partition image
# primary gpt
dd if=${TMPDIR}/gpt.img of=files/gpt_both0.bin bs=512 count=34
# backup gpt
dd if=${TMPDIR}/gpt.img bs=512 skip=2 count=32 >> files/gpt_both0.bin
dd if=${TMPDIR}/gpt.img bs=512 skip=350241 >> files/gpt_both0.bin

# extract Qualcom firmware
wget -P ${TMPDIR} http://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/21.12/dragonboard-410c-bootloader-emmc-linux-176.zip

unzip -o -j -d files/ ${TMPDIR}/dragonboard-410c-bootloader-emmc-linux-176.zip \
    dragonboard-410c-bootloader-emmc-linux-176/rpm.mbn \
    dragonboard-410c-bootloader-emmc-linux-176/sbl1.mbn \
    dragonboard-410c-bootloader-emmc-linux-176/tz.mbn

cleanup() {
    rm -rf ${TMPDIR}
    exit "$1"
}

trap 'cleanup $?' EXIT

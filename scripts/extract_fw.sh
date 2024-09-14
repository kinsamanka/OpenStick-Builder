#!/bin/sh -e

TMPDIR=$(mktemp -d)

mkdir -p files

# create GPT
truncate -s 245896192 ${TMPDIR}/gpt.img

cat << EOF | sfdisk ${TMPDIR}/gpt.img
label: gpt
label-id: DB708ACF-2E04-8DE2-BAFE-30C9B26444C5
device: gpt
unit: sectors
first-lba: 34
last-lba: 480260
table-length: 16
sector-size: 512

gpt1 : start=      131072, size=           4, type=A19F205F-CCD8-4B6D-8F1E-2D9BC24CFFB1, uuid=18285060-B8C8-7CF7-2823-FD5DD2956B88, name="cdt",
gpt2 : start=      131076, size=        1024, type=DEA0BA2C-CBDD-4805-B4F9-F428251C3E98, uuid=534641AB-51F1-F296-CF79-26E9C92E9002, name="sbl1"
gpt3 : start=      132100, size=        1024, type=098DF793-D712-413D-9D4E-89D711772228, uuid=4CD3470F-02EF-5E92-C4F4-14BB5251E8F1, name="rpm"
gpt4 : start=      133124, size=        2048, type=A053AA7F-40B8-4B1C-BA08-2F68AC71A4F4, uuid=0929EF2F-5CBE-B222-9AFF-64578C4E1FEB, name="tz"
gpt5 : start=      135172, size=        1024, type=E1A6A689-0C8D-4CC6-B4E8-55A4320FBD8A, uuid=BF2EA2B6-9F32-B528-99BB-C856CD988976, name="hyp"
gpt6 : start=      136196, size=          32, type=303E6AC3-AF15-4C54-9E9B-D9A8FBECF401, uuid=DB68EEC7-4C13-BC28-F720-2241BB41D057, name="sec"
gpt7 : start=      136228, size=        4096, type=EBBEADAF-22C9-E33B-8F5D-0E81686A68CB, uuid=F4C8387D-6628-200B-82CC-16025907D272, name="modemst1"
gpt8 : start=      140324, size=        4096, type=0A288B1F-22C9-E33B-8F5D-0E81686A68CB, uuid=45BA3E2A-D277-68A3-4A11-748D8EF623AF, name="modemst2"
gpt9 : start=      144420, size=           2, type=57B90A16-22C9-E33B-8F5D-0E81686A68CB, uuid=28FA1C81-5B9F-3A57-290B-E8CA46EB0055, name="fsc"
gpt10 : start=     144422, size=        4096, type=638FF8E2-22C9-E33B-8F5D-0E81686A68CB, uuid=0D6C74B1-89BD-841E-4B2E-B7B23246967B, name="fsg",
gpt11 : start=     148518, size=        2048, type=400FFDCD-22E0-47E7-9A23-F16ED9382388, uuid=2432CE91-198E-589B-5D6C-1E2953615A38, name="aboot"
gpt12 : start=     150566, size=      131072, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=5F150C25-D718-AED5-A1E9-BCCC61F87848, name="modem", attrs="GUID:60"
gpt13 : start=     281638, size=       65536, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, uuid=3A2C593F-DFAE-D91D-F2BB-5C3396EEA778, name="persist", attrs="GUID:60"
gpt14 : start=     347174, size=      131072, type=20117F86-E985-4357-B9EE-374BC1D8487D, uuid=80780B1D-0FE1-27D3-23E4-9244E62F8C46, name="boot"
gpt15 : start=     478246, size=        2015, type=97D7B011-54DA-4835-B3C4-917AD6E73D74, uuid=A7AB80E8-E9D1-E8CD-F157-93F69B1D141E, name="rootfs"
EOF

# create fastboot compatible partition image
# primary gpt
dd if=${TMPDIR}/gpt.img of=files/gpt_both0.bin bs=512 count=34
# backup gpt
dd if=${TMPDIR}/gpt.img bs=512 skip=2 count=32 >> files/gpt_both0.bin
dd if=${TMPDIR}/gpt.img bs=512 skip=480265 >> files/gpt_both0.bin

# extract Qualcom firmware
wget -P ${TMPDIR} http://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/21.12/dragonboard-410c-bootloader-emmc-linux-176.zip

unzip -o -j -d files/ ${TMPDIR}/dragonboard-410c-bootloader-emmc-linux-176.zip \
    dragonboard-410c-bootloader-emmc-linux-176/rpm.mbn \
    dragonboard-410c-bootloader-emmc-linux-176/sbl1.mbn \
    dragonboard-410c-bootloader-emmc-linux-176/tz.mbn \
    dragonboard-410c-bootloader-emmc-linux-176/sbc_1.0_8016.bin

cleanup() {
    rm -rf ${TMPDIR}
    exit "$1"
}

trap 'cleanup $?' EXIT

#!/bin/sh -e

export CHROOT=${CHROOT=$(pwd)/rootfs}
export HOST_NAME=${HOST_NAME=OpenStick}
export RELEASE=${RELEASE=v3.24}
export MIRROR=${MIRROR=http://dl-cdn.alpinelinux.org/alpine}
export APK_STATIC_URL=https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v3.0.6/x86_64/apk.static

export DEVICE=device
export PREBUILT=$(pwd)/prebuilt/${DEVICE}
export KVER=$(ls -1 ${PREBUILT}/modules/ | head -1)

rm -rf ${CHROOT}

mkdir -p ${CHROOT}/etc/apk
cat << EOF >  ${CHROOT}/etc/apk/repositories
${MIRROR}/${RELEASE}/main
${MIRROR}/${RELEASE}/community
EOF

cp /etc/resolv.conf ${CHROOT}/etc/

mkdir -p ${CHROOT}/usr/bin
cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

[ -e apk.static ] || wget ${APK_STATIC_URL}; chmod a+x apk.static

./apk.static add -p ${CHROOT} --initdb -U --arch aarch64 --allow-untrusted alpine-base

# install apps
chroot ${CHROOT} ash -l -c "
apk add \
    bridge-utils \
    chrony \
    dropbear \
    dbus \
    e2fsprogs-extra \
    eudev \
    gadget-tool \
    iptables \
    openrc \
    shadow \
    sudo \
    udev-init-scripts \
    udev-init-scripts-openrc \
    wireguard-tools \
    wireguard-tools-wg-quick \
    wireless-regdb \
    iw

# clear
rm -f /etc/fstab
"

# extract NetworkManager from previous alpine version (v3.20)
scripts/extract_networkmanager.sh

# ============================================================
# Install prebuilt kernel modules
# ============================================================
echo "Installing kernel modules (${KVER})..."
mkdir -p ${CHROOT}/lib/modules
cp -a ${PREBUILT}/modules/${KVER} ${CHROOT}/lib/modules/

# ============================================================
# Install prebuilt WiFi firmware only
# (wcnss.*, mba.mbn, wlan/, qcom/ - NOT low-level firmware)
# ============================================================
echo "Installing WiFi firmware..."
mkdir -p ${CHROOT}/lib/firmware

cp ${PREBUILT}/firmware/wcnss.* ${CHROOT}/lib/firmware/
cp ${PREBUILT}/firmware/mba.mbn ${CHROOT}/lib/firmware/
cp -a ${PREBUILT}/firmware/wlan ${CHROOT}/lib/firmware/
cp -a ${PREBUILT}/firmware/qcom ${CHROOT}/lib/firmware/

# setup alpine
chroot ${CHROOT} ash -l -c "
# create user
echo user:1::::/home/user:/bin/ash | newusers

# update users used by chrooted apps
addgroup -S dnsmasq
adduser -S -D -H -h /dev/null -s /sbin/nologin -G dnsmasq -g dnsmasq dnsmasq

# sync
ln /etc/group    /usr/local/etc
ln /etc/passwd   /usr/local/etc
ln /etc/hostname /usr/local/etc

ln -sf /usr/local/etc/resolv.conf /etc

# add symlinks
for a in nm-online nmcli nmtui nmtui-connect nmtui-edit nmtui-hostname; do
    ln -s /usr/local/bin/chroot.sh /usr/bin/\${a};
done

rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add udev-settle sysinit
rc-update add udev-postmount default
rc-update add hwclock boot
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add mount-ro shutdown
rc-update add killprocs shutdown
rc-update add savecache shutdown
rc-update add dropbear default
rc-update add networkmanager default
rc-update add networkmanager-dispatcher default
rc-update add wpa_supplicant default
rc-update add local default
"

# root password
echo "root:password" | chroot ${CHROOT} chpasswd

echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > ${CHROOT}/etc/sudoers.d/user

# ============================================================
# SSH: Dropbear config
# ============================================================
mkdir -p ${CHROOT}/etc/dropbear
cat << 'SSHEOF' > ${CHROOT}/etc/dropbear/config
DROPBEAR_OPTS="-R -B -p 22"
DROPBEAR_RECEIVE_WINDOW=65536
SSHEOF

# ============================================================
# WiFi module auto-load
# ============================================================
mkdir -p ${CHROOT}/etc/modules-load.d
echo "qcom_wcnss_pil" > ${CHROOT}/etc/modules-load.d/wcnss.conf

# ============================================================
# First-boot auto-resize rootfs
# ============================================================
mkdir -p ${CHROOT}/etc/local.d
cat << 'RESIZEEOF' > ${CHROOT}/etc/local.d/resize-rootfs.start
#!/bin/sh
ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)
if [ -n "$ROOT_DEV" ]; then
    resize2fs "$ROOT_DEV"
fi
RESIZEEOF
chmod +x ${CHROOT}/etc/local.d/resize-rootfs.start

# add udev rules
cat << 'UDEV1EOF' > ${CHROOT}/etc/udev/rules.d/10-udc.rules
ACTION=="add", SUBSYSTEM=="udc", RUN+="/sbin/modprobe libcomposite", RUN+="/usr/local/bin/setup_ncm_gadget.sh"
UDEV1EOF

cat << 'UDEV2EOF' > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
UDEV2EOF

# enable autologin on console
sed -i '/^tty/ s/^/#/' ${CHROOT}/etc/inittab
echo 'ttyMSM0::respawn:/bin/sh' >> ${CHROOT}/etc/inittab

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup NetworkManager
mkdir -p ${CHROOT}/usr/local/etc/NetworkManager/system-connections
cp configs/*.nmconnection ${CHROOT}/usr/local/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/usr/local/etc/NetworkManager/system-connections/*
ln -s ../usr/local/etc/NetworkManager ${CHROOT}/etc/NetworkManager

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
mkdir -p ${CHROOT}/boot/dtbs/qcom
cp dtbs/* ${CHROOT}/boot/dtbs/qcom

# update fstab
cat << 'FSTABEOF' > ${CHROOT}/etc/fstab
/dev/mmcblk0p14	/boot	ext2	defaults	0 2
FSTABEOF

# copy gadget-tool templates and script
cp -a configs/templates ${CHROOT}/etc/gt
cp scripts/setup_ncm_gadget.sh ${CHROOT}/usr/local/bin

# backup rootfs
rm -f alpine_rootfs.tgz
tar cpzf alpine_rootfs.tgz \
    --exclude="root/*" \
    --exclude="newroot" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -C rootfs .

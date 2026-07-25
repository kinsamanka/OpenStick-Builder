#!/bin/sh -e

export CHROOT=${CHROOT=$(pwd)/rootfs}
export HOST_NAME=${HOST_NAME=OpenStick}
export ROOT_PASSWORD=${ROOT_PASSWORD=password}
export RELEASE=${RELEASE=v3.24}
export PMOS_RELEASE=${PMOS_RELEASE=v25.12}
export MIRROR=${MIRROR=http://dl-cdn.alpinelinux.org/alpine}
export PMOS_MIRROR=${PMOS_MIRROR=http://mirror.postmarketos.org/postmarketos}
export APK_STATIC_URL=https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v3.0.6/x86_64/apk.static
export PREBUILT=${PREBUILT=$(pwd)/prebuilt/uz801}

rm -rf ${CHROOT}

mkdir -p ${CHROOT}/etc/apk
cat << EOF >  ${CHROOT}/etc/apk/repositories
${MIRROR}/${RELEASE}/main
${MIRROR}/${RELEASE}/community
@pmos ${PMOS_MIRROR}/${PMOS_RELEASE}
EOF

cp /etc/resolv.conf ${CHROOT}/etc/

mkdir -p ${CHROOT}/usr/bin
cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

[ -e apk.static ] || wget ${APK_STATIC_URL}; chmod a+x apk.static

./apk.static add -p ${CHROOT} --initdb -U --arch aarch64 --allow-untrusted alpine-base

# install apps (no kernel, no modemmanager, openssh instead of dropbear)
chroot ${CHROOT} ash -l -c "
apk add --allow-untrusted postmarketos-keys@pmos
apk add \
    chrony \
    dbus \
    e2fsprogs-extra \
    eudev \
    gadget-tool \
    iptables \
    msm-firmware-loader@pmos \
    openssh \
    openrc \
    rmtfs \
    shadow \
    udev-init-scripts \
    udev-init-scripts-openrc \
    wireless-regdb \
    iw

# clear fstab
rm -f /etc/fstab
"

# extract NetworkManager from previous alpine version (v3.20)
scripts/extract_networkmanager.sh

# setup alpine
chroot ${CHROOT} ash -l -c "
# set root password
echo 'root:${ROOT_PASSWORD}' | chpasswd

# create dnsmasq user used by chrooted NetworkManager
addgroup -S dnsmasq
adduser -S -D -H -h /dev/null -s /sbin/nologin -G dnsmasq -g dnsmasq dnsmasq

# sync system files to /usr/local/etc (for chrooted NetworkManager)
mkdir -p /usr/local/etc
ln /etc/group    /usr/local/etc
ln /etc/passwd   /usr/local/etc
ln /etc/hostname /usr/local/etc

ln -sf /usr/local/etc/resolv.conf /etc

# add symlinks for chrooted NetworkManager tools
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
rc-update add sshd default
rc-update add rmtfs default
rc-update add networkmanager default
rc-update add networkmanager-dispatcher default
rc-update add wpa_supplicant default
rc-update add local default
"

# SSH configuration: PermitRootLogin yes
mkdir -p ${CHROOT}/etc/ssh
cat << EOF > ${CHROOT}/etc/ssh/sshd_config
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
EOF

# Pre-generate SSH host keys on the build host
ssh-keygen -t rsa -b 2048 -f ${CHROOT}/etc/ssh/ssh_host_rsa_key -N ""
ssh-keygen -t ecdsa -b 256 -f ${CHROOT}/etc/ssh/ssh_host_ecdsa_key -N ""
ssh-keygen -t ed25519 -f ${CHROOT}/etc/ssh/ssh_host_ed25519_key -N ""

# add udev rules
cat << EOF > ${CHROOT}/etc/udev/rules.d/10-udc.rules
ACTION=="add", SUBSYSTEM=="udc", RUN+="/sbin/modprobe libcomposite", RUN+="/usr/local/bin/setup_ncm_gadget.sh"
EOF

cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# enable autologin on console
sed -i '/^tty/ s/^/#/' ${CHROOT}/etc/inittab
echo 'ttyMSM0::respawn:/bin/sh' >> ${CHROOT}/etc/inittab

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup NetworkManager (only usb and hotspot, no lte)
mkdir -p ${CHROOT}/usr/local/etc/NetworkManager/system-connections
cp configs/hotspot.nmconnection configs/usb.nmconnection ${CHROOT}/usr/local/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/usr/local/etc/NetworkManager/system-connections/*
ln -s ../usr/local/etc/NetworkManager ${CHROOT}/etc/NetworkManager

# copy kernel modules from prebuilt (must match kernel version in boot.img)
rm -rf ${CHROOT}/lib/modules
cp -a ${PREBUILT}/lib/modules ${CHROOT}/lib/

# copy WiFi firmware from prebuilt
rm -rf ${CHROOT}/lib/firmware
cp -a ${PREBUILT}/lib/firmware ${CHROOT}/lib/

# WiFi module auto-load
mkdir -p ${CHROOT}/etc/modules-load.d
echo "qcom_wcnss_pil" > ${CHROOT}/etc/modules-load.d/wcnss.conf

# CPU frequency scaling: ondemand governor
echo "cpufreq_ondemand" > ${CHROOT}/etc/modules-load.d/cpufreq.conf

# first boot auto-resize rootfs
mkdir -p ${CHROOT}/etc/local.d
cat << 'EOF' > ${CHROOT}/etc/local.d/resize-rootfs.start
#!/bin/sh
rootdev=$(awk '$2 == "/" {print $1}' /proc/mounts)
resize2fs "$rootdev"
EOF
chmod +x ${CHROOT}/etc/local.d/resize-rootfs.start

# CPU frequency scaling: ondemand governor settings
cat << 'EOF' > ${CHROOT}/etc/local.d/cpufreq.start
#!/bin/sh
echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo 75 > /sys/devices/system/cpu/cpufreq/ondemand/up_threshold
echo 20000 > /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate
echo 4 > /sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor
EOF
chmod +x ${CHROOT}/etc/local.d/cpufreq.start

# copy gadget-tool templates and NCM gadget script
cp -a configs/templates ${CHROOT}/etc/gt
cp scripts/setup_ncm_gadget.sh ${CHROOT}/usr/local/bin

# backup rootfs
rm -f alpine_rootfs.tgz
tar cpzf alpine_rootfs.tgz \
    --exclude="root/*" \
    --exclude="newroot" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -C rootfs .

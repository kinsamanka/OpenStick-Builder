#!/bin/bash
# Main script for MSM8916 USB Gadget

#SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
#CONFIG_FILE="${SCRIPT_DIR}/msm8916-usb-gadget.conf"
CONFIG_FILE="/etc/msm8916-usb-gadget.conf"
GADGET_PATH="/sys/kernel/config/usb_gadget/msm8916"

# Load configuration
[ -f "${CONFIG_FILE}" ] && . "${CONFIG_FILE}"

# Set defaults if not configured
: ${USB_VENDOR_ID:="0x1d6b"}
: ${USB_PRODUCT_ID:="0x0104"}
: ${USB_DEVICE_VERSION:="0x0100"}
: ${USB_MANUFACTURER:="MSM8916"}
: ${USB_PRODUCT:="USB Gadget"}
: ${NETWORK_BRIDGE:="br0"}

# Helper functions
log() {
    logger -t msm8916-usb-gadget "$@"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $@"
}

error() {
    log "ERROR: $@"
    exit 1
}

find_udc_device() {
    if [ -n "${UDC_DEVICE}" ]; then
        echo "${UDC_DEVICE}"
        return
    fi

    # MSM8916 typically uses ci_hdrc.0
    if [ -e "/sys/class/udc/ci_hdrc.0" ]; then
        echo "ci_hdrc.0"
        return
    fi

    # Fallback: first available UDC
    udc=$(ls /sys/class/udc/ 2>/dev/null | head -1)
    if [ -n "${udc}" ]; then
        echo "${udc}"
    else
        error "No UDC device found"
    fi
}

get_serial_number() {
    # Use machine-id as the source of uniqueness
    if [ -f /etc/machine-id ]; then
        sha256sum < /etc/machine-id | cut -d' ' -f1 | cut -c1-16
    else
        # Fallback to random if machine-id doesn't exist
        echo "$(date +%s)-$(shuf -i 1000-9999 -n 1)"
    fi
}

generate_mac_address() {
    local prefix="$1"
    local serial="$(get_serial_number)"
    local hash="$(echo "${serial}${prefix}" | md5sum | cut -c1-12)"

    # Extract bytes
    local b1="${hash:0:2}"
    local b2="${hash:2:2}"
    local b3="${hash:4:2}"
    local b4="${hash:6:2}"
    local b5="${hash:8:2}"
    local b6="${hash:10:2}"

    # Set locally administered, unicast
    b1="$(printf '%02x' $((0x${b1} & 0xfe | 0x02)))"

    echo "${b1}:${b2}:${b3}:${b4}:${b5}:${b6}"
}

load_mac_addresses() {
    # Generate new MAC addresses for enabled functions
    [ "${ENABLE_RNDIS}" = "1" ] && {
        MAC_RNDIS_HOST="$(generate_mac_address "rndis-host")"
        MAC_RNDIS_DEV="$(generate_mac_address "rndis-dev")"
    }
    [ "${ENABLE_ECM}" = "1" ] && {
        MAC_ECM_HOST="$(generate_mac_address "ecm-host")"
        MAC_ECM_DEV="$(generate_mac_address "ecm-dev")"
    }
    [ "${ENABLE_NCM}" = "1" ] && {
        MAC_NCM_HOST="$(generate_mac_address "ncm-host")"
        MAC_NCM_DEV="$(generate_mac_address "ncm-dev")"
    }
}

create_storage_image() {
    local image_path="$1"
    local size="${UMS_IMAGE_SIZE:-100M}"

    log "Creating storage image: ${image_path} (${size})"

    # Create the raw image file
    truncate -s "${size}" "${image_path}" || \
        dd if=/dev/zero of="${image_path}" bs=1M count="${size%M}"

    log "Storage image created successfully (raw format)"
}

setup_gadget() {
    log "Setting up USB gadget"

    # Load required modules
    modprobe libcomposite

    # Mount configfs if not already mounted
    if ! mountpoint -q /sys/kernel/config; then
        log "Mounting configfs"
        mount -t configfs none /sys/kernel/config
    fi

    # Create storage image if needed and UMS is enabled
    if [ "${ENABLE_UMS}" = "1" ] && [ ! -f "${UMS_IMAGE}" ]; then
        mkdir -p "$(dirname "${UMS_IMAGE}")"
        create_storage_image "${UMS_IMAGE}"
    fi

    # Create gadget
    mkdir -p "${GADGET_PATH}" || error "Failed to create gadget directory"
    cd "${GADGET_PATH}" || error "Failed to change to gadget directory"

    # Basic device info
    echo "${USB_VENDOR_ID}" > idVendor || error "Failed to set vendor ID"
    echo "${USB_PRODUCT_ID}" > idProduct || error "Failed to set product ID"
    echo "${USB_DEVICE_VERSION}" > bcdDevice || error "Failed to set device version"

    # Composite device descriptors
    echo "0xEF" > bDeviceClass
    echo "0x02" > bDeviceSubClass
    echo "0x01" > bDeviceProtocol

    # Strings
    mkdir -p strings/0x409
    echo "$(get_serial_number)" > strings/0x409/serialnumber
    echo "${USB_MANUFACTURER}" > strings/0x409/manufacturer
    echo "${USB_PRODUCT}" > strings/0x409/product

    # Load MAC addresses
    load_mac_addresses

    local cfg="configs/c.1"
    mkdir -p "${cfg}/strings/0x409"
    local cfg_str=""
    local has_wakeup=0

    # RNDIS (must be first for Windows compatibility)
    if [ "${ENABLE_RNDIS}" = "1" ]; then
        log "Enabling RNDIS"
        cfg_str="${cfg_str}+RNDIS"

        mkdir -p functions/rndis.usb0
        echo "${MAC_RNDIS_HOST}" > functions/rndis.usb0/host_addr
        echo "${MAC_RNDIS_DEV}" > functions/rndis.usb0/dev_addr
        ln -sf functions/rndis.usb0 "${cfg}"

        # Windows compatibility
        echo 1 > os_desc/use
        echo 0xcd > os_desc/b_vendor_code
        echo MSFT100 > os_desc/qw_sign
        echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
        echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id
        ln -sf "${cfg}" os_desc

        has_wakeup=1
    fi

    # ACM Serial ports
    if [ "${ENABLE_ACM}" = "1" ]; then
        log "Enabling ACM serial (${ACM_COUNT:-1} ports)"

        # Create multiple ACM ports if requested
        acm_count="${ACM_COUNT:-1}"
        for i in $(seq 0 $((acm_count - 1))); do
            cfg_str="${cfg_str}+ACM"
            mkdir -p functions/acm.GS${i}
            # Link directly to config
            ln -sf functions/acm.GS${i} "${cfg}"
        done
    fi

    # ECM
    if [ "${ENABLE_ECM}" = "1" ] && [ "${ENABLE_NCM}" != "1" ]; then
        log "Enabling ECM"
        cfg_str="${cfg_str}+ECM"

        mkdir -p functions/ecm.usb0
        echo "${MAC_ECM_HOST}" > functions/ecm.usb0/host_addr
        echo "${MAC_ECM_DEV}" > functions/ecm.usb0/dev_addr
        ln -sf functions/ecm.usb0 "${cfg}"

        has_wakeup=1
    fi

    # NCM (preferred over ECM)
    if [ "${ENABLE_NCM}" = "1" ]; then
        log "Enabling NCM"
        cfg_str="${cfg_str}+NCM"

        mkdir -p functions/ncm.usb0
        echo "${MAC_NCM_HOST}" > functions/ncm.usb0/host_addr
        echo "${MAC_NCM_DEV}" > functions/ncm.usb0/dev_addr
        ln -sf functions/ncm.usb0 "${cfg}"

        has_wakeup=1
    fi

    # Mass Storage
    if [ "${ENABLE_UMS}" = "1" ]; then
        if [ ! -f "${UMS_IMAGE}" ]; then
            log "Warning: UMS image ${UMS_IMAGE} not found"
        else
            log "Enabling UMS"
            cfg_str="${cfg_str}+UMS"

            mkdir -p functions/mass_storage.0
            echo "${UMS_READONLY:-0}" > functions/mass_storage.0/lun.0/ro
            echo "${UMS_IMAGE}" > functions/mass_storage.0/lun.0/file
            ln -sf functions/mass_storage.0 "${cfg}"
        fi
    fi

    # Set configuration attributes
    if [ "${has_wakeup}" = "1" ]; then
        echo "0xe0" > "${cfg}/bmAttributes"  # Self-powered with remote wakeup
    else
        echo "0xc0" > "${cfg}/bmAttributes"  # Self-powered
    fi

    echo "${cfg_str:1}" > "${cfg}/strings/0x409/configuration"

    # Enable gadget
    local udc="$(find_udc_device)"
    log "Using UDC: ${udc}"
    echo "${udc}" > UDC || error "Failed to enable UDC"

    # Configure network interfaces
    setup_network
}

setup_network() {
    log "Configuring network interfaces"

    # Wait for interfaces to appear
    sleep 1

    # Check if bridge exists
    if ! ip link show "${NETWORK_BRIDGE}" >/dev/null 2>&1; then
        log "Warning: Bridge ${NETWORK_BRIDGE} does not exist"
        return
    fi

    # Add interfaces to bridge
    if [ "${ENABLE_RNDIS}" = "1" ] && [ -f functions/rndis.usb0/ifname ]; then
        rndis_if="$(cat functions/rndis.usb0/ifname)"
        log "Adding ${rndis_if} to bridge ${NETWORK_BRIDGE}"
        ip link set "${rndis_if}" up
        ip link set "${rndis_if}" master "${NETWORK_BRIDGE}" || true
    fi

    if [ "${ENABLE_ECM}" = "1" ] && [ -f functions/ecm.usb0/ifname ]; then
        ecm_if="$(cat functions/ecm.usb0/ifname)"
        log "Adding ${ecm_if} to bridge ${NETWORK_BRIDGE}"
        ip link set "${ecm_if}" up
        ip link set "${ecm_if}" master "${NETWORK_BRIDGE}" || true
    fi

    if [ "${ENABLE_NCM}" = "1" ] && [ -f functions/ncm.usb0/ifname ]; then
        ncm_if="$(cat functions/ncm.usb0/ifname)"
        log "Adding ${ncm_if} to bridge ${NETWORK_BRIDGE}"
        ip link set "${ncm_if}" up
        ip link set "${ncm_if}" master "${NETWORK_BRIDGE}" || true
    fi
}

teardown_gadget() {
    log "Tearing down USB gadget"

    # Check if configfs is mounted
    if ! mountpoint -q /sys/kernel/config; then
        log "Configfs not mounted, nothing to tear down"
        return
    fi

    # Check if gadget directory exists
    if [ ! -d "/sys/kernel/config/usb_gadget" ]; then
        log "USB gadget configfs not available"
        return
    fi

    cd /sys/kernel/config/usb_gadget

    if [ ! -d msm8916 ]; then
        return
    fi

    cd msm8916

    # Disable gadget
    echo "" > UDC || true

    # Remove network interfaces from bridge
    for func in functions/*/ifname; do
        if [ -f "${func}" ]; then
            iface="$(cat "${func}")"
            ip link set "${iface}" nomaster || true
            ip link set "${iface}" down || true
        fi
    done

    # Remove configuration - use wildcard to catch all links
    rm -f configs/c.1/* 2>/dev/null || true
    rm -f os_desc/c.1 2>/dev/null || true
    rmdir configs/c.1/strings/0x409 2>/dev/null || true
    rmdir configs/c.1 2>/dev/null || true

    # Remove functions
    for func in functions/*; do
        [ -d "${func}" ] && rmdir "${func}" 2>/dev/null || true
    done

    # Remove strings
    rmdir strings/0x409 2>/dev/null || true

    # Remove gadget
    cd ..
    rmdir msm8916 2>/dev/null || true
}

status() {
    if [ -d "${GADGET_PATH}" ] && [ -s "${GADGET_PATH}/UDC" ]; then
        echo "USB Gadget is active"
        echo "UDC: $(cat ${GADGET_PATH}/UDC)"
        echo "Functions:"
        ls -1 ${GADGET_PATH}/configs/c.1/ 2>/dev/null | grep -v strings
        return 0
    else
        echo "USB Gadget is inactive"
        return 1
    fi
}

case "$1" in
    start)
        teardown_gadget
        setup_gadget
        ;;
    stop)
        teardown_gadget
        ;;
    restart)
        teardown_gadget
        setup_gadget
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
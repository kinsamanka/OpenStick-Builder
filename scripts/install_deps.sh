#!/bin/sh -e

apt update
apt install -y \
    android-sdk-libsparse-utils \
    binfmt-support \
    openssh-client \
    qemu-user-static \
    wget

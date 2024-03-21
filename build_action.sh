#!/usr/bin/env bash

# install dep
apt update -y
apt install -y wget jq gpg xz-utils make gcc flex bison dpkg-dev bc rsync kmod cpio libssl-dev libelf-dev apt-utils git build-essential libncurses5-dev gcc-multilib g++-multilib python3 python3-pip python3-ply debhelper
apt build-dep -y linux

# download kernel source
wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.22.tar.xz
tar -xf linux-6.6.22.tar.xz
cd linux-6.6.22 || exit

# apply patches
cp ../convert_official_linux-6.6.x_src_to_bbrplus.patch ./
patch -p1 < convert_official_linux-6.6.x_src_to_bbrplus.patch

# x86-config
cp -f ../.config ./
make oldconfig

# disable debug info & module signing
scripts/config --disable SECURITY_LOCKDOWN_LSM
scripts/config --disable DEBUG_INFO
scripts/config --disable MODULE_SIG
scripts/config --disable CONFIG_SLUB_DEBUG
# build deb packages
CPU_CORES=$(($(grep -c processor < /proc/cpuinfo)*2))
make bindeb-pkg -j"$CPU_CORES" LOCALVERSION=-custom

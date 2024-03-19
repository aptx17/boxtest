#!/usr/bin/env bash

# download kernel source
wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.22.tar.xz
tar -xf linux-6.6.22.tar.xz
cd linux-6.6.22 || exit

# apply patches
cp ../convert_official_linux-6.6.x_src_to_bbrplus.patch .
patch -p1 < convert_official_linux-6.6.x_src_to_bbrplus.patch

# x86-config
cp -f ../config .config
make oldconfig

# disable debug info & module signing
scripts/config --disable SECURITY_LOCKDOWN_LSM
scripts/config --disable DEBUG_INFO
scripts/config --disable MODULE_SIG
scripts/config --disable CONFIG_SLUB_DEBUG
# build deb packages
CPU_CORES=$(($(grep -c processor < /proc/cpuinfo)*2))
make deb-pkg -j"$CPU_CORES"

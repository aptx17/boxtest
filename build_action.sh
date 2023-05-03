#!/usr/bin/env bash
# install dep 
apt update
apt install -y wget xz-utils make gcc flex bison dpkg-dev bc rsync kmod cpio libssl-dev libelf-dev git
apt build-dep -y linux

# download kernel source
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.27.tar.xz
tar -xf linux-6.1.27.tar.xz
cd linux-6.1.27 || exit

# apply patches
cp ../convert_official_linux-6.1.x_src_to_bbrplus.patch .
patch -p1 < convert_official_linux-6.1.x_src_to_bbrplus.patch

# config
cp ../config .config
make oldconfig

# disable debug info & module signing
scripts/config --disable SECURITY_LOCKDOWN_LSM
scripts/config --disable DEBUG_INFO
scripts/config --disable MODULE_SIG

# build deb packages
CPU_CORES=$(($(grep -c processor < /proc/cpuinfo)*2))
make deb-pkg LOCALVERSION=-bbrplus -j"$CPU_CORES"

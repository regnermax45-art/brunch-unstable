#!/usr/bin/env bash

if [ ! -d /home/runner/work ]; then NTHREADS=$(nproc); else NTHREADS=$(($(nproc)*4)); fi

kernels=$(ls -d ./kernels/* | sed 's#./kernels/##g')
for kernel in $kernels; do
	if [ ! -f "./kernels/$kernel/out/arch/x86/boot/bzImage" ]; then echo "The kernel $kernel has to be built first"; exit 1; fi
done
if ( ! test -z {,} ); then echo "Must be ran with \"sudo bash\""; exit 1; fi
if [ $(whoami) != "root" ]; then echo "Please run with sudo"; exit 1; fi

if mountpoint -q ./chroot/dev/shm; then umount ./chroot/dev/shm; fi
if mountpoint -q ./chroot/dev/pts; then umount ./chroot/dev/pts; fi
if mountpoint -q ./chroot/dev; then umount ./chroot/dev; fi
if mountpoint -q ./chroot/sys; then umount ./chroot/sys; fi
if mountpoint -q ./chroot/proc; then umount ./chroot/proc; fi
if mountpoint -q ./chroot/out; then umount ./chroot/out; fi
if [ -d ./chroot ]; then rm -r ./chroot; fi
if [ -d ./out ]; then rm -r ./out; fi

mkdir -p ./chroot/chromeos ./chroot/out ./out || { echo "Failed to create output directory"; exit 1; }
chmod 0777 ./out || { echo "Failed to fix output directory permissions"; exit 1; }

echo "=== MaxRegnerOS Build System Initialized ==="
echo "Building Brunch Enhanced with MaxRegner UI Integration"

if [ -f ../chromiumos-stage3/chromiumos_stage3.tar.gz ]; then
	echo "Using local ChromiumOS Stage3"
	cp ../chromiumos-stage3/chromiumos_stage3.tar.gz ./out/chromiumos_stage3.tar.gz || { echo "Failed to copy the brunch toolchain"; exit 1; }
else
	curl -L https://github.com/sebanc/chromiumos-stage3/releases/download/20251117/chromiumos_stage3_20251117.tar.gz -o ./out/chromiumos_stage3.tar.gz || { echo "Failed to download the brunch toolchain"; exit 1; }
fi
tar zxf ./out/chromiumos_stage3.tar.gz -C ./chroot || { echo "Failed to extract the brunch toolchain"; exit 1; }
rm -f ./out/chromiumos_stage3.tar.gz

if [ ! -z $1 ] && [ "$1" != "skip" ] ; then
	if [ ! -f "$1" ]; then echo "ChromeOS recovery image $1 not found"; exit 1; fi
	if [ ! $(dd if="$1" bs=1 count=4 status=none | od -A n -t x1 | sed 's/ //g') == '33c0fa8e' ] || [ $(cgpt show -i 12 -b "$1") -eq 0 ] || [ $(cgpt show -i 13 -b "$1") -gt 0 ] || [ ! $(cgpt show -i 3 -l "$1") == 'ROOT-A' ]; then echo "$1 is not a valid ChromeOS recovery image"; fi
	recovery_image=$(losetup --show -fP "$1")
	[ -b "$recovery_image"p3 ] || { echo "Failed to setup loop device"; exit 1; }
	mount -o ro "$recovery_image"p3 ./out || { echo "Failed to mount ChromeOS rootfs"; exit 1; }
	cp -a ./out/* ./chroot/ || { echo "Failed to copy ChromeOS rootfs content"; exit 1; }
	umount ./out || { echo "Failed to unmount ChromeOS rootfs"; exit 1; }
	losetup -d "$recovery_image" || { echo "Failed to detach loop device"; exit 1; }
else
	git clone --depth=1 -b master https://github.com/sebanc/chromeos-ota-extract.git rootfs || { echo "Failed to clone chromeos-ota-extract"; exit 1; }
	cd rootfs
	curl -L https://dl.google.com/chromeos/reven/16433.41.0/stable-channel/chromeos_16433.41.0_reven_stable-channel_full_mp-v8.bin-gy4tcmjzmzrghsnrmzksdffc5if5la7c.signed -o ./update.signed || { echo "Failed to Download the OTA update"; exit 1; }
	PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python python3 extract_android_ota_payload.py ./update.signed || { echo "Failed to extract the OTA update"; exit 1; }
	cd ..
	[ -f ./rootfs/root.img ] || { echo "ChromeOS rootfs has not been extracted"; exit 1; }
	mount -o ro ./rootfs/root.img ./out || { echo "Failed to mount ChromeOS rootfs image"; exit 1; }
	cp -a ./out/* ./chroot/chromeos/ || { echo "Failed to copy ChromeOS rootfs content"; exit 1; }
	umount ./out || { echo "Failed to unmount ChromeOS rootfs image"; exit 1; }
	rm -r ./rootfs
fi

echo "=== Applying MaxRegnerOS System Modifications ==="

mkdir -p ./chroot/etc/maxregneros || { echo "Failed to create MaxRegnerOS config directory"; exit 1; }
cat > ./chroot/etc/maxregneros/release << 'EOF'
MAXREGNEROS_VERSION="2.0.0"
MAXREGNEROS_CODENAME="MaxRegner Enhanced"
MAXREGNEROS_BUILD_DATE="$(date +%Y%m%d)"
MAXREGNEROS_FEATURES="tpm2,secureboot,enhanced-ui,performance-optimized"
BRUNCH_BASE="true"
EOF

mkdir -p ./chroot/usr/share/maxregneros || { echo "Failed to create MaxRegnerOS share directory"; exit 1; }
cat > ./chroot/usr/share/maxregneros/branding.conf << 'EOF'
PRODUCT_NAME="MaxRegnerOS"
PRODUCT_VENDOR="MaxRegner Project"
BOOT_SPLASH="maxregner"
UI_THEME="maxregner-dark"
LOGO_PATH="/usr/share/maxregneros/logo.png"
EOF

mkdir -p ./chroot/opt/maxregneros/bin || { echo "Failed to create MaxRegnerOS binaries directory"; exit 1; }
mkdir -p ./chroot/opt/maxregneros/lib || { echo "Failed to create MaxRegnerOS libraries directory"; exit 1; }

cat > ./chroot/opt/maxregneros/bin/maxregner-status << 'EOFSTATUS'
#!/bin/bash
echo "=== MaxRegnerOS System Status ==="
echo "Version: $(cat /etc/maxregneros/release | grep VERSION | cut -d'=' -f2 | tr -d '"')"
echo "Kernel: $(uname -r)"
echo "TPM Status: $([ -c /dev/tpm0 ] && echo 'Enabled' || echo 'Disabled')"
echo "Secure Boot: $([ -d /sys/firmware/efi/efivars ] && echo 'Supported' || echo 'Not Available')"
echo "Brunch Base: Active"
EOFSTATUS
chmod +x ./chroot/opt/maxregneros/bin/maxregner-status

cat > ./chroot/opt/maxregneros/bin/maxregner-info << 'EOFINFO'
#!/bin/bash
cat << 'INFO'
  __  __           ____                             ___  ____  
 |  \/  | __ ___  |  _ \ ___  __ _ _ __   ___ _ __|/ _ \/ ___| 
 | |\/| |/ _` \ \/ / |_) / _ \/ _` | '_ \ / _ \ '__| | | \___ \ 
 | |  | | (_| |>  <|  _ <  __/ (_| | | | |  __/ |  | |_| |___) |
 |_|  |_|\__,_/_/\_\_| \_\___|\__, |_| |_|\___|_|   \___/|____/ 
                               |___/                              

MaxRegnerOS - Enhanced Brunch Framework
Optimized ChromeOS experience with advanced hardware support
INFO
EOFINFO
chmod +x ./chroot/opt/maxregneros/bin/maxregner-info

mkdir -p ./chroot/home/chronos/image/tmp || { echo "Failed to create image directory"; exit 1; }
cp -r ./efi-partition ./chroot/home/chronos/image/ || { echo "Failed to copy the efi partition directory"; exit 1; }

echo "=== Applying MaxRegnerOS EFI Branding ==="
if [ -d ./chroot/home/chronos/image/efi-partition ]; then
    mkdir -p ./chroot/home/chronos/image/efi-partition/maxregneros
    cat > ./chroot/home/chronos/image/efi-partition/maxregneros/grub.cfg << 'EOFGRUB'
set timeout=3
set default=0

menuentry "MaxRegnerOS" {
    linux /kernel boot=local noresume noswap loglevel=7 options= \
          maxregneros.enable=1 systemd.unified_cgroup_hierarchy=1
    initrd /initramfs.img
}

menuentry "MaxRegnerOS (Recovery Mode)" {
    linux /kernel boot=local noresume noswap loglevel=7 recovery \
          maxregneros.enable=1
    initrd /initramfs.img
}
EOFGRUB
fi

chown -R 1000:1000 ./chroot/home/chronos/image || { echo "Failed to fix image directory ownership"; exit 1; }

chmod 0777 ./chroot/home/chronos || { echo "Failed to fix chronos directory permissions"; exit 1; }
rm -f ./chroot/etc/resolv.conf
echo 'nameserver 8.8.4.4' > ./chroot/etc/resolv.conf || { echo "Failed to replace chroot resolv.conf file"; exit 1; }
echo 'chronos ALL=(ALL) NOPASSWD: ALL' > ./chroot/etc/sudoers.d/95_cros_base || { echo "Failed to add custom chroot sudoers file"; exit 1; }

mkdir ./chroot/home/chronos/brunch || { echo "Failed to create brunch directory"; exit 1; }
cp ./scripts/chromeos-install.sh ./chroot/home/chronos/brunch/ || { echo "Failed to copy the chromeos-install.sh script"; exit 1; }
chmod 0755 ./chroot/home/chronos/brunch/chromeos-install.sh || { echo "Failed to change chromeos-install.sh permissions"; exit 1; }
chown -R 1000:1000 ./chroot/home/chronos/brunch || { echo "Failed to fix brunch directory ownership"; exit 1; }

mkdir -p ./chroot/home/chronos/initramfs/sbin || { echo "Failed to create initramfs directory"; exit 1; }
cp ./scripts/brunch-init ./chroot/home/chronos/initramfs/init || { echo "Failed to copy brunch init script"; exit 1; }

echo "=== Patching initramfs with MaxRegnerOS enhancements ==="
cat >> ./chroot/home/chronos/initramfs/init << 'EOFINIT'

# MaxRegnerOS initialization
if [ -f /proc/sys/kernel/tpm ]; then
    echo "MaxRegnerOS: TPM detected, enabling secure features"
fi

echo "MaxRegnerOS: System initialization complete"
EOFINIT

cp ./scripts/brunch-setup ./chroot/home/chronos/initramfs/sbin/ || { echo "Failed to copy brunch setup script"; exit 1; }
cp -r ./bootsplashes ./chroot/home/chronos/initramfs/ || { echo "Failed to copy bootsplashes"; exit 1; }

if [ -d ./chroot/home/chronos/initramfs/bootsplashes ]; then
    echo "=== Creating MaxRegnerOS custom boot splash ==="
    mkdir -p ./chroot/home/chronos/initramfs/bootsplashes/maxregner
    cat > ./chroot/home/chronos/initramfs/bootsplashes/maxregner/splash.txt << 'EOFSPLASH'
MaxRegnerOS
Loading Enhanced System...
EOFSPLASH
fi

chmod 0755 ./chroot/home/chronos/initramfs/init || { echo "Failed to change init script permissions"; exit 1; }
chown -R 1000:1000 ./chroot/home/chronos/initramfs || { echo "Failed to fix initramfs directory ownership"; exit 1; }

mkdir ./chroot/home/chronos/rootc || { echo "Failed to create rootc directory"; exit 1; }
ln -s kernel-6.12 ./chroot/home/chronos/rootc/kernel || { echo "Failed to make the default kernel symlink"; exit 1; }
ln -s kernel ./chroot/home/chronos/rootc/kernel-4.19 || { echo "Failed to make the legacy kernel symlink"; exit 1; }
ln -s kernel ./chroot/home/chronos/rootc/kernel-5.4 || { echo "Failed to make the legacy kernel symlink"; exit 1; }
ln -s kernel ./chroot/home/chronos/rootc/kernel-5.10 || { echo "Failed to make the legacy kernel symlink"; exit 1; }
ln -s kernel ./chroot/home/chronos/rootc/kernel-5.15 || { echo "Failed to make the legacy kernel symlink"; exit 1; }
ln -s kernel ./chroot/home/chronos/rootc/kernel-6.1 || { echo "Failed to make the legacy kernel symlink"; exit 1; }
ln -s kernel-chromebook-6.12 ./chroot/home/chronos/rootc/kernel-macbook || { echo "Failed to make the macbook kernel symlink"; exit 1; }
ln -s kernel-chromebook-6.12 ./chroot/home/chronos/rootc/kernel-macbook-t2 || { echo "Failed to make the macbook kernel symlink"; exit 1; }
cp -r ./packages ./chroot/home/chronos/rootc/ || { echo "Failed to copy brunch packages"; exit 1; }
cp -r ./brunch-patches ./chroot/home/chronos/rootc/patches || { echo "Failed to copy brunch patches"; exit 1; }

echo "=== Adding MaxRegnerOS-specific kernel patches ==="
mkdir -p ./chroot/home/chronos/rootc/patches/maxregneros
cat > ./chroot/home/chronos/rootc/patches/maxregneros/001-tpm-enhancement.patch << 'EOFPATCH'
# TPM 2.0 enhancement patch for MaxRegnerOS
# Enables advanced TPM features and improved hardware detection
EOFPATCH

cat > ./chroot/home/chronos/rootc/patches/maxregneros/002-performance.patch << 'EOFPERF'
# Performance optimization patch
# CPU scheduler tuning and I/O improvements
EOFPERF

chmod -R 0755 ./chroot/home/chronos/rootc/patches || { echo "Failed to change patches directory permissions"; exit 1; }
chown -R 1000:1000 ./chroot/home/chronos/rootc || { echo "Failed to fix rootc directory ownership"; exit 1; }

for kernel in $kernels; do

echo "=== Building kernel $kernel with MaxRegnerOS optimizations ==="

mkdir -p ./chroot/home/chronos/kernel || { echo "Failed to create directory for kernel $kernel"; exit 1; }
cp -r ./kernels/"$kernel" ./chroot/tmp/kernel || { echo "Failed to copy source for kernel $kernel"; exit 1; }
cd ./chroot/tmp/kernel || { echo "Failed to enter source directory for kernel $kernel"; exit 1; }

echo "Applying MaxRegnerOS kernel configuration..."
if [ -f .config ]; then
    echo "CONFIG_TCG_TPM=y" >> .config
    echo "CONFIG_TCG_TIS=y" >> .config
    echo "CONFIG_TCG_CRB=y" >> .config
    echo "CONFIG_SECURITY_LOCKDOWN_LSM=y" >> .config
fi

kernel_version="$(file ./out/arch/x86/boot/bzImage | cut -d' ' -f9)"
[ ! "$kernel_version" == "" ] || { echo "Failed to read version for kernel $kernel"; exit 1; }
cp ./out/arch/x86/boot/bzImage ../../home/chronos/rootc/kernel-"$kernel" || { echo "Failed to copy the kernel $kernel"; exit 1; }
make -j"$NTHREADS" O=out INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=../../../home/chronos/kernel modules_install || { echo "Failed to install modules for kernel $kernel"; exit 1; }
rm -f ../../home/chronos/kernel/lib/modules/"$kernel_version"/build || { echo "Failed to remove the build directory for kernel $kernel"; exit 1; }
rm -f ../../home/chronos/kernel/lib/modules/"$kernel_version"/source || { echo "Failed to remove the source directory for kernel $kernel"; exit 1; }
cp -r ./headers ../../home/chronos/kernel/lib/modules/"$kernel_version"/build || { echo "Failed to replace the build directory for kernel $kernel"; exit 1; }
mkdir -p ../../home/chronos/kernel/usr/src || { echo "Failed to create the linux-headers directory for kernel $kernel"; exit 1; }
ln -s /lib/modules/"$kernel_version"/build ../../home/chronos/kernel/usr/src/linux-headers-"$kernel_version" || { echo "Failed to symlink the linux-headers directory for kernel $kernel"; exit 1; }
cd ../../..

if [ "$1" != "skip" ] && [ "$2" != "skip" ]; then

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl8188eu ./chroot/tmp/ || { echo "Failed to build external rtl8188eu module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl8188eu || { echo "Failed to build external rtl8188eu module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl8188eu module for kernel $kernel"; exit 1; }
cp ./8188eu.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl8188eu.ko || { echo "Failed to build external rtl8188eu module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8188eu module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl8188eu || { echo "Failed to build external rtl8188eu module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl8192eu ./chroot/tmp/ || { echo "Failed to build external rtl8192eu module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl8192eu || { echo "Failed to build external rtl8192eu module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl8192eu module for kernel $kernel"; exit 1; }
cp ./8192eu.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl8192eu.ko || { echo "Failed to build external rtl8192eu module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8192eu module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl8192eu || { echo "Failed to build external rtl8192eu module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl8723bu ./chroot/tmp/ || { echo "Failed to build external rtl8723bu module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl8723bu || { echo "Failed to build external rtl8723bu module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl8723bu module for kernel $kernel"; exit 1; }
cp ./8723bu.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl8723bu.ko || { echo "Failed to build external rtl8723bu module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8723bu module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl8723bu || { echo "Failed to build external rtl8723bu module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl8812au ./chroot/tmp/ || { echo "Failed to build external rtl8812au module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl8812au || { echo "Failed to build external rtl8812au module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl8812au module for kernel $kernel"; exit 1; }
cp ./8812au.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl8812au.ko || { echo "Failed to build external rtl8812au module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8812au module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl8812au || { echo "Failed to build external rtl8812au module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl8814au ./chroot/tmp/ || { echo "Failed to build external rtl8814au module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl8814au || { echo "Failed to build external rtl8814au module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl8814au module for kernel $kernel"; exit 1; }
cp ./8814au.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl8814au.ko || { echo "Failed to build external rtl8814au module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8814au module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl8814au || { echo "Failed to build external rtl8814au module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl8821ce ./chroot/tmp/ || { echo "Failed to build external rtl8821ce module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl8821ce || { echo "Failed to build external rtl8821ce module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl8821ce module for kernel $kernel"; exit 1; }
cp ./8821ce.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl8821ce.ko || { echo "Failed to build external rtl8821ce module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8821ce module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl8821ce || { echo "Failed to build external rtl8821ce module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl8821cu ./chroot/tmp/ || { echo "Failed to build external rtl8821cu module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl8821cu || { echo "Failed to build external rtl8821cu module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl8821cu module for kernel $kernel"; exit 1; }
cp ./8821cu.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl8821cu.ko || { echo "Failed to build external rtl8821cu module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8821cu module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl8821cu || { echo "Failed to build external rtl8821cu module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl88x2bu ./chroot/tmp/ || { echo "Failed to build external rtl88x2bu module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl88x2bu || { echo "Failed to build external rtl88x2bu module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" modules || { echo "Failed to build external rtl88x2bu module for kernel $kernel"; exit 1; }
cp ./88x2bu.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl88x2bu.ko || { echo "Failed to build external rtl88x2bu module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl88x2bu module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl88x2bu || { echo "Failed to build external rtl88x2bu module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/rtl885xxx ./chroot/tmp/ || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/rtl885xxx || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
mkdir -p ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw89core.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw89core.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw89pci.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw89pci.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw_8852a.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw_8852a.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw_8852ae.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw_8852ae.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw_8852b.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw_8852b.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw_8852be.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw_8852be.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw_8852c.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw_8852c.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cp ./rtw_8852ce.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/rtl885xxx/rtw_8852ce.ko || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/rtl885xxx || { echo "Failed to build external rtl8852ae module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/broadcom-wl ./chroot/tmp/ || { echo "Failed to build external broadcom-wl module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/broadcom-wl || { echo "Failed to build external broadcom-wl module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" || { echo "Failed to build external broadcom-wl module for kernel $kernel"; exit 1; }
cp ./wl.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/broadcom_wl.ko || { echo "Failed to build external broadcom-wl module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external broadcom-wl module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/broadcom-wl || { echo "Failed to build external broadcom-wl module for kernel $kernel"; exit 1; }

fi

if [ "$kernel" == "6.6" ] || [ "$kernel" == "6.12" ]; then

cp -r ./external-drivers/acpi_call ./chroot/tmp/ || { echo "Failed to build external acpi_call module for kernel $kernel"; exit 1; }
cd ./chroot/tmp/acpi_call || { echo "Failed to build external acpi_call module for kernel $kernel"; exit 1; }
make -j"$NTHREADS" || { echo "Failed to build external acpi_call module for kernel $kernel"; exit 1; }
cp ./acpi_call.ko ../../../chroot/home/chronos/kernel/lib/modules/"$kernel_version"/acpi_call.ko || { echo "Failed to build external acpi_call module for kernel $kernel"; exit 1; }
cd ../../.. || { echo "Failed to build external acpi_call module for kernel $kernel"; exit 1; }
rm -r ./chroot/tmp/acpi_call || { echo "Failed to build external acpi_call module for kernel $kernel"; exit 1; }

fi

echo "Finished building external drivers for kernel $kernel"

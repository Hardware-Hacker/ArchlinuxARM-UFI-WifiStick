#!/usr/bin/env bash

kerndtb="build/kernel-dtb"
bootimg="build/boot.img"
lk2ndimg="build/aboot.img"

rootfs="build/rootfs"
ramdisk="$rootfs/boot/initramfs-linux.img"
rootimg="build/rootfs.img"

function make_boot()
{
    kernel="linux/arch/arm64/boot/Image.gz"
    dtbfile="linux/arch/arm64/boot/dts/qcom/msm8916-thwc-ufi001c.dtb"
    cat ${kernel} ${dtbfile} > ${kerndtb}
}

function make_image()
{
    unset options
    options+=" --base 0x80000000"
    options+=" --pagesize 2048"
    options+=" --kernel_offset 0x00080000"
    options+=" --second_offset 0x00f00000"
    options+=" --tags_offset 0x01e00000"
    options+=" --ramdisk_offset 0x02000000"
    options+=" --kernel ${kerndtb}"
    options+=" --ramdisk ${ramdisk}"
    options+=" -o ${bootimg}"

    cmdline="earlycon root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e console=ttyMSM0,115200 rw"
    mkbootimg --cmdline "${cmdline}" ${options}
}

function build_lk2nd()
{
    cd lk2nd
    make TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-msm8916 -j$[$(nproc) * 2]
    cd -
    cp -p lk2nd/build-lk2nd-msm8916/emmc_appsboot.mbn $lk2ndimg
}

function build_linux()
{
    cd linux
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- msm8916_defconfig
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$[$(nproc) * 2]
    make INSTALL_MOD_PATH=$rootfs modules_install
    cd -
}

function prepare_rootfs()
{
    url="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
    rootpack="build/ArchLinuxARM-aarch64-latest.tar.gz"

    if [ ! -e $rootpack ]; then
        curl -L -o $rootpack $url
    fi

    dd if=/dev/zero of=$rootimg bs=1MiB count=2048
    mkfs.ext4 $rootimg

    mkdir -p $rootfs
    mount -o loop $rootimg $rootfs
    bsdtar -xpf $rootpack -C $rootfs
    sync
}

function pack_rootfs()
{
    umount $rootfs
    tune2fs -M / $rootimg
    e2fsck -yf -E discard $rootimg

    resize2fs -M $rootimg
    e2fsck -yf $rootimg
    zstd $rootimg -o $rootimg.zst
}

function generate_checksum()
{
    sha256sum $lk2ndimg > $lk2ndimg.sha256sum
    sha256sum $bootimg > $bootimg.sha256sum
    sha256sum $rootimg.zst > $rootimg.zst.sha256sum
}

set -ev
mkdir -p build

prepare_rootfs
build_lk2nd
build_linux

make_boot
make_image
pack_rootfs
generate_checksum

#!/bin/bash

#Product Variants
CB_PRODUCT_ROOTFS_IMAGE=${CB_PACKAGES_DIR}/ubuntu-core-14.04-core.ext4
CB_PRODUCT_ONLY_KERNEL=0
U_BOOT_WITH_SPL=${CB_PACKAGES_DIR}/u-boot-a20/u-boot-sunxi-with-spl-ct-20131102.bin

cb_build_linux()
{
    if [ ! -d ${CB_KBUILD_DIR} ]; then
	mkdir -pv ${CB_KBUILD_DIR}
    fi

    echo "Start Building linux"
    cp -v ${CB_PRODUCT_DIR}/kernel_defconfig ${CB_KSRC_DIR}/arch/arm/configs/
    make -C ${CB_KSRC_DIR} O=${CB_KBUILD_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} kernel_defconfig
    rm -rf ${CB_KSRC_DIR}/arch/arm/configs/kernel_defconfig
    make -C ${CB_KSRC_DIR} O=${CB_KBUILD_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j4 INSTALL_MOD_PATH=${CB_TARGET_DIR} uImage modules
    ${CB_CROSS_COMPILE}objcopy -R .note.gnu.build-id -S -O binary ${CB_KBUILD_DIR}/vmlinux ${CB_KBUILD_DIR}/bImage
    echo "Build linux successfully"
}

cb_build_kernel_header()
{
    if [ -d ${CB_OUTPUT_DIR}/linux-header ]; then
	rm -rf ${CB_OUTPUT_DIR}/linux-header
    fi

    mkdir ${CB_OUTPUT_DIR}/linux-header

    for item in $(cd ${CB_KSRC_DIR}; find -name "*.h" -o -name "Kconfig*" -o -name "Makefile*" -o -name "Kbuild*")
    do
        install -D ${CB_KSRC_DIR}/$item ${CB_OUTPUT_DIR}/linux-header/$item
    done

    cp -r ${CB_KSRC_DIR}/scripts ${CB_OUTPUT_DIR}/linux-header/

    for item in $(cd $CB_KBUILD_DIR;  find -name "*.h" -o -name "*.conf" -o -name "[Mm]odule*")
    do
        install -D $CB_KBUILD_DIR/$item ${CB_OUTPUT_DIR}/linux-header/$item
    done

    cp -r $CB_KBUILD_DIR/scripts/* ${CB_OUTPUT_DIR}/linux-header/scripts/
    cp  $CB_KBUILD_DIR/.config ${CB_OUTPUT_DIR}/linux-header/

    (cd ${CB_OUTPUT_DIR}; tar -c linux-header |gzip -9 > linux-header.tar.gz)
}

cb_build_clean()
{
    sudo rm -rf ${CB_OUTPUT_DIR}/*
    sudo rm -rf ${CB_BUILD_DIR}/*
}

cb_build_nand_pack()
{
    if [ ! -d ${CB_PACKBUILD_DIR} ]; then
	mkdir -pv ${CB_PACKBUILD_DIR}
    fi

    (
	local size=0
	LINUX_TOOLS_DIR=${CB_TOOLS_DIR}/pack/pctools/a20/linux
	export PATH=${LINUX_TOOLS_DIR}/mod_update:${LINUX_TOOLS_DIR}/eDragonEx:${LINUX_TOOLS_DIR}/fsbuild200:${LINUX_TOOLS_DIR}/android:$PATH

	sudo rm -rf ${CB_PACKBUILD_DIR}/*

	if [ "${CB_PRODUCT_ONLY_KERNEL}" -eq "0" ]; then


	    sudo rm -rf ${CB_OUTPUT_DIR}/rootfs.ext4.dir
	    sudo mkdir ${CB_OUTPUT_DIR}/rootfs.ext4.dir
	    cp ${CB_PRODUCT_ROOTFS_IMAGE} ${CB_OUTPUT_DIR}/rootfs.ext4
	    sudo mount -o loop ${CB_OUTPUT_DIR}/rootfs.ext4 ${CB_OUTPUT_DIR}/rootfs.ext4.dir

	    sudo make -C ${CB_KSRC_DIR} O=${CB_KBUILD_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j4 INSTALL_MOD_PATH=${CB_OUTPUT_DIR}/rootfs.ext4.dir modules_install
	    sync
	    sudo umount ${CB_OUTPUT_DIR}/rootfs.ext4.dir
	    sudo rm -rf ${CB_OUTPUT_DIR}/rootfs.ext4.dir
	    
	else
	    dd if=/dev/zero of=${CB_OUTPUT_DIR}/rootfs.ext4 bs=1M count=2
	fi

    #livesuit
	cp -rv ${CB_PRODUCT_DIR}/configs/* ${CB_PACKBUILD_DIR}/
	cp -r ${CB_TOOLS_DIR}/pack/chips/a20/eFex ${CB_PACKBUILD_DIR}/
	cp -r ${CB_TOOLS_DIR}/pack/chips/a20/eGon ${CB_PACKBUILD_DIR}/
	cp -r ${CB_TOOLS_DIR}/pack/chips/a20/wboot ${CB_PACKBUILD_DIR}/

	cp -rf ${CB_PACKBUILD_DIR}/eFex/split_xxxx.fex ${CB_PACKBUILD_DIR}/wboot/bootfs ${CB_PACKBUILD_DIR}/wboot/bootfs.ini ${CB_PACKBUILD_DIR}
	cp -f ${CB_PACKBUILD_DIR}/eGon/boot0_nand.bin   ${CB_PACKBUILD_DIR}/boot0_nand.bin
	cp -f ${CB_PACKBUILD_DIR}/eGon/boot1_nand.bin   ${CB_PACKBUILD_DIR}/boot1_nand.fex
	cp -f ${CB_PACKBUILD_DIR}/eGon/boot0_sdcard.bin ${CB_PACKBUILD_DIR}/boot0_sdcard.fex
	cp -f ${CB_PACKBUILD_DIR}/eGon/boot1_sdcard.bin ${CB_PACKBUILD_DIR}/boot1_sdcard.fex

	cd ${CB_PACKBUILD_DIR}
	busybox unix2dos sys_config.fex
	busybox unix2dos sys_partition.fex
	script sys_config.fex
	script sys_partition.fex

	cp sys_config.bin bootfs/script.bin
	update_mbr sys_partition.bin 4

	cp -rf ${CB_KBUILD_DIR}/arch/arm/boot/uImage bootfs/
	cp -rf ${CB_PRODUCT_DIR}/u-boot.bin bootfs/linux/
	cp -rv ${CB_PRODUCT_DIR}/uEnv.txt bootfs/

	update_boot0 boot0_nand.bin   sys_config.bin NAND
	update_boot0 boot0_sdcard.fex sys_config.bin SDMMC_CARD
	update_boot1 boot1_nand.fex   sys_config.bin NAND
	update_boot1 boot1_sdcard.fex sys_config.bin SDMMC_CARD

	fsbuild bootfs.ini split_xxxx.fex
	mv bootfs.fex bootloader.fex

	ln -s ${CB_OUTPUT_DIR}/rootfs.ext4 rootfs.fex
	dragon image.cfg sys_partition.fex
	cd -
    )
}

cb_build_nand_image()
{
    cb_build_linux
    cb_build_nand_pack
}


cb_build_card_image()
{
    cb_build_linux

    sudo rm -rf ${CB_OUTPUT_DIR}/card0-part1 ${CB_OUTPUT_DIR}/card0-part2
    mkdir -pv ${CB_OUTPUT_DIR}/card0-part1 ${CB_OUTPUT_DIR}/card0-part2

    #part1
    cp -v ${CB_KBUILD_DIR}/arch/arm/boot/uImage ${CB_OUTPUT_DIR}/card0-part1
    fex2bin ${CB_PRODUCT_DIR}/configs/sys_config_mmc.fex ${CB_OUTPUT_DIR}/card0-part1/script.bin
    #cp -v ${CB_PRODUCT_DIR}/boot.scr ${CB_OUTPUT_DIR}/card0-part1/boot.scr
    cp -v ${CB_PRODUCT_DIR}/configs/uEnv-mmc.txt ${CB_OUTPUT_DIR}/card0-part1/uEnv.txt

    (cd ${CB_OUTPUT_DIR}/card0-part1;  tar -c *) |gzip -9 > ${CB_OUTPUT_DIR}/bootfs-part1.tar.gz

    #part2
    rm -rf /tmp/tmp_${CB_PRODUCT_NAME}
    mkdir /tmp/tmp_${CB_PRODUCT_NAME}
    sudo mount -o loop ${CB_PRODUCT_ROOTFS_IMAGE} /tmp/tmp_${CB_PRODUCT_NAME}
    (cd /tmp/tmp_${CB_PRODUCT_NAME}; sudo tar -cp *) |sudo tar -C ${CB_OUTPUT_DIR}/card0-part2 -xp
    sudo make -C ${CB_KSRC_DIR} O=${CB_KBUILD_DIR} ARCH=arm CROSS_COMPILE=${CB_CROSS_COMPILE} -j4 INSTALL_MOD_PATH=${CB_OUTPUT_DIR}/card0-part2 modules_install
    (cd ${CB_OUTPUT_DIR}/card0-part2; sudo tar -c * )|gzip -9 > ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
}

cb_install_card()
{
    local sd_dev=$1
    if cb_sd_sunxi_part $1
    then
	echo "Make sunxi partitons successfully"
    else
	echo "Make sunxi partitions failed"
	return 1
    fi

    mkdir /tmp/sdc1
    sudo mount /dev/${sd_dev}1 /tmp/sdc1
    sudo tar -C /tmp/sdc1 -xvf ${CB_OUTPUT_DIR}/bootfs-part1.tar.gz
    sync
    sudo umount /tmp/sdc1
    rm -rf /tmp/sdc1

    if cb_sd_make_boot2 $1 $U_BOOT_WITH_SPL
    then
	echo "Build successfully"
    else
	echo "Build failed"
	return 2
    fi

    mkdir /tmp/sdc2
    sudo mount /dev/${sd_dev}2 /tmp/sdc2
    sudo tar -C /tmp/sdc2 -xf ${CB_OUTPUT_DIR}/rootfs-part2.tar.gz
    sync
    sudo umount /tmp/sdc2
    rm -rf /tmp/sdc2

    return 0
}

cb_build_release()
{
    if [ ! -d ${CB_RELEASE_DIR} ]; then
        mkdir -pv ${CB_RELEASE_DIR}
    fi

    rm -rf ${CB_RELEASE_DIR}/*

    if [ -f ${CB_PACKBUILD_DIR}/livesuit_cubieboard3.img ]; then
        echo "copy livesuit image"
	mv  ${CB_PACKBUILD_DIR}/livesuit_cubieboard3.img ${CB_RELEASE_DIR}/${CB_PRODUCT_NAME}-nand.img
        gzip -c ${CB_RELEASE_DIR}/${CB_PRODUCT_NAME}-nand.img >  ${CB_RELEASE_DIR}/${CB_PRODUCT_NAME}-nand.img.gz
        md5sum  ${CB_RELEASE_DIR}/${CB_PRODUCT_NAME}-nand.img.gz > ${CB_RELEASE_DIR}/${CB_PRODUCT_NAME}-nand.img.gz.md5
        echo "login:linaro" > ${CB_RELEASE_DIR}/login_passwd.txt
        echo "passwd:linaro" >> ${CB_RELEASE_DIR}/login_passwd.txt
        awk 'NR == 1,NR == 3' ${CB_KSRC_DIR}/Makefile  > ${CB_RELEASE_DIR}/kernel_version.txt


        echo "copy kernel source"
        cp ${CB_KBUILD_DIR}/.config ${CB_RELEASE_DIR}/cubietruck_defconfig
        (
            cd ${CB_KSRC_DIR}
            git archive --prefix kernel-source/ HEAD |gzip > ${CB_RELEASE_DIR}/kernel-source.tar.gz
        )
        md5sum ${CB_RELEASE_DIR}/kernel-source.tar.gz > ${CB_RELEASE_DIR}/kernel-source.tar.gz.md5
        cp -rv ${CB_PRODUCT_DIR}/configs ${CB_RELEASE_DIR}/
        date +%Y%m%d > ${CB_RELEASE_DIR}/build.log

	cb_build_kernel_header
	mv $CB_OUTPUT_DIR/linux-header.tar.gz ${CB_RELEASE_DIR}/ 

	echo "done"
    fi

    if [ -f ${CB_KBUILD_DIR}/arch/arm/boot/uImage ]; then
	echo "copy kernel header"
        cb_build_kernel_header
    fi

    cp -v $CB_OUTPUT_DIR/*.tar.gz ${CB_RELEASE_DIR}/
    cp -v $U_BOOT_WITH_SPL ${CB_RELEASE_DIR}/
}



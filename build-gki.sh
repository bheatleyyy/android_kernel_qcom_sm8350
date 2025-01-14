#!/bin/bash
#
# Compile script for QuicksilveR kernel
# Copyright (C) 2020-2021 Adithya R.

SECONDS=0 # builtin bash timer
ZIPNAME="StormBreaker-lisa-$(date '+%Y%m%d-%H%M').zip"
TC_DIR="$HOME/wkspace/clang/clang-r450784b"
GCC_64_DIR="$HOME/wkspace/clang/aarch64-linux-android-4.9"
GCC_32_DIR="$HOME/wkspace/clang/arm-linux-androideabi-4.9"
AK3_DIR="AnyKernel3"
DEVICE="lisa"

if ! [ -d "${TC_DIR}" ]; then
echo "Clang not found! Cloning to ${TC_DIR}..."
if ! git clone --depth=1 https://gitlab.com/yaosp/prebuilts_clang_host_linux-x86_clang-r450784b ${TC_DIR}; then
echo "Cloning failed! Aborting..."
exit 1
fi
fi

if ! [ -d "${GCC_64_DIR}" ]; then
echo "gcc not found! Cloning to ${GCC_64_DIR}..."
if ! git clone --depth=1 -b lineage-19.1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git ${GCC_64_DIR}; then
echo "Cloning failed! Aborting..."
exit 1
fi
fi

if ! [ -d "${GCC_32_DIR}" ]; then
echo "gcc_32 not found! Cloning to ${GCC_32_DIR}..."
if ! git clone --depth=1 -b lineage-19.1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git ${GCC_32_DIR}; then
echo "Cloning failed! Aborting..."
exit 1
fi
fi

MAKE_PARAMS="O=out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 TARGET_PRODUCT=$DEVICE \
	CROSS_COMPILE=$GCC_64_DIR/bin/aarch64-linux-android- \
	CROSS_COMPILE_ARM32=$GCC_32_DIR/bin/arm-linux-androideabi-"

export PATH="$TC_DIR/bin:$PATH"

if [[ $2 = "-r" || $1 = "--regen" ]]; then
	make $MAKE_PARAMS $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
	exit
fi

if [[ $2 = "-c" || $1 = "--clean" ]]; then
	echo -e "\nCleaning output folder..."
	rm -rf out
fi

mkdir -p out
ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 CROSS_COMPILE=$GCC_64_DIR/bin/aarch64-linux-android- CROSS_COMPILE_ARM32=$GCC_32_DIR/bin/arm-linux-androideabi- scripts/kconfig/merge_config.sh -O out arch/arm64/configs/vendor/lahaina-qgki_defconfig arch/arm64/configs/vendor/xiaomi-sm8350_QGKI.config arch/arm64/configs/vendor/"$DEVICE"_QGKI.config

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) $MAKE_PARAMS || exit $?
make -j$(nproc --all) $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

kernel="out/arch/arm64/boot/Image"
dtb="out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb"
dtbo="out/arch/arm64/boot/dts/vendor/qcom/lisa-sm7325-overlay.dtbo"

if [ -f "$kernel" ] && [ -f "$dtb" ] && [ -f "$dtbo" ]; then
	echo -e "\nKernel compiled succesfully! Zipping up...\n"
	if [ -d "$AK3_DIR" ]; then
		cp -r $AK3_DIR AnyKernel3
	elif ! git clone -q https://github.com/ItsVixano/AnyKernel3 -b lisa-aosp; then
		echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
		exit 1
	fi
	cp $kernel AnyKernel3
	cp $dtb AnyKernel3/dtb
	python2 scripts/dtc/libfdt/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 $dtbo
	cp $(find out/modules/lib/modules/5.4* -name '*.ko') AnyKernel3/modules/vendor/lib/modules/
	cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} AnyKernel3/modules/vendor/lib/modules
	cp out/modules/lib/modules/5.4*/modules.order AnyKernel3/modules/vendor/lib/modules/modules.load
	sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' AnyKernel3/modules/vendor/lib/modules/modules.dep
	sed -i 's/.*\///g' AnyKernel3/modules/vendor/lib/modules/modules.load
	rm -rf out/arch/arm64/boot out/modules
	cd AnyKernel3
	git checkout lisa-aosp &> /dev/null
	zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo "Zip: $ZIPNAME"
	[ -x "$(command -v gdrive)" ] && gdrive upload --share "$ZIPNAME"
else
	echo -e "\nCompilation failed!"
	exit 1
fi

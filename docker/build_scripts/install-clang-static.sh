#!/bin/bash
# Install packages that will be needed at runtime

# Stop at any error, show all commands
set -exuo pipefail

# Set build environment variables
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
# shellcheck source-path=SCRIPTDIR
source "${MY_DIR}/build_utils.sh"

case "${BASE_POLICY}-${AUDITWHEEL_ARCH}" in
	manylinux-armv7l) TARGET_TRIPLET=arm-unknown-linux-gnueabihf;;
	musllinux-armv7l) TARGET_TRIPLET=armv7-alpine-linux-musleabihf;;
	manylinux-ppc64le) TARGET_TRIPLET=powerpc64le-none-linux-gnu;;
	musllinux-ppc64le) TARGET_TRIPLET=powerpc64le-alpine-linux-musl;;
	musllinux-i686) TARGET_TRIPLET=i586-alpine-linux-musl;;
	manylinux-riscv64) TARGET_TRIPLET=riscv64-redhat-linux;;
	manylinux-*) TARGET_TRIPLET=${AUDITWHEEL_ARCH}-none-linux-gnu;;
	musllinux-*) TARGET_TRIPLET=${AUDITWHEEL_ARCH}-alpine-linux-musl;;
esac
case "${AUDITWHEEL_ARCH}" in
	riscv64) M_ARCH="-march=rv64gc";;
esac

for TOOLCHAIN_ARCH in aarch64 x86_64; do
	TOOLCHAIN_PATH=/opt/clang-static-${TOOLCHAIN_ARCH}
	mkdir -p ${TOOLCHAIN_PATH}
	case ${TOOLCHAIN_ARCH} in
		aarch64) GOARCH=arm64;;
		x86_64) GOARCH=amd64;;
	esac
	curl -fsSL https://github.com/dzbarsky/static-clang/releases/download/v19.1.6/linux_${GOARCH}_minimal.tar.xz | tar -C ${TOOLCHAIN_PATH} -xJ
	ln -s clang ${TOOLCHAIN_PATH}/bin/gcc
	ln -s clang ${TOOLCHAIN_PATH}/bin/cc
	ln -s clang-cpp ${TOOLCHAIN_PATH}/bin/cpp
	ln -s clang++ ${TOOLCHAIN_PATH}/bin/g++
	ln -s clang++ ${TOOLCHAIN_PATH}/bin/c++
	ln -s llvm-ar ${TOOLCHAIN_PATH}/bin/ar
	ln -s llvm-nm ${TOOLCHAIN_PATH}/bin/nm
	ln -s llvm-objcopy ${TOOLCHAIN_PATH}/bin/objcopy
	ln -s llvm-objdump ${TOOLCHAIN_PATH}/bin/objdump
	ln -s llvm-strip ${TOOLCHAIN_PATH}/bin/strip

	cat<<EOF >"${TOOLCHAIN_PATH}/bin/${AUDITWHEEL_PLAT}.cfg"
	-target ${TARGET_TRIPLET}
	${M_ARCH:-}
	--gcc-toolchain=${DEVTOOLSET_ROOTPATH:-}/usr
EOF

	cat<<EOF >${TOOLCHAIN_PATH}/bin/clang.cfg
	@${AUDITWHEEL_PLAT}.cfg
	-fuse-ld=lld
EOF
	cat<<EOF >${TOOLCHAIN_PATH}/bin/clang++.cfg
	@${AUDITWHEEL_PLAT}.cfg
	-fuse-ld=lld
EOF
	cat<<EOF >${TOOLCHAIN_PATH}/bin/clang-cpp.cfg
	@${AUDITWHEEL_PLAT}.cfg
EOF

done

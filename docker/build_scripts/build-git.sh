#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
# shellcheck source-path=SCRIPTDIR
source "${MY_DIR}/build_utils.sh"

# cross-compilation setup
# TODO move this in a helper file
case "${BASE_POLICY}-${AUDITWHEEL_ARCH}" in
  manylinux-armv7l) TARGET_TRIPLET=arm-unknown-linux-gnueabihf;;
  musllinux-armv7l) TARGET_TRIPLET=arm-unknown-linux-musleabihf;;
	manylinux-ppc64le) TARGET_TRIPLET=powerpc64le-none-linux-gnu;;
	musllinux-ppc64le) TARGET_TRIPLET=powerpc64le-none-linux-musl;;
	manylinux-*) TARGET_TRIPLET=${AUDITWHEEL_ARCH}-none-linux-gnu;;
	musllinux-*) TARGET_TRIPLET=${AUDITWHEEL_ARCH}-none-linux-musl;;
esac
case "${AUDITWHEEL_ARCH}" in
	riscv64) M_ARCH="-march=rva20u64";;
esac
if [ "${DEVTOOLSET_ROOTPATH:-}" == "" ]; then
	GCC_TOOLCHAIN="/rootfs"
else
	GCC_TOOLCHAIN="/rootfs${DEVTOOLSET_ROOTPATH}"
fi

touch /tmp/main.cpp
clang-19 -fuse-ld=lld -v -target ${TARGET_TRIPLET} ${M_ARCH:-} --sysroot=/rootfs --gcc-toolchain=${GCC_TOOLCHAIN} /tmp/main.cpp

if [ "${BASE_POLICY}" == "musllinux" ]; then
	export NO_REGEX=NeedsStartEnd
fi

if [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	export NO_UNCOMPRESS2=1
	CSPRNG_METHOD=urandom
	# workaround build issue when openssl gets included
	# git provides its own implementation of ctypes which conflicts
	# with the one in CentOS 7. Just use the one from git.
	# echo "" > /usr/include/ctype.h
	mkdir -p /tmp/centos7/include
	touch /tmp/centos7/include/ctype.h
	MANYLINUX_CPPFLAGS="-I/tmp/centos7/include ${MANYLINUX_CPPFLAGS}"
else
	CSPRNG_METHOD=getrandom
fi

if [ -d /rootfs/opt/_internal ]; then
	CURL_PREFIX=$(find /rootfs/opt/_internal -maxdepth 1 -name 'curl-*')
	if [ "${CURL_PREFIX}" != "" ]; then
		export CURLDIR=${CURL_PREFIX}
		CURL_LDFLAGS="-Wl,-rpath=${CURL_PREFIX:7}/lib -L${CURL_PREFIX}/lib $("${CURL_PREFIX}/bin/curl-config" --libs)"
		export CURL_LDFLAGS
		mkdir -p /manylinux-rootfs
		cp -rf /rootfs/manylinux-rootfs/* /manylinux-rootfs
	fi
fi
# Install newest git
check_var "${GIT_ROOT}"
check_var "${GIT_HASH}"
check_var "${GIT_DOWNLOAD_URL}"

fetch_source "${GIT_ROOT}.tar.gz" "${GIT_DOWNLOAD_URL}"
check_sha256sum "${GIT_ROOT}.tar.gz" "${GIT_HASH}"
tar -xzf "${GIT_ROOT}.tar.gz"
pushd "${GIT_ROOT}"
make install prefix=/usr/local \
  V=1 \
  NO_GETTEXT=1 \
  NO_TCLTK=1 \
  INSTALL_STRIP=-s \
  CSPRNG_METHOD=${CSPRNG_METHOD} \
  DESTDIR=/manylinux-rootfs \
  "HOST_CPU=${AUDITWHEEL_ARCH}" \
  AR="llvm-ar-19" \
  CC="clang-19 -target ${TARGET_TRIPLET} ${M_ARCH:-} --sysroot=/rootfs --gcc-toolchain=${GCC_TOOLCHAIN}" \
  LD="lld-19" \
  OBJCOPY="llvm-objcopy-19" \
  STRIP="llvm-strip-19" \
  CPPFLAGS="${MANYLINUX_CPPFLAGS}" \
  CFLAGS="${MANYLINUX_CFLAGS}" \
  CXXFLAGS="${MANYLINUX_CXXFLAGS}" \
  LDFLAGS="-fuse-ld=lld ${MANYLINUX_LDFLAGS}"
popd
rm -rf "${GIT_ROOT}" "${GIT_ROOT}.tar.gz"

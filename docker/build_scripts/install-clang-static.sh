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

TOOLCHAIN_PATH="$1"
ln -s clang "${TOOLCHAIN_PATH}/bin/gcc"
ln -s clang "${TOOLCHAIN_PATH}/bin/cc"
ln -s clang-cpp "${TOOLCHAIN_PATH}/bin/cpp"
ln -s clang++ "${TOOLCHAIN_PATH}/bin/g++"
ln -s clang++ "${TOOLCHAIN_PATH}/bin/c++"

cat<<EOF >"${TOOLCHAIN_PATH}/bin/${AUDITWHEEL_PLAT}.cfg"
	-target ${TARGET_TRIPLET}
	${M_ARCH:-}
	--gcc-toolchain=${DEVTOOLSET_ROOTPATH:-}/usr
EOF

cat<<EOF >"${TOOLCHAIN_PATH}/bin/clang.cfg"
	@${AUDITWHEEL_PLAT}.cfg
	-fuse-ld=lld
EOF
cat<<EOF >"${TOOLCHAIN_PATH}/bin/clang++.cfg"
	@${AUDITWHEEL_PLAT}.cfg
	-fuse-ld=lld
EOF
cat<<EOF >"${TOOLCHAIN_PATH}/bin/clang-cpp.cfg"
	@${AUDITWHEEL_PLAT}.cfg
EOF

cat<<EOF >"${TOOLCHAIN_PATH}/entrypoint"
#!/bin/bash

set -eu

export PATH="${TOOLCHAIN_PATH}/bin:\${PATH}"
exec manylinux-entrypoint "\$@"
EOF

chmod +x "${TOOLCHAIN_PATH}/entrypoint"

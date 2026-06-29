#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
# shellcheck source-path=SCRIPTDIR
source "${MY_DIR}/build_utils.sh"

if [ "${BASE_POLICY}" == "musllinux" ]; then
	export NO_REGEX=NeedsStartEnd
fi

# Install newest git

fetch_source "${GIT_ROOT}.tar.gz" "${GIT_DOWNLOAD_URL}" "${GIT_HASH}"
tar -xzf "${GIT_ROOT}.tar.gz"
pushd "${GIT_ROOT}"
make install \
	prefix=/usr/local \
	NO_GETTEXT=1 \
	NO_TCLTK=1 \
	NO_RUST=1 \
	INSTALL_SYMLINKS=1 \
	INSTALL_STRIP=-s \
	DESTDIR=/manylinux-rootfs \
	CSPRNG_METHOD=getrandom \
	CPPFLAGS="${MANYLINUX_CPPFLAGS}" \
	CFLAGS="${MANYLINUX_CFLAGS}" \
	CXXFLAGS="${MANYLINUX_CXXFLAGS}" \
	LDFLAGS="${MANYLINUX_LDFLAGS}"
popd
rm -rf "${GIT_ROOT}" "${GIT_ROOT}.tar.gz"

# Install
cp -rlf /manylinux-rootfs/* /

git version

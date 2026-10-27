#!/bin/bash
# Install packages that will be needed at runtime

# Stop at any error, show all commands
set -exuo pipefail

# Set build environment variables
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
# shellcheck source-path=SCRIPTDIR
source "${MY_DIR}/build_utils.sh"

# Libraries that are allowed as part of the manylinux2014 profile
# Extract from PEP: https://www.python.org/dev/peps/pep-0599/#the-manylinux2014-policy
# On RPM-based systems, they are provided by these packages:
# Package:    Libraries
# glib2:      libglib-2.0.so.0, libgthread-2.0.so.0, libgobject-2.0.so.0
# glibc:      libresolv.so.2, libutil.so.1, libnsl.so.1, librt.so.1, libpthread.so.0, libdl.so.2, libm.so.6, libc.so.6
# libICE:     libICE.so.6
# libX11:     libX11.so.6
# libXext:    libXext.so.6
# libXrender: libXrender.so.1
# libgcc:     libgcc_s.so.1
# libstdc++:  libstdc++.so.6
# mesa:       libGL.so.1
#
# PEP is missing the package for libSM.so.6 for RPM based system
#
# With PEP600, more packages are allowed by auditwheel policies
# - libz.so.1
# - libexpat.so.1


# MANYLINUX_DEPS: Install development packages (except for libgcc which is provided by gcc install)
if [ "${OS_ID_LIKE}" == "rhel" ]; then
	MANYLINUX_DEPS=(glibc-devel libstdc++-devel glib2-devel libX11-devel libXext-devel libXrender-devel mesa-libGL-devel libICE-devel libSM-devel zlib-devel expat-devel)
elif [ "${OS_ID_LIKE}" == "debian" ]; then
  MANYLINUX_DEPS=(libc6-dev libglib2.0-dev libx11-dev libxext-dev libxrender-dev libgl1-mesa-dev libice-dev libsm-dev zlib1g-dev libexpat1-dev)
elif [ "${OS_ID_LIKE}" == "alpine" ]; then
	MANYLINUX_DEPS=(musl-dev libstdc++ glib-dev libx11-dev libxext-dev libxrender-dev mesa-dev libice-dev libsm-dev zlib-dev expat-dev)
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

# RUNTIME_DEPS: Runtime dependencies. c.f. install-build-packages.sh
if [ "${OS_ID_LIKE}" == "rhel" ]; then
	RUNTIME_DEPS=(zlib bzip2 expat ncurses readline gdbm xz openssl libcurl uuid libffi tk)
	if [ "${AUDITWHEEL_POLICY}" != "manylinux_2_28" ]; then
		# for graalpy
		RUNTIME_DEPS+=(libxcrypt-compat)
	fi
elif [ "${OS_ID_LIKE}" == "debian" ]; then
  RUNTIME_DEPS=(zlib1g libbz2-1.0 libexpat1 libffi8 libncurses6 libreadline8 tk libgdbm6 libdb5.3 libssl3 liblzma5 libcurl4 uuid)
elif [ "${OS_ID_LIKE}" == "alpine" ]; then
	RUNTIME_DEPS=(zlib bzip2 expat ncurses-libs readline tk gdbm xz openssl libcurl libuuid libffi)
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

BASE_TOOLS=(autoconf automake bison bzip2 ca-certificates curl diffutils file make patch unzip)
if [ "${OS_ID_LIKE}" == "rhel" ]; then
	BASE_TOOLS+=(glibc-locale-source glibc-langpack-en gnupg2 gzip hardlink hostname libcurl libxcrypt tar which)
	if [ "${AUDITWHEEL_ARCH}" != "loongarch64" ]; then
		BASE_TOOLS+=(libnsl)
	fi
	echo "tsflags=nodocs" >> /etc/dnf/dnf.conf
	EPEL=epel-release
	if [ "${AUDITWHEEL_ARCH}" == "i686" ] || [ "${AUDITWHEEL_ARCH}" == "riscv64" ]; then
		EPEL=
	elif [ "${AUDITWHEEL_ARCH}" == "loongarch64" ]; then
		EPEL=anolis-epao-release
	fi
	dnf -y install dnf-plugins-core ${EPEL}
	if [ "${AUDITWHEEL_POLICY}" == "manylinux_2_28" ]; then
		dnf config-manager --set-enabled powertools
	elif [ "${AUDITWHEEL_ARCH}" != "loongarch64" ]; then
		dnf config-manager --set-enabled crb
	fi
	dnf -y upgrade --nobest
	if [ "${AUDITWHEEL_POLICY}" == "manylinux_2_28" ] || [ "${AUDITWHEEL_POLICY}" == "manylinux_2_34" ] || [ "${AUDITWHEEL_POLICY}" == "manylinux_2_38" ]; then
		TOOLCHAIN_DEPS=(gcc-toolset-14-binutils gcc-toolset-14-gcc gcc-toolset-14-gcc-c++ gcc-toolset-14-gcc-gfortran gcc-toolset-14-libatomic-devel)
	else
		# TODO enable gcc-toolset-15 once available (probably in 10.1)
		# TOOLCHAIN_DEPS=(gcc-toolset-15-binutils gcc-toolset-15-gcc gcc-toolset-15-gcc-c++ gcc-toolset-15-gcc-gfortran gcc-toolset-15-libatomic-devel)
		TOOLCHAIN_DEPS=(binutils gcc gcc-c++ gcc-gfortran libatomic)
	fi
elif [ "${OS_ID_LIKE}" == "debian" ]; then
	TOOLCHAIN_DEPS+=(binutils gcc g++ gfortran libatomic1)
	BASE_TOOLS+=(gpg gpg-agent hardlink hostname locales xz-utils)
elif [ "${OS_ID_LIKE}" == "alpine" ]; then
	TOOLCHAIN_DEPS=(binutils gcc g++ gfortran libatomic)
	BASE_TOOLS+=(gnupg util-linux shadow tar)
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi
if [ "${AUDITWHEEL_ARCH}" == "x86_64" ]; then
	TOOLCHAIN_DEPS+=(yasm)
fi

manylinux_pkg_install "${BASE_TOOLS[@]}" "${TOOLCHAIN_DEPS[@]}" "${MANYLINUX_DEPS[@]}" "${RUNTIME_DEPS[@]}"

# update system packages, we already updated them but
# the following script takes care of cleaning-up some things
# and since it's also needed in the finalize step, everything's
# centralized in this script to avoid code duplication
LC_ALL=C "${MY_DIR}/update-system-packages.sh"

if [ "${BASE_POLICY}" == "manylinux" ]; then
	# we'll be removing libcrypt.so.1 later on
	# this is needed to ensure the new one will be found
	# as LD_LIBRARY_PATH does not seem enough.
	# c.f. https://github.com/pypa/manylinux/issues/1022
	# we also want to keep those standard build directories searched by ld
	# c.f. https://github.com/pypa/manylinux/issues/1886
	echo "/usr/local/lib" > /etc/ld.so.conf.d/00-manylinux.conf
	if [ -d "/usr/local/lib64" ]; then
		echo "/usr/local/lib64" >> /etc/ld.so.conf.d/00-manylinux.conf
	fi
	ldconfig
else
	# set the default shell to bash
	chsh -s /bin/bash root
	useradd -D -s /bin/bash
fi

if [ "${OS_ID_LIKE}-${AUDITWHEEL_ARCH}" == "rhel-i686" ] && [ -f /usr/bin/i686-redhat-linux-gnu-pkg-config ] && [ ! -f /usr/bin/i386-redhat-linux-gnu-pkg-config ]; then
	ln -s i686-redhat-linux-gnu-pkg-config /usr/bin/i386-redhat-linux-gnu-pkg-config
fi
